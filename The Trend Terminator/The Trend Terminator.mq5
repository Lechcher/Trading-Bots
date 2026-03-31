//+------------------------------------------------------------------+
//|                                           The Trend Terminator.mq5|
//|                               Copyright 2026, Senior MQL5 Algo-Dev|
//|                                              https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Senior MQL5 Algo-Dev"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\TerminalInfo.mqh>

CTrade         trade;
CAccountInfo   accountInfo;
CSymbolInfo    symInfo;

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_LOT_METHOD {
   LOT_FIXED = 0, // Fixed Lots
   LOT_RISK  = 1  // % Risk per Trade
};

enum ENUM_SL_TP_METHOD {
   METHOD_ATR = 0, // ATR
   METHOD_FIXED = 1 // Fixed Points
};

enum ENUM_TP2_METHOD {
   TP2_CCI = 0, // CCI Signal
   TP2_ATR = 1, // ATR
   TP2_FIXED = 2 // Fixed Points
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
sinput string                 InpStr1           = "=== Money Management ===";
input ENUM_LOT_METHOD         InpLotMethod      = LOT_RISK;    // Lot Sizing Method
input double                  InpRiskPercent    = 1.0;         // Risk %
input double                  InpFixedLots      = 0.1;         // Fixed Lots

sinput string                 InpStr2           = "=== Indicators Settings ===";
input int                     InpEmaPeriod      = 200;         // EMA Period
input int                     InpRsiPeriod      = 14;          // RSI Period
input double                  InpRsiCenterLine  = 50.0;        // RSI Center Line
input int                     InpCciPeriod      = 34;          // CCI Period

sinput string                 InpStr3           = "=== SL, TP & Break-Even ===";
input ENUM_SL_TP_METHOD       InpSlMethod       = METHOD_ATR;  // SL Calculation Method
input ENUM_SL_TP_METHOD       InpTp1Method      = METHOD_ATR;  // TP1 Calculation Method
input ENUM_TP2_METHOD         InpTp2Method      = TP2_CCI;     // TP2 Calculation Method
input int                     InpAtrPeriod      = 21;          // ATR Period
input double                  InpSlAtrMult      = 2.5;         // SL ATR Multiplier
input double                  InpTp1AtrMult     = 2.0;         // TP1 ATR Multiplier
input double                  InpTp2AtrMult     = 4.0;         // TP2 ATR Multiplier (if TP2 = ATR)
input int                     InpFixedSlPts     = 250;         // Fixed SL (Points)
input int                     InpFixedTp1Pts    = 250;         // Fixed TP1 (Points)
input int                     InpFixedTp2Pts    = 500;         // Fixed TP2 (Points)
input int                     InpBeBufferPts    = 20;          // Break-Even Buffer (Points)

sinput string                 InpStr4           = "=== Trading Sessions ===";
input bool                    InpEnableSession  = true;        // Enable Session Filter
input bool                    InpSydneyEnable   = false;       // Sydney Session
input string                  InpSydneyStart    = "00:00";     // Sydney Start
input string                  InpSydneyEnd      = "09:00";     // Sydney End
input bool                    InpTokyoEnable    = false;       // Tokyo Session
input string                  InpTokyoStart     = "02:00";     // Tokyo Start
input string                  InpTokyoEnd       = "11:00";     // Tokyo End
input bool                    InpLondonEnable   = true;       // London Session
input string                  InpLondonStart    = "10:00";     // London Start
input string                  InpLondonEnd      = "18:30";     // London End
input bool                    InpNyEnable       = true;       // New York Session
input string                  InpNyStart        = "15:00";     // New York Start
input string                  InpNyEnd          = "23:00";     // New York End

sinput string                 InpStr5           = "=== News Filter ===";
input bool                    InpEnableNews     = true;        // Enable News Filter
input bool                    InpNewsHigh       = true;        // Filter High Impact News
input bool                    InpNewsMed        = false;       // Filter Medium Impact News
input bool                    InpNewsLow        = false;       // Filter Low Impact News
input int                     InpNewsPauseBef   = 30;          // Minutes Pause Before News
input int                     InpNewsPauseAft   = 30;          // Minutes Pause After News

sinput string                 InpStr6           = "=== Friday Close ===";
input bool                    InpEnableFriClose = true;        // Enable Friday Close
input string                  InpFriCloseTime   = "22:45";     // Friday Close Time

sinput string                 InpStr7           = "=== Developer & Setup ===";
input ulong                   InpMagicNumber    = 123456;      // Magic Number
input string                  InpTradeComment   = "Trend Terminator"; // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int      handle_ema;
int      handle_rsi;
int      handle_cci;
int      handle_atr;

double   ema_buff[];
double   rsi_buff[];
double   cci_buff[];
double   atr_buff[];
double   close_buff[];

bool     isHedging;
double   g_symbol_point;
int      g_symbol_digits;

// Struct to store ticket state for TP1/TP2
struct TradeState {
   ulong ticket;
   bool  is_tp1_closed;
   bool  is_be_moved;
   bool  is_tp2_assigned;
   int   type; // POSITION_TYPE_BUY or POSITION_TYPE_SELL
};
TradeState pos_states[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   symInfo.Name(Symbol());
   g_symbol_point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   g_symbol_digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   isHedging = (margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   handle_ema = iMA(Symbol(), Period(), InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handle_rsi = iRSI(Symbol(), Period(), InpRsiPeriod, PRICE_CLOSE);
   handle_cci = iCCI(Symbol(), Period(), InpCciPeriod, PRICE_TYPICAL);
   handle_atr = iATR(Symbol(), Period(), InpAtrPeriod);

   if(handle_ema == INVALID_HANDLE || handle_rsi == INVALID_HANDLE || 
      handle_cci == INVALID_HANDLE || handle_atr == INVALID_HANDLE) {
      Print("Error creating indicators!");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(ema_buff, true);
   ArraySetAsSeries(rsi_buff, true);
   ArraySetAsSeries(cci_buff, true);
   ArraySetAsSeries(atr_buff, true);
   ArraySetAsSeries(close_buff, true);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_ema);
   IndicatorRelease(handle_rsi);
   IndicatorRelease(handle_cci);
   IndicatorRelease(handle_atr);
  }

//+------------------------------------------------------------------+
//| Time Parse helper                                                |
//+------------------------------------------------------------------+
int TimeToMinutes(string time_str) {
   datetime t = StringToTime(time_str);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
}

//+------------------------------------------------------------------+
//| Friday Close Check                                               |
//+------------------------------------------------------------------+
bool CheckFridayClose() {
   if(!InpEnableFriClose) return false;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_week == 5) { // Friday
       int current_mins = dt.hour * 60 + dt.min;
       int close_mins = TimeToMinutes(InpFriCloseTime);
       
       if(current_mins >= close_mins) {
           return true;
       }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Session Checks                                                   |
//+------------------------------------------------------------------+
bool IsInSession(string start_str, string end_str, int current_mins) {
   int start_m = TimeToMinutes(start_str);
   int end_m = TimeToMinutes(end_str);
   if(start_m < end_m) {
      return (current_mins >= start_m && current_mins <= end_m);
   } else {
      return (current_mins >= start_m || current_mins <= end_m);
   }
}

bool CheckSessionFilter() {
   if(!InpEnableSession) return true; // Allowed
   if(!InpSydneyEnable && !InpTokyoEnable && !InpLondonEnable && !InpNyEnable) return true; // Allow trading if user enabled filter but left all sessions false
   
   MqlDateTime dt;
   TimeCurrent(dt);
   int current_mins = dt.hour * 60 + dt.min;
   
   bool allowed = false;
   if(InpSydneyEnable && IsInSession(InpSydneyStart, InpSydneyEnd, current_mins)) allowed = true;
   if(InpTokyoEnable && IsInSession(InpTokyoStart, InpTokyoEnd, current_mins)) allowed = true;
   if(InpLondonEnable && IsInSession(InpLondonStart, InpLondonEnd, current_mins)) allowed = true;
   if(InpNyEnable && IsInSession(InpNyStart, InpNyEnd, current_mins)) allowed = true;
   
   return allowed;
}

//+------------------------------------------------------------------+
//| News Check Wrapper (MT5 Calendar)                                |
//+------------------------------------------------------------------+
bool CheckNewsFilter() {
   if(!InpEnableNews) return true; // Allowed
   if(MQLInfoInteger(MQL_TESTER)) return true; // Bypass in strategy tester
   
   // Basic MT5 Calendar check - looping through incoming events in standard timeframe
   MqlCalendarEvent events[];
   MqlCalendarValue values[];
   
   datetime current = TimeCurrent();
   datetime start_t = current - InpNewsPauseBef * 60;
   datetime end_t   = current + InpNewsPauseAft * 60;
   
   // A simple generic fallback checks if any events for EUR/USD currencies exist during this timeframe.
   string arr_currencies[] = {"EUR", "USD"}; 
   for(int c = 0; c < 2; c++) {
       MqlCalendarValue q_values[];
       if(CalendarValueHistory(q_values, start_t, end_t, NULL, arr_currencies[c])) {
           for(int v = 0; v < ArraySize(q_values); v++) {
               MqlCalendarEvent ev;
               if(CalendarEventById(q_values[v].event_id, ev)) {
                   if((InpNewsHigh && ev.importance == CALENDAR_IMPORTANCE_HIGH) ||
                      (InpNewsMed && ev.importance == CALENDAR_IMPORTANCE_MODERATE) ||
                      (InpNewsLow && ev.importance == CALENDAR_IMPORTANCE_LOW)) {
                       return false; // Not allowed to trade
                   }
               }
           }
       }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Trade Size                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance) {
   double lot = InpFixedLots;
   
   if(InpLotMethod == LOT_RISK) {
       double balance = AccountInfoDouble(ACCOUNT_BALANCE);
       double risk_amount = balance * (InpRiskPercent / 100.0);
       double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
       double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
       
       if(sl_distance > 0 && tick_size > 0 && tick_value > 0) {
           double sl_ticks = sl_distance / tick_size;
           lot = risk_amount / (sl_ticks * tick_value);
       }
   }
   
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   lot = MathMax(min_lot, MathMin(max_lot, lot));
   lot = min_lot + MathFloor((lot - min_lot) / step_lot) * step_lot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Close All Friday                                                 |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   if(CheckFridayClose()) {
       for(int i = PositionsTotal() - 1; i >= 0; i--) {
           ulong ticket = PositionGetTicket(i);
           if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
               trade.PositionClose(ticket);
           }
       }
   }
}

//+------------------------------------------------------------------+
//| Update Position States                                           |
//+------------------------------------------------------------------+
void ManageBreakEvenAndTP1() {
   double atr_val = 0;
   if(atr_buff[1]) atr_val = atr_buff[1];

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
       ulong ticket = PositionGetTicket(i);
       if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
           
           double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
           double sl = PositionGetDouble(POSITION_SL);
           double tp = PositionGetDouble(POSITION_TP);
           double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
           double vol = PositionGetDouble(POSITION_VOLUME);
           int type = (int)PositionGetInteger(POSITION_TYPE);
           
           // Fetch TP1 distance setting to track BE activation
           double tp1_dist = (InpTp1Method == METHOD_ATR) ? (atr_val * InpTp1AtrMult) : (InpFixedTp1Pts * g_symbol_point);
           
           // Break-Even / Action logic 
           bool reach_tp1 = false;
           if(type == POSITION_TYPE_BUY) {
               reach_tp1 = (current_price >= (open_price + tp1_dist));
           } else {
               reach_tp1 = (current_price <= (open_price - tp1_dist));
           }

           if(reach_tp1) {
               // 1. Move to Break-Even + Buffer
               double be_level = (type == POSITION_TYPE_BUY) ? (open_price + InpBeBufferPts * g_symbol_point) : (open_price - InpBeBufferPts * g_symbol_point);
               be_level = NormalizeDouble(be_level, g_symbol_digits);
               
               bool need_modify_sl = false;
               if(type == POSITION_TYPE_BUY && (sl < be_level || sl == 0)) need_modify_sl = true;
               if(type == POSITION_TYPE_SELL && (sl > be_level || sl == 0)) need_modify_sl = true;
               
               if(need_modify_sl) {
                   trade.PositionModify(ticket, be_level, tp);
               }

               // 2. Partial Close (Netting mode) or TP1 check
               if(!isHedging && vol > SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN)) {
                   // Calculate half volume conforming to steps
                   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
                   double close_vol = vol / 2.0;
                   close_vol = MathFloor(close_vol / step) * step;
                   
                   // Find tracking state to ensure we close TP1 only once
                   bool already_closed_half = false;
                   for(int s=0; s<ArraySize(pos_states); s++) {
                       if(pos_states[s].ticket == ticket && pos_states[s].is_tp1_closed) {
                           already_closed_half = true;
                           break;
                       }
                   }
                   
                   if(!already_closed_half && close_vol >= SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN)) {
                       if(trade.PositionClosePartial(ticket, close_vol)) {
                           // Ensure state tracked
                           bool found=false;
                           for(int s=0; s<ArraySize(pos_states); s++) {
                               if(pos_states[s].ticket == ticket) {
                                   pos_states[s].is_tp1_closed = true; found=true; break;
                               }
                           }
                           if(!found) {
                               int ns = ArraySize(pos_states);
                               ArrayResize(pos_states, ns+1);
                               pos_states[ns].ticket = ticket;
                               pos_states[ns].is_tp1_closed = true;
                               pos_states[ns].is_be_moved = true;
                           }
                       }
                   }
               }
           }
           
           // Track TP2 Exit CCI conditions
           if(InpTp2Method == TP2_CCI) {
               // We need CCI data
               if(type == POSITION_TYPE_BUY) {
                   if(cci_buff[2] > 100 && cci_buff[1] < 100) { // Hook back from above +100
                       // Ensure this represents the 'runner' or 'tp2' part
                       // Hedging case: It's just a position with a certain label / ticket. Close it.
                       // Netting case: We close the whole remaining position.
                       trade.PositionClose(ticket);
                   }
               } else if(type == POSITION_TYPE_SELL) {
                   if(cci_buff[2] < -100 && cci_buff[1] > -100) { // Hook back from below -100
                       trade.PositionClose(ticket);
                   }
               }
           }
       }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Friday close enforcement
   CloseAllPositions();
   if(CheckFridayClose()) return;

   // Update Indicators FIRST so Break-Even can fetch correct ATR values instantly
   if(CopyBuffer(handle_ema, 0, 0, 3, ema_buff) <= 0) return;
   if(CopyBuffer(handle_rsi, 0, 0, 3, rsi_buff) <= 0) return;
   if(CopyBuffer(handle_cci, 0, 0, 3, cci_buff) <= 0) return;
   if(CopyBuffer(handle_atr, 0, 0, 3, atr_buff) <= 0) return;
   if(CopyClose(Symbol(), Period(), 0, 3, close_buff) <= 0) return;

   // Ensure the freshest tick
   MqlTick tick;
   if(!SymbolInfoTick(Symbol(), tick)) return;

   // Clean up dead pos_states
   int total_state = ArraySize(pos_states);
   for(int i = total_state - 1; i >= 0; i--) {
       if(!PositionSelectByTicket(pos_states[i].ticket)) {
           // Remove from array (shift left)
           for(int j=i; j<total_state-1; j++) pos_states[j] = pos_states[j+1];
           ArrayResize(pos_states, total_state-1);
           total_state--;
       }
   }

   // Manage existin positions strictly
   ManageBreakEvenAndTP1();

   // Find Open Positions for current symbol and magic
   int open_buys = 0;
   int open_sells = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
       ulong t = PositionGetTicket(i);
       if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
           if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) open_buys++;
           else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) open_sells++;
       }
   }
   
   int max_trades = isHedging ? 2 : 1;
   if((open_buys + open_sells) >= max_trades) return; // Wait until all clear

   // Check filters (Sessions / News)
   if(!CheckSessionFilter()) return;
   if(!CheckNewsFilter()) return;

   // New Bar Check using Time[0]
   static datetime last_time = 0;
   datetime current_time = iTime(Symbol(), Period(), 0);
   if(current_time == last_time) return;
   last_time = current_time; // Execute strictly once per bar

   // Check Entry Logic on Shift 1
   bool buy_condition = (close_buff[1] > ema_buff[1]) && 
                        (rsi_buff[1] > InpRsiCenterLine) &&
                        (cci_buff[2] < -100 && cci_buff[1] >= -100);
                        
   bool sell_condition = (close_buff[1] < ema_buff[1]) && 
                         (rsi_buff[1] < InpRsiCenterLine) &&
                         (cci_buff[2] > 100 && cci_buff[1] <= 100);

   if(!buy_condition && !sell_condition) return;
   
   double sl_dist = (InpSlMethod == METHOD_ATR) ? (atr_buff[1] * InpSlAtrMult) : (InpFixedSlPts * g_symbol_point);
   double tp1_dist = (InpTp1Method == METHOD_ATR) ? (atr_buff[1] * InpTp1AtrMult) : (InpFixedTp1Pts * g_symbol_point);
   double tp2_dist = (InpTp2Method == TP2_ATR) ? (atr_buff[1] * InpTp2AtrMult) : (InpTp2Method == TP2_FIXED ? InpFixedTp2Pts * g_symbol_point : 0);

   double lot = CalculateLotSize(sl_dist);
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double step_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   trade.SetExpertMagicNumber(InpMagicNumber);

   if(buy_condition) {
       double ask = tick.ask;
       double sl = NormalizeDouble(ask - sl_dist, g_symbol_digits);
       
       if(isHedging) {
           double split_lot = NormalizeDouble(lot / 2.0, 2);
           split_lot = MathFloor(split_lot / step_lot) * step_lot;
           if(split_lot < min_lot) {
               // Cannot split, execute as 1 order TP2 only
               double tp2 = tp2_dist > 0 ? NormalizeDouble(ask + tp2_dist, g_symbol_digits) : 0;
               trade.Buy(lot, Symbol(), ask, sl, tp2, InpTradeComment);
           } else {
               // TP1 Order
               double tp1 = NormalizeDouble(ask + tp1_dist, g_symbol_digits);
               trade.Buy(split_lot, Symbol(), ask, sl, tp1, InpTradeComment + "_TP1");
               // TP2 Order
               double tp2 = tp2_dist > 0 ? NormalizeDouble(ask + tp2_dist, g_symbol_digits) : 0;
               trade.Buy(split_lot, Symbol(), ask, sl, tp2, InpTradeComment + "_TP2");
           }
       } else { // Netting
           double tp = tp2_dist > 0 ? NormalizeDouble(ask + tp2_dist, g_symbol_digits) : 0;
           // In netting, we only place TP2 physically if ATR/Fixed used, OR 0 if CCI. TP1 is handled by code.
           trade.Buy(lot, Symbol(), ask, sl, tp, InpTradeComment);
       }
   }
   else if(sell_condition) {
       double bid = tick.bid;
       double sl = NormalizeDouble(bid + sl_dist, g_symbol_digits);
       
       if(isHedging) {
           double split_lot = NormalizeDouble(lot / 2.0, 2);
           split_lot = MathFloor(split_lot / step_lot) * step_lot;
           if(split_lot < min_lot) {
               // Cannot split, execute as 1 order TP2 only
               double tp2 = tp2_dist > 0 ? NormalizeDouble(bid - tp2_dist, g_symbol_digits) : 0;
               trade.Sell(lot, Symbol(), bid, sl, tp2, InpTradeComment);
           } else {
               // TP1 Order
               double tp1 = NormalizeDouble(bid - tp1_dist, g_symbol_digits);
               trade.Sell(split_lot, Symbol(), bid, sl, tp1, InpTradeComment + "_TP1");
               // TP2 Order
               double tp2 = tp2_dist > 0 ? NormalizeDouble(bid - tp2_dist, g_symbol_digits) : 0;
               trade.Sell(split_lot, Symbol(), bid, sl, tp2, InpTradeComment + "_TP2");
           }
       } else { // Netting
           double tp = tp2_dist > 0 ? NormalizeDouble(bid - tp2_dist, g_symbol_digits) : 0;
           trade.Sell(lot, Symbol(), bid, sl, tp, InpTradeComment);
       }
   }
  }
//+------------------------------------------------------------------+
