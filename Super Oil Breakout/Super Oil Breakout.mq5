//+------------------------------------------------------------------+
//|                                              OilBreakoutEA.mq5   |
//|                                              Just Write!         |
//+------------------------------------------------------------------+
#property copyright "Just Write!"
#property link      "https://github.com/Lechcher"
#property version   "1.00"
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
input ENUM_LOT_MODE           Lot_Size_Mode      = Risk_Percent;     // Lot Size Mode
input double                  Lots               = 0.1;              // Fixed Lots
input double                  RiskPercent        = 0.1;              // Risk % of Free Margin
input int                     Max_Spread_Points  = 50;               // Maximum Allowed Spread (Points)
input ulong                   Magic              = 222;              // Magic Number

sinput string                 Section2 = "--- Strategy & Breakout Settings ---";
input ENUM_TIMEFRAMES         Timeframe          = PERIOD_M15;       // Calculation Timeframe
input int                     BarsN              = 20;               // Lookback Bars for High/Low
input int                     OrderDistPoints    = 150;              // Buffer Distance from High/Low (Points)
input int                     ExpirationHours    = 2;                // Pending Order Expiration (Hours)

sinput string                 Section3 = "--- Dual Higher Timeframe Trend Filter ---";
input bool                    Use_Trend_Filter   = true;             // Use Trend Filter
input ENUM_TIMEFRAMES         Trend_Timeframe    = PERIOD_H1;        // Trend Timeframe
input int                     Fast_EMA_Period    = 21;               // Fast EMA Period
input int                     Slow_EMA_Period    = 50;               // Slow EMA Period
input ENUM_MA_METHOD          Trend_MA_Method    = MODE_EMA;         // Trend MA Method

sinput string                 Section4 = "--- TP & SL Calculation Mode ---";
input ENUM_TPSL_MODE          TPSL_Mode          = ATR_Dynamic;      // TP/SL Mode
input int                     TpPoints           = 800;              // Fixed TP (Points)
input int                     SlPoints           = 400;              // Fixed SL (Points)
input int                     ATR_Period         = 14;               // ATR Period
input double                  ATR_TP_Multiplier  = 4.0;              // ATR Multiplier for TP
input double                  ATR_SL_Multiplier  = 2.0;              // ATR Multiplier for SL

sinput string                 Section5 = "--- Trailing Stop Settings ---";
input int                     TslTriggerPoints   = 300;              // TSL Activation Profit (Points)
input int                     TslPoints          = 150;              // TSL Trailing Distance (Points)

sinput string                 Section6 = "--- Weekend Gap Protection ---";
input bool                    Close_On_Friday    = true;             // Close All Trades on Friday
input int                     Friday_Close_Hour  = 22;               // Friday Close Hour (Server Time)
input int                     Friday_Close_Minute= 45;               // Friday Close Minute (Server Time)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES & OBJECTS                                       |
//+------------------------------------------------------------------+
CTrade         trade;
CSymbolInfo    symInfo;

int            atr_handle;           // Handle for the ATR indicator
int            fast_ema_handle = INVALID_HANDLE;  // Handle for the Fast Trend EMA indicator
int            slow_ema_handle = INVALID_HANDLE;  // Handle for the Slow Trend EMA indicator
int            p_adj = 1;            // Point multiplier for 3-digit vs 2-digit brokers

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION FUNCTION                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Symbol Info
   if(!symInfo.Name(_Symbol)) return INIT_FAILED;
   
   // Asset Normalization for Oil (Handling 2-digit vs 3-digit oil pricing mostly, and 5-digit forex)
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
   
   // Setup Dual EMA Trend Filter Indicators
   if(Use_Trend_Filter)
   {
      fast_ema_handle = iMA(_Symbol, Trend_Timeframe, Fast_EMA_Period, 0, Trend_MA_Method, PRICE_CLOSE);
      slow_ema_handle = iMA(_Symbol, Trend_Timeframe, Slow_EMA_Period, 0, Trend_MA_Method, PRICE_CLOSE);
      
      if(fast_ema_handle == INVALID_HANDLE || slow_ema_handle == INVALID_HANDLE)
      {
         Print("Error initializing Dual Trend EMA indicators");
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
      
   if(fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(fast_ema_handle);
      
   if(slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(slow_ema_handle);
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   symInfo.RefreshRates();
   
   // 1. Spread Check
   double current_spread = (symInfo.Ask() - symInfo.Bid()) / _Point;
   if(current_spread > Max_Spread_Points * p_adj)
      return; // Do not trade or manage if spread is too wide
      
   // --- Weekend Gap Protection ---
   if(!IsTradingAllowed())
   {
      CloseAllTradesAndOrders();
      return; // Block EA from placing any new orders or managing trades
   }
      
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
   
   // OCO Logic: If we have an active position, delete any remaining pending orders immediately
   if(pos_count > 0)
   {
      if(has_buy_stop) trade.OrderDelete(buy_stop_ticket);
      if(has_sell_stop) trade.OrderDelete(sell_stop_ticket);
      return; // Do not place new breakouts while in a trade
   }
   
   // 4. Dual EMA Trend Filter Logic
   bool allow_buy = true;
   bool allow_sell = true;
   
   if(Use_Trend_Filter)
   {
      double fast_ema_buffer[], slow_ema_buffer[];
      ArraySetAsSeries(fast_ema_buffer, true);
      ArraySetAsSeries(slow_ema_buffer, true);
      
      if(CopyBuffer(fast_ema_handle, 0, 0, 1, fast_ema_buffer) > 0 && 
         CopyBuffer(slow_ema_handle, 0, 0, 1, slow_ema_buffer) > 0)
      {
         double current_price = symInfo.Bid();
         double fast_ema = fast_ema_buffer[0];
         double slow_ema = slow_ema_buffer[0];
         
         // Strong Uptrend Consensus: Fast > Slow AND Price > Fast AND Price > Slow
         if(!(fast_ema > slow_ema && current_price > fast_ema && current_price > slow_ema)) 
            allow_buy = false;  
            
         // Strong Downtrend Consensus: Fast < Slow AND Price < Fast AND Price < Slow
         if(!(fast_ema < slow_ema && current_price < fast_ema && current_price < slow_ema)) 
            allow_sell = false; 
      }
      else
      {
         // If buffers fail to copy, restrict trading as a safety measure
         allow_buy = false;
         allow_sell = false;
      }
   }
   
   // Delete pending orders that violate the dual trend filter
   if(!allow_buy && has_buy_stop) { trade.OrderDelete(buy_stop_ticket); has_buy_stop = false; }
   if(!allow_sell && has_sell_stop) { trade.OrderDelete(sell_stop_ticket); has_sell_stop = false; }
   
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
   
   // Ensure orders are not placed too close to current price (Stops Level)
   double stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(buy_price < symInfo.Ask() + stops_level) buy_price = symInfo.Ask() + stops_level;
   if(sell_price > symInfo.Bid() - stops_level) sell_price = symInfo.Bid() - stops_level;
   
   // Calculate TP and SL actual price distances
   double tp_dist_price = 0, sl_dist_price = 0;
   GetSLTPDistances(tp_dist_price, sl_dist_price);
   
   // Calculate Lot Size dynamically based on SL distance
   double lot_size = GetLotSize(sl_dist_price);
   
   // Expiration Time
   datetime expiration = TimeCurrent() + (datetime)(ExpirationHours * 3600);
   
   // Manage Buy Stop Order
   if(allow_buy)
   {
      if(!has_buy_stop)
      {
         trade.BuyStop(lot_size, buy_price, _Symbol, buy_price - sl_dist_price, buy_price + tp_dist_price, ORDER_TIME_SPECIFIED, expiration);
      }
      else
      {
         double current_buy_price = OrderGetDouble(ORDER_PRICE_OPEN);
         if(MathAbs(current_buy_price - buy_price) > _Point) // Only modify if price changed
            trade.OrderModify(buy_stop_ticket, buy_price, buy_price - sl_dist_price, buy_price + tp_dist_price, ORDER_TIME_SPECIFIED, expiration);
      }
   }
   
   // Manage Sell Stop Order
   if(allow_sell)
   {
      if(!has_sell_stop)
      {
         trade.SellStop(lot_size, sell_price, _Symbol, sell_price + sl_dist_price, sell_price - tp_dist_price, ORDER_TIME_SPECIFIED, expiration);
      }
      else
      {
         double current_sell_price = OrderGetDouble(ORDER_PRICE_OPEN);
         if(MathAbs(current_sell_price - sell_price) > _Point) // Only modify if price changed
            trade.OrderModify(sell_stop_ticket, sell_price, sell_price + sl_dist_price, sell_price - tp_dist_price, ORDER_TIME_SPECIFIED, expiration);
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
      
      // Copy Shift 1 (last closed bar) for stable ATR scaling
      if(CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) > 0) 
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

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
      {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         long type = PositionGetInteger(POSITION_TYPE);

         if(type == POSITION_TYPE_BUY)
         {
            if(symInfo.Bid() - open_price >= tsl_trigger_price)
            {
               double new_sl = symInfo.Bid() - tsl_dist_price;
               if(new_sl > sl && new_sl < symInfo.Bid())
               {
                  trade.PositionModify(ticket, new_sl, tp);
               }
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            if(open_price - symInfo.Ask() >= tsl_trigger_price)
            {
               double new_sl = symInfo.Ask() + tsl_dist_price;
               if((sl == 0.0 || new_sl < sl) && new_sl > symInfo.Ask())
               {
                  trade.PositionModify(ticket, new_sl, tp);
               }
            }
         }
      }
   }
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
   // Close all active positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
      {
         trade.PositionClose(ticket);
      }
   }
   
   // Delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic)
      {
         trade.OrderDelete(ticket);
      }
   }
}
//+------------------------------------------------------------------+