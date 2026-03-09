//+------------------------------------------------------------------+
//|                                             GoldBreakoutEA.mq5   |
//|                                             Just Write!          |
//+------------------------------------------------------------------+
#property copyright "Just Write!"
#property link      "https://github.com/Lechcher"
#property version   "1.07"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums for Modes
enum ENUM_LOT_MODE {
   Fixed_Lots,     // Fixed Lot Size
   Risk_Percent    // Dynamic Risk (%)
};

enum ENUM_TPSL_MODE {
   Fixed_Points,   // Fixed Points
   ATR_Dynamic     // ATR-Based Dynamic
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string                 Section1 = "--- Trade & Risk Management ---";
input bool                    Restrict_To_Gold   = false;             // Restrict EA to Gold Only
input ENUM_LOT_MODE           Lot_Size_Mode      = Risk_Percent;     // Lot Size Mode
input double                  Lots               = 0.01;              // Fixed Lots
input double                  RiskPercent        = 0.1;              // Risk % of Free Margin
input int                     Max_Spread_Points  = 50;               // Maximum Allowed Spread (Points)
input ulong                   Magic              = 111;              // Magic Number

sinput string                 Section2 = "--- Strategy & Breakout Settings ---";
input ENUM_TIMEFRAMES         Timeframe          = PERIOD_M15;       // Calculation Timeframe
input int                     BarsN              = 15;               // Lookback Bars for High/Low
input int                     OrderDistPoints    = 100;              // Buffer Distance from High/Low (Points)
input int                     ExpirationHours    = 1;                // Pending Order Expiration (Hours)

sinput string                 Section3 = "--- Higher Timeframe Trend Filter ---";
input bool                    Use_Trend_Filter   = true;             // Use Trend Filter
input ENUM_TIMEFRAMES         Trend_Timeframe    = PERIOD_H1;        // Trend Timeframe
input int                     Trend_MA_Period    = 50;               // Trend MA Period
input ENUM_MA_METHOD          Trend_MA_Method    = MODE_EMA;         // Trend MA Method

sinput string                 Section4 = "--- TP & SL Calculation Mode ---";
input ENUM_TPSL_MODE          TPSL_Mode          = Fixed_Points;     // TP/SL Mode
input int                     TpPoints           = 1000;             // Fixed TP (Points)
input int                     SlPoints           = 300;              // Fixed SL (Points)
input int                     ATR_Period         = 14;               // ATR Period
input double                  ATR_TP_Multiplier  = 6.0;              // ATR Multiplier for TP
input double                  ATR_SL_Multiplier  = 2.0;              // ATR Multiplier for SL

sinput string                 Section5 = "--- Trailing Stop Settings ---";
input int                     TslTriggerPoints   = 150;              // TSL Activation Profit (Points)
input int                     TslPoints          = 100;              // TSL Trailing Distance (Points)

sinput string                 Section6 = "--- Weekend Gap Protection ---";
input bool                    Close_On_Friday    = true;             // Close All Trades on Friday
input int                     Friday_Close_Hour  = 22;               // Friday Close Hour (Server Time)
input int                     Friday_Close_Minute= 45;               // Friday Close Minute (Server Time)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES & OBJECTS                                       |
//+------------------------------------------------------------------+
CTrade         trade;
CSymbolInfo    symInfo;

int            atr_handle;    // Handle for the ATR indicator
int            ma_handle = INVALID_HANDLE; // Handle for the Trend MA indicator
int            p_adj = 1;     // Point multiplier for 3/5 digit brokers

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION FUNCTION                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Restrict EA to XAUUSD / Gold only to prevent accidental runs on unsupported pairs
   if(Restrict_To_Gold)
   {
      string current_sym = _Symbol;
      StringToUpper(current_sym); // Make case-insensitive to catch 'xauusd' or 'gold'
      
      if(StringFind(current_sym, "XAU") < 0 && StringFind(current_sym, "GOLD") < 0)
      {
         Print("Initialization Failed: This EA is exclusively optimized for Gold. Current symbol: ", _Symbol);
         return INIT_FAILED;
      }
   }

   // Initialize Symbol Info
   if(!symInfo.Name(_Symbol)) return INIT_FAILED;
   
   // Handle 2-digit vs 3-digit Gold (and 4 vs 5 digit forex)
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) p_adj = 10;
   else p_adj = 1;
   
   // Setup Trade Class
   trade.SetExpertMagicNumber(Magic);
   
   // Setup ATR Indicator
   if(TPSL_Mode == ATR_Dynamic)
   {
      atr_handle = iATR(_Symbol, Timeframe, ATR_Period);
      if(atr_handle == INVALID_HANDLE)
      {
         Print("Error initializing ATR indicator");
         return INIT_FAILED;
      }
   }
   
   // Setup Trend MA Indicator
   if(Use_Trend_Filter)
   {
      ma_handle = iMA(_Symbol, Trend_Timeframe, Trend_MA_Period, 0, Trend_MA_Method, PRICE_CLOSE);
      if(ma_handle == INVALID_HANDLE)
      {
         Print("Error initializing Trend MA indicator");
         return INIT_FAILED;
      }
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION FUNCTION                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
      
   if(ma_handle != INVALID_HANDLE)
      IndicatorRelease(ma_handle);
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Market Open Check (Prevents [Market closed] spam during daily breaks) ---
   if(!IsMarketOpen()) return;

   symInfo.RefreshRates();
   
   // --- Weekend Gap Protection (Highest Priority) ---
   // This MUST be before the Spread Check, otherwise wide spreads right at market close 
   // will prevent the EA from successfully closing weekend trades.
   if(!IsTradingAllowed())
   {
      CloseAllTradesAndOrders();
      return; // Block EA from placing any new orders or managing trades
   }
   
   // 1. Spread Check
   double current_spread = (symInfo.Ask() - symInfo.Bid()) / _Point;
   if(current_spread > Max_Spread_Points * p_adj)
      return; // Do not trade or manage if spread is too wide
      
   // 2. Manage Trailing Stop
   ManageTrailingStop();
   
   // 3. Check existing positions and pending orders (OCO Logic)
   int pos_count = 0;
   bool has_buy_stop = false;
   bool has_sell_stop = false;
   ulong buy_stop_ticket = 0;
   ulong sell_stop_ticket = 0;
   
   // Count Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
         pos_count++;
   }
   
   // Count Pending Orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic)
      {
         if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
         {
            has_buy_stop = true;
            buy_stop_ticket = ticket;
         }
         if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
         {
            has_sell_stop = true;
            sell_stop_ticket = ticket;
         }
      }
   }
   
   // OCO Logic: If we have an active position, delete any remaining pending orders
   if(pos_count > 0)
   {
      static datetime last_oco_time = 0;
      
      // NEW METHOD: Relaxed OCO Throttle. Wait 60 seconds between retries to prevent log spam.
      if(TimeCurrent() - last_oco_time >= 60) 
      {
         bool oco_attempt = false;
         if(has_buy_stop) { trade.OrderDelete(buy_stop_ticket); oco_attempt = true; }
         if(has_sell_stop) { trade.OrderDelete(sell_stop_ticket); oco_attempt = true; }
         
         if(oco_attempt) last_oco_time = TimeCurrent();
      }
      return; // Do not place new breakouts while in a trade
   }
   
   // 4. Trend Filter Logic
   bool allow_buy = true;
   bool allow_sell = true;
   
   if(Use_Trend_Filter)
   {
      double ma_buffer[];
      ArraySetAsSeries(ma_buffer, true);
      if(CopyBuffer(ma_handle, 0, 0, 1, ma_buffer) > 0)
      {
         double current_price = symInfo.Bid();
         if(current_price <= ma_buffer[0]) allow_buy = false;  // Strictly above for Buy
         if(current_price >= ma_buffer[0]) allow_sell = false; // Strictly below for Sell
      }
   }
   
   // Delete pending orders that violate the trend filter
   static datetime last_trend_del_time = 0;
   if((!allow_buy && has_buy_stop) || (!allow_sell && has_sell_stop))
   {
      // Throttle deletion attempts to prevent log spam if the broker is frozen
      if(TimeCurrent() - last_trend_del_time >= 60)
      {
         if(!allow_buy && has_buy_stop) { trade.OrderDelete(buy_stop_ticket); has_buy_stop = false; }
         if(!allow_sell && has_sell_stop) { trade.OrderDelete(sell_stop_ticket); has_sell_stop = false; }
         last_trend_del_time = TimeCurrent();
      }
   }
   
   // 5. Breakout Logic (Place or Update Pending Orders)
   double high_arr[], low_arr[];
   ArraySetAsSeries(high_arr, true);
   ArraySetAsSeries(low_arr, true);
   
   // Get Highs and Lows (Shift 1 to ignore current forming bar)
   if(CopyHigh(_Symbol, Timeframe, 1, BarsN, high_arr) <= 0) return;
   if(CopyLow(_Symbol, Timeframe, 1, BarsN, low_arr) <= 0) return;
   
   double highest_high = high_arr[ArrayMaximum(high_arr, 0, BarsN)];
   double lowest_low = low_arr[ArrayMinimum(low_arr, 0, BarsN)];
   
   // Calculate Order Prices
   double buffer_dist = OrderDistPoints * p_adj * _Point;
   double buy_price = highest_high + buffer_dist;
   double sell_price = lowest_low - buffer_dist;
   
   // Ensure orders are not placed or modified too close to current price (Stops Level / Freeze Level)
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_level_dist = (double)MathMax(stops_level, freeze_level) * _Point;
   if(min_level_dist == 0) min_level_dist = 5 * p_adj * _Point; // Safety fallback
   
   bool valid_buy_price = (buy_price >= symInfo.Ask() + min_level_dist);
   bool valid_sell_price = (sell_price <= symInfo.Bid() - min_level_dist);
   
   // Calculate TP and SL actual price distances
   double tp_dist_price = 0, sl_dist_price = 0;
   GetSLTPDistances(tp_dist_price, sl_dist_price);
   
   // Enforce broker's minimum Stops Level for SL and TP distances to prevent [Invalid stops]
   if(sl_dist_price < min_level_dist) sl_dist_price = min_level_dist;
   if(tp_dist_price < min_level_dist) tp_dist_price = min_level_dist;
   
   // Calculate Lot Size dynamically based on SL distance
   double lot_size = GetLotSize(sl_dist_price);
   
   // Expiration Time
   datetime expiration = TimeCurrent() + (datetime)(ExpirationHours * 3600);
   
   // Normalize prices to the broker's specific tick size to prevent micro-fraction rounding errors
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = _Point; // Safety fallback
   
   buy_price = MathRound(buy_price / tick_size) * tick_size;
   sell_price = MathRound(sell_price / tick_size) * tick_size;
   
   double buy_sl = MathRound((buy_price - sl_dist_price) / tick_size) * tick_size;
   double buy_tp = MathRound((buy_price + tp_dist_price) / tick_size) * tick_size;
   
   double sell_sl = MathRound((sell_price + sl_dist_price) / tick_size) * tick_size;
   double sell_tp = MathRound((sell_price - tp_dist_price) / tick_size) * tick_size;
   
   // Strict modification threshold (Require at least 3 points of change to prevent tick spam)
   double modify_threshold = 3 * p_adj * _Point;
   
   // Manage Buy Stop Order
   if(allow_buy && valid_buy_price)
   {
      if(!has_buy_stop)
      {
         trade.BuyStop(lot_size, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_SPECIFIED, expiration);
      }
      else
      {
         double current_buy_price = OrderGetDouble(ORDER_PRICE_OPEN);
         double current_buy_sl    = OrderGetDouble(ORDER_SL);
         double current_buy_tp    = OrderGetDouble(ORDER_TP);
         
         // Only modify if Price, SL, or TP changed substantially (filters out ATR micro-fluctuations)
         if(MathAbs(current_buy_price - buy_price) > modify_threshold || 
            MathAbs(current_buy_sl - buy_sl) > modify_threshold || 
            MathAbs(current_buy_tp - buy_tp) > modify_threshold) 
         {
            // Verify the existing order isn't frozen before trying to modify it
            if(current_buy_price >= symInfo.Ask() + min_level_dist)
               trade.OrderModify(buy_stop_ticket, buy_price, buy_sl, buy_tp, ORDER_TIME_SPECIFIED, expiration);
         }
      }
   }
   
   // Manage Sell Stop Order
   if(allow_sell && valid_sell_price)
   {
      if(!has_sell_stop)
      {
         trade.SellStop(lot_size, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_SPECIFIED, expiration);
      }
      else
      {
         double current_sell_price = OrderGetDouble(ORDER_PRICE_OPEN);
         double current_sell_sl    = OrderGetDouble(ORDER_SL);
         double current_sell_tp    = OrderGetDouble(ORDER_TP);
         
         // Only modify if Price, SL, or TP changed substantially (filters out ATR micro-fluctuations)
         if(MathAbs(current_sell_price - sell_price) > modify_threshold || 
            MathAbs(current_sell_sl - sell_sl) > modify_threshold || 
            MathAbs(current_sell_tp - sell_tp) > modify_threshold) 
         {
            // Verify the existing order isn't frozen before trying to modify it
            if(current_sell_price <= symInfo.Bid() - min_level_dist)
               trade.OrderModify(sell_stop_ticket, sell_price, sell_sl, sell_tp, ORDER_TIME_SPECIFIED, expiration);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CALCULATE TP & SL DISTANCES (IN PRICE VALUE)                     |
//+------------------------------------------------------------------+
void GetSLTPDistances(double &tp_dist_price, double &sl_dist_price)
{
   if(TPSL_Mode == Fixed_Points)
   {
      tp_dist_price = TpPoints * p_adj * _Point;
      sl_dist_price = SlPoints * p_adj * _Point;
   }
   else // ATR_Dynamic
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      
      if(CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) > 0) // Shift 1 (last closed bar)
      {
         tp_dist_price = atr_buffer[0] * ATR_TP_Multiplier;
         sl_dist_price = atr_buffer[0] * ATR_SL_Multiplier;
      }
      else
      {
         // Fallback to fixed points if ATR fails to load temporarily
         tp_dist_price = TpPoints * p_adj * _Point;
         sl_dist_price = SlPoints * p_adj * _Point;
      }
   }
}

//+------------------------------------------------------------------+
//| LOT SIZE CALCULATION (RISK MANAGEMENT)                           |
//+------------------------------------------------------------------+
double GetLotSize(double sl_dist_price)
{
   if(Lot_Size_Mode == Fixed_Lots) return Lots;

   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double risk_money = free_margin * (RiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Failsafe checks
   if(sl_dist_price <= 0 || tick_size <= 0 || tick_value <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   // Calculate loss in currency for 1 standard lot
   double loss_per_lot = (sl_dist_price / tick_size) * tick_value;
   if(loss_per_lot == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   // Calculate raw lot size
   double lot_calc = risk_money / loss_per_lot;

   // Normalize Volume strictly to Broker requirements
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot_calc = MathFloor(lot_calc / vol_step) * vol_step;
   
   if(lot_calc < vol_min) lot_calc = vol_min;
   if(lot_calc > vol_max) lot_calc = vol_max;

   return NormalizeDouble(lot_calc, 2); 
}

//+------------------------------------------------------------------+
//| TRAILING STOP MANAGEMENT                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(TslTriggerPoints <= 0 || TslPoints <= 0) return;

   double tsl_trigger_price = TslTriggerPoints * p_adj * _Point;
   double tsl_dist_price = TslPoints * p_adj * _Point;
   
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = _Point; // Safety fallback
   
   // Require the SL to move by at least this amount before sending a server request (prevents tick spam)
   double min_step = 5 * p_adj * _Point; 

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
      {
         // Refresh rates per position to guarantee absolute precision during fast breakouts
         symInfo.RefreshRates();
         
         // Factor in Stops Level, Freeze Level, AND Spread dynamically
         long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         long freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
         long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         
         double min_stop_level = (double)MathMax(MathMax(stops_level, freeze_level), spread * 1.5) * _Point;
         if(min_stop_level == 0) min_stop_level = 5 * p_adj * _Point; // Safety fallback
         min_stop_level += 5 * p_adj * _Point; // Extra 5-point thick cushion
         
         // Prevent SL from crashing into TP. Must respect the widest of TslPoints or Broker Minimums.
         double min_dist_to_tp = MathMax(tsl_dist_price, min_stop_level);
         
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         long type = PositionGetInteger(POSITION_TYPE);

         if(type == POSITION_TYPE_BUY)
         {
            // 0. FREEZE CHECK: If price is already too close to TP or SL, broker locks the position
            if(tp > 0.0 && MathAbs(tp - symInfo.Bid()) <= min_stop_level) continue;
            if(sl > 0.0 && MathAbs(symInfo.Bid() - sl) <= min_stop_level) continue;
            
            if(symInfo.Bid() - open_price >= tsl_trigger_price)
            {
               double new_sl = symInfo.Bid() - tsl_dist_price;
               new_sl = MathRound(new_sl / tick_size) * tick_size;
               
               // 1. Move SL significantly closer. 2. Outside freeze/stop levels from Bid.
               if(new_sl > sl + min_step && new_sl <= symInfo.Bid() - min_stop_level)
               {
                  // 3. Stop trailing if the SL gets too close to the TP to prevent broker rejection.
                  if(tp == 0.0 || (tp - new_sl) >= min_dist_to_tp)
                  {
                     trade.PositionModify(ticket, new_sl, tp);
                  }
               }
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            // 0. FREEZE CHECK: If price is already too close to TP or SL, broker locks the position
            if(tp > 0.0 && MathAbs(symInfo.Ask() - tp) <= min_stop_level) continue;
            if(sl > 0.0 && MathAbs(sl - symInfo.Ask()) <= min_stop_level) continue;
            
            if(open_price - symInfo.Ask() >= tsl_trigger_price)
            {
               double new_sl = symInfo.Ask() + tsl_dist_price;
               new_sl = MathRound(new_sl / tick_size) * tick_size;
               
               // 1. Move SL significantly closer. 2. Outside freeze/stop levels from Ask.
               if((sl == 0.0 || new_sl < sl - min_step) && new_sl >= symInfo.Ask() + min_stop_level)
               {
                  // 3. Stop trailing if the SL gets too close to the TP to prevent broker rejection.
                  if(tp == 0.0 || (new_sl - tp) >= min_dist_to_tp)
                  {
                     trade.PositionModify(ticket, new_sl, tp);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK IF MARKET IS OPEN (PREVENTS DAILY BREAK ERROR SPAM)        |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return false;

   MqlDateTime dt;
   TimeCurrent(dt);

   datetime from, to;
   bool session_exists = false;
   
   // Convert current time to seconds from the start of the day
   long current_sec = dt.hour * 3600 + dt.min * 60 + dt.sec;

   // Check all defined trading sessions for the current day of the week
   for(int i = 0; i < 10; i++)
   {
      if(SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
      {
         session_exists = true;
         if(current_sec >= (long)from && current_sec < (long)to)
            return true; // We are inside an active session
      }
      else
      {
         break; // No more sessions for this day
      }
   }

   // If the broker has defined sessions for today, but the current time falls outside them (Market is closed)
   if(session_exists) return false;

   // Fallback: If the broker does not explicitly define any sessions, assume market is open
   return true;
}

//+------------------------------------------------------------------+
//| WEEKEND GAP PROTECTION LOGIC                                     |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   if(!Close_On_Friday) return true;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Check if it's past the designated time on Friday
   if(dt.day_of_week == 5) // 5 = Friday
   {
      if(dt.hour > Friday_Close_Hour || (dt.hour == Friday_Close_Hour && dt.min >= Friday_Close_Minute))
         return false;
   }
   // Block trading on Saturday and Sunday (Wait for Monday open)
   else if(dt.day_of_week == 6 || dt.day_of_week == 0) // 6 = Saturday, 0 = Sunday
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CLOSE ALL TRADES AND PENDING ORDERS                              |
//+------------------------------------------------------------------+
void CloseAllTradesAndOrders()
{
   static int last_close_day = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // NEW METHOD: "One-Shot" Friday Close. 
   // Only trigger this block exactly once per day. If the broker rejects the deletions 
   // due to massive Friday spread freezing, we DO NOT try again. 
   // Your pending orders will naturally expire over the weekend anyway.
   if(dt.day_of_year == last_close_day) return;
   
   bool action_taken = false;
   
   // Close all active positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
      {
         trade.PositionClose(ticket);
         action_taken = true;
      }
   }
   
   // Delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic)
      {
         trade.OrderDelete(ticket);
         action_taken = true; 
      }
   }
   
   // Mark this day as processed so the EA rests until tomorrow
   if(action_taken) last_close_day = dt.day_of_year;
}