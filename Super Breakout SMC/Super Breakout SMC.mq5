//+------------------------------------------------------------------+
//|                                           Super Breakout SMC.mq5 |
//|                                     Developed by Just Write!  |
//+------------------------------------------------------------------+
#property copyright "Just Write!"
#property link      "https://github.com/Lechcher"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Enums
enum ENUM_RISK_MODE {
   FIXED_LOTS,      // Fixed Lot Size
   PERCENT_BALANCE  // Percent of Balance
};

enum ENUM_SL_MODE {
   SL_FIXED_PIPS,
   SL_ATR,
   SL_FIBO,
   SL_STRUCTURE
};

enum ENUM_TP_MODE {
   TP_FIXED_PIPS,
   TP_ATR,
   TP_FIBO_EXTENSION,
   TP_RISK_REWARD
};

//--- Input parameters
input string               InpGeneralOptions = "--- Core Settings ---";
input ENUM_TIMEFRAMES      InpTimeframeMain = PERIOD_M15;                // Main Structure (M15)
input ENUM_TIMEFRAMES      InpTimeframeTrig = PERIOD_M5;                 // Trigger Timeframe (M5)

input string               InpSessionOptions = "--- Trade Sessions (Killzones) ---";
input bool                 InpSydney = false;                            // Sydney Session
input int                  InpSydneyStartHour = 22;                      // Sydney Start Hour (UTC)
input int                  InpSydneyStartMinute = 0;                     // Sydney Start Minute
input int                  InpSydneyEndHour = 7;                         // Sydney End Hour (UTC)
input int                  InpSydneyEndMinute = 0;                       // Sydney End Minute
input bool                 InpTokyo = false;                             // Tokyo Session
input int                  InpTokyoStartHour = 0;                        // Tokyo Start Hour (UTC)
input int                  InpTokyoStartMinute = 0;                      // Tokyo Start Minute
input int                  InpTokyoEndHour = 9;                          // Tokyo End Hour (UTC)
input int                  InpTokyoEndMinute = 0;                        // Tokyo End Minute
input bool                 InpLondon = true;                             // London Session
input int                  InpLondonStartHour = 8;                       // London Start Hour (UTC)
input int                  InpLondonStartMinute = 0;                     // London Start Minute
input int                  InpLondonEndHour = 16;                        // London End Hour (UTC)
input int                  InpLondonEndMinute = 0;                       // London End Minute
input bool                 InpNewYork = true;                            // New York Session
input int                  InpNewYorkStartHour = 13;                     // New York Start Hour (UTC)
input int                  InpNewYorkStartMinute = 0;                    // New York Start Minute
input int                  InpNewYorkEndHour = 21;                       // New York End Hour (UTC)
input int                  InpNewYorkEndMinute = 0;                      // New York End Minute

input string               InpRiskOptions = "--- Risk Management ---";
input ENUM_RISK_MODE       InpRiskMode = PERCENT_BALANCE;                // Risk Mode
input double               InpRiskPercent = 1.0;                         // Risk Percent (%)
input double               InpFixedLotSize = 0.05;                       // Fixed Lot Size

input string               InpExitOptions = "--- Exits & Targets ---";
input ENUM_SL_MODE         InpSLMode = SL_ATR;                           // Stop Loss Mode
input double               InpATRMultiplier = 1.6;                       // ATR Multiplier (SL)
input ENUM_TP_MODE         InpTPMode = TP_RISK_REWARD;                   // Take Profit Mode
input double               InpRRRatio = 2.0;                             // Risk/Reward Ratio (TP)
input bool                 InpBreakEven = true;                          // Break-Even Active
input double               InpBreakEvenRR = 1.0;                         // Break-Even Trigger (1R)

input string               InpFilterOptions = "--- Filters & Rules ---";
input bool                 InpWeekendGapProtection = true;               // Weekend Gap Protection
input int                  InpFridayCloseHour = 21;                      // Friday Close Hour
input int                  InpFridayCloseMinute = 45;                    // Friday Close Minute
input int                  InpMondayOpenHour = 2;                        // Monday Resume Hour
input int                  InpMondayOpenMinute = 0;                      // Monday Resume Minute

input string               InpAdvancedOptions = "--- Advanced / Strategy Tuning ---";
input int                  InpATRPeriod = 14;                            // ATR Period
input int                  InpRSIPeriod = 9;                             // RSI Period
input double               InpRSIBullishHealthyMin = 60.0;               // RSI Buy Healthy Min
input double               InpRSIBullishHealthyMax = 85.0;               // RSI Buy Healthy Max
input double               InpRSILongInvalidation = 20.0;                // RSI Buy Setup Invalidation
input double               InpRSIBearishHealthyMin = 15.0;               // RSI Sell Healthy Min
input double               InpRSIBearishHealthyMax = 40.0;               // RSI Sell Healthy Max
input double               InpRSIShortInvalidation = 80.0;               // RSI Sell Setup Invalidation
input int                  InpSwingLookback = 10;                        // Bars Lookback for Breakout Fibo
input double               InpFiboEntryLevel = 0.5;                      // Fibo Entry Retracement Level
input int                  InpMagicNumber = 12345;                       // EA Magic Number

//--- Global Variables
CTrade         ExtTrade;
CSymbolInfo    ExtSymbol;
CPositionInfo  ExtPosition;

int            ExtATRHandle = INVALID_HANDLE;
int            ExtRSIHandle = INVALID_HANDLE;

double         ExtATRBuffer[];
double         ExtRSIBuffer[];

double         ExtSessionHigh = 0;
double         ExtSessionLow = 0;

// Breakout State Machine
enum ENUM_BREAKOUT_STATE {
   STATE_WAITING,
   STATE_VALID_BREAKOUT_BULLISH,
   STATE_VALID_BREAKOUT_BEARISH,
};
ENUM_BREAKOUT_STATE ExtBreakoutState = STATE_WAITING;

double         ExtImpulseHigh = 0;
double         ExtImpulseLow = 0;
double         ExtFibo50Level = 0;
bool           ExtLimitOrderPlaced = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Init Symbol
   if(!ExtSymbol.Name(_Symbol)) {
      Print("Error initializing symbol: ", GetLastError());
      return INIT_FAILED;
   }
   ExtSymbol.RefreshRates();
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   
   // Init Indicators
   ExtATRHandle = iATR(_Symbol, InpTimeframeMain, InpATRPeriod);
   if(ExtATRHandle == INVALID_HANDLE) {
      Print("Failed to create ATR handle, Error: ", GetLastError());
      return INIT_FAILED;
   }
   
   ExtRSIHandle = iRSI(_Symbol, InpTimeframeTrig, InpRSIPeriod, PRICE_CLOSE);
   if(ExtRSIHandle == INVALID_HANDLE) {
      Print("Failed to create RSI handle, Error: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(ExtATRBuffer, true);
   ArraySetAsSeries(ExtRSIBuffer, true);

   EventSetTimer(1); // Timer for chart UI updates
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(ExtATRHandle != INVALID_HANDLE) IndicatorRelease(ExtATRHandle);
   if(ExtRSIHandle != INVALID_HANDLE) IndicatorRelease(ExtRSIHandle);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Pre-Trade Validation Block to sync with Broker Server
   if(!IsTradingAllowed()) return;
   
   // Check bar states
   static datetime lastM15Bar = 0;
   datetime currentM15Bar = iTime(_Symbol, InpTimeframeMain, 0);
   bool newM15Bar = false;
   if(lastM15Bar != currentM15Bar) {
      newM15Bar = true;
      lastM15Bar = currentM15Bar;
   }
   
   // Safety & Position Checks (Tick-level)
   ManageOpenPositions();
   HandleWeekendGap();
   CheckSetupInvalidation();

   // Core Logic Mapping (Bar-level to avoid tick noise)
   if(newM15Bar && !HasOpenPositions() && !ExtLimitOrderPlaced) {
      ProcessBreakoutLogic();
   }
   
   // Entry Trigger Logic (Tick-level if breakout active)
   if(ExtBreakoutState != STATE_WAITING && !HasOpenPositions()) {
      CheckM5Trigger();
   }
  }

//+------------------------------------------------------------------+
//| Timer function for UI Display                                    |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateChartComment();
  }

//+------------------------------------------------------------------+
//| Process Breakout Logic (M15)                                     |
//+------------------------------------------------------------------+
void ProcessBreakoutLogic()
  {
   UpdateSessionHighLow();
   
   if(ExtSessionHigh == 0 || ExtSessionLow == 0) return;
   
   double c1 = iClose(_Symbol, InpTimeframeMain, 1);
   double o1 = iOpen(_Symbol, InpTimeframeMain, 1);
   double h1 = iHigh(_Symbol, InpTimeframeMain, 1);
   double l1 = iLow(_Symbol, InpTimeframeMain, 1);
   
   // Fakeout (Liquidity Sweep) Protection
   // Bullish fakeout: Pierces session high but closes back inside range strongly
   if(h1 > ExtSessionHigh && c1 < ExtSessionHigh && c1 < o1) {
      ExtBreakoutState = STATE_WAITING;
      return;
   }
   // Bearish fakeout: Pierces session low but closes back inside range strongly
   if(l1 < ExtSessionLow && c1 > ExtSessionLow && c1 > o1) {
      ExtBreakoutState = STATE_WAITING;
      return;
   }
   
   // Valid Breakout Identification
   // Strong bullish close entirely outside
   if(c1 > ExtSessionHigh && o1 < c1) {
      ExtBreakoutState = STATE_VALID_BREAKOUT_BULLISH;
      CalculateFiboLevels(true);
   }
   // Strong bearish close entirely outside
   else if(c1 < ExtSessionLow && o1 > c1) {
      ExtBreakoutState = STATE_VALID_BREAKOUT_BEARISH;
      CalculateFiboLevels(false);
   }
  }

//+------------------------------------------------------------------+
//| Connection & Market Synchronization Checks                       |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   // 1. Check if terminal is connected to the broker server
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   
   // 2. Check if AutoTrading is allowed globally in the terminal
   //    and specifically for this Expert Advisor.
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   
   // 3. Market Watch verify: Check if market is open/accepting deals
   if(!SymbolInfoInteger(_Symbol, SYMBOL_SESSION_DEALS)) return false;
   
   // 4. Verify specific symbol's trade mode permits opening positions
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY) return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Dynamically Calculate Broker GMT Offset                          |
//+------------------------------------------------------------------+
int CalculateGMTOffset()
  {
   // Compare Broker Server time against GMT time
   datetime timeServer = TimeCurrent();
   datetime timeGMT = TimeGMT();
   int diffSeconds = (int)(timeServer - timeGMT);
   return diffSeconds / 3600; // Returns GMT Offset in whole hours
  }

//+------------------------------------------------------------------+
//| Helper to determine if current time is within a session window   |
//+------------------------------------------------------------------+
bool IsTimeInSession(int currentHour, int currentMin, int startHour, int startMin, int endHour, int endMin)
  {
   int currentTotal = currentHour * 60 + currentMin;
   int startTotal = startHour * 60 + startMin;
   int endTotal = endHour * 60 + endMin;
   
   if(startTotal < endTotal) {
      return (currentTotal >= startTotal && currentTotal < endTotal);
   } else if(startTotal > endTotal) {
      // Handles wraparound sessions (e.g. Sydney 22:00 to 07:00)
      return (currentTotal >= startTotal || currentTotal < endTotal);
   }
   return false;
  }

//+------------------------------------------------------------------+
//| Determine and Map Current Session Boundaries                     |
//+------------------------------------------------------------------+
void UpdateSessionHighLow()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   bool inSydney = InpSydney && IsTimeInSession(dt.hour, dt.min, InpSydneyStartHour, InpSydneyStartMinute, InpSydneyEndHour, InpSydneyEndMinute);
   bool inTokyo = InpTokyo && IsTimeInSession(dt.hour, dt.min, InpTokyoStartHour, InpTokyoStartMinute, InpTokyoEndHour, InpTokyoEndMinute);
   bool inLondon = InpLondon && IsTimeInSession(dt.hour, dt.min, InpLondonStartHour, InpLondonStartMinute, InpLondonEndHour, InpLondonEndMinute);
   bool inNewYork = InpNewYork && IsTimeInSession(dt.hour, dt.min, InpNewYorkStartHour, InpNewYorkStartMinute, InpNewYorkEndHour, InpNewYorkEndMinute);
   
   // Track the session high/low for the actively mapped period
   if(inSydney || inTokyo || inLondon || inNewYork) {
      int startIdx = 10; // Simplified window lookback to find session start
      int endIdx = 2; // Look at all candles before the breakout candle
      
      int hhIdx = iHighest(_Symbol, InpTimeframeMain, MODE_HIGH, startIdx, endIdx);
      int llIdx = iLowest(_Symbol, InpTimeframeMain, MODE_LOW, startIdx, endIdx);
      
      if(hhIdx >= 0 && llIdx >= 0) {
         ExtSessionHigh = iHigh(_Symbol, InpTimeframeMain, hhIdx);
         ExtSessionLow  = iLow(_Symbol, InpTimeframeMain, llIdx);
      }
   }
  }

//+------------------------------------------------------------------+
//| Calculate the Impulse Leg & Fibonacci 50% Zone                   |
//+------------------------------------------------------------------+
void CalculateFiboLevels(bool isBullish)
  {
   int breakoutIdx = 1;
   
   if(isBullish) {
      ExtImpulseHigh = iHigh(_Symbol, InpTimeframeMain, breakoutIdx);
      int startSwingIdx = iLowest(_Symbol, InpTimeframeMain, MODE_LOW, InpSwingLookback, breakoutIdx);
      ExtImpulseLow = iLow(_Symbol, InpTimeframeMain, startSwingIdx);
   }
   else {
      ExtImpulseLow = iLow(_Symbol, InpTimeframeMain, breakoutIdx);
      int startSwingIdx = iHighest(_Symbol, InpTimeframeMain, MODE_HIGH, InpSwingLookback, breakoutIdx);
      ExtImpulseHigh = iHigh(_Symbol, InpTimeframeMain, startSwingIdx);
   }
   
   ExtFibo50Level = ExtImpulseLow + (ExtImpulseHigh - ExtImpulseLow) * InpFiboEntryLevel;
  }

//+------------------------------------------------------------------+
//| Monitor Trigger Conditions (M5 RSI filtering)                    |
//+------------------------------------------------------------------+
void CheckM5Trigger()
  {
   if(CopyBuffer(ExtRSIHandle, 0, 0, 1, ExtRSIBuffer) <= 0) return;
   
   double rsiM5 = ExtRSIBuffer[0];
   ExtSymbol.RefreshRates();
   double ask = ExtSymbol.Ask();
   double bid = ExtSymbol.Bid();
   
   // Margin Checks & Executions
   if(ExtBreakoutState == STATE_VALID_BREAKOUT_BULLISH) {
      if(ask <= ExtFibo50Level + ExtSymbol.Spread() * ExtSymbol.Point()) { // Reached 50% Fibo Entry Zone
         if(rsiM5 >= InpRSIBullishHealthyMin && rsiM5 <= InpRSIBullishHealthyMax) {
            ExecuteOrder(ORDER_TYPE_BUY, ask);
            ExtBreakoutState = STATE_WAITING;
         }
         else if(rsiM5 > InpRSIBullishHealthyMax && !ExtLimitOrderPlaced) {
            PlaceLimitOrder(ORDER_TYPE_BUY_LIMIT, ExtFibo50Level);
            ExtLimitOrderPlaced = true;
         }
      }
   }
   else if(ExtBreakoutState == STATE_VALID_BREAKOUT_BEARISH) {
      if(bid >= ExtFibo50Level - ExtSymbol.Spread() * ExtSymbol.Point()) { // Reached 50% Fibo Entry Zone
         if(rsiM5 >= InpRSIBearishHealthyMin && rsiM5 <= InpRSIBearishHealthyMax) {
            ExecuteOrder(ORDER_TYPE_SELL, bid);
            ExtBreakoutState = STATE_WAITING;
         }
         else if(rsiM5 < InpRSIBearishHealthyMin && !ExtLimitOrderPlaced) {
            PlaceLimitOrder(ORDER_TYPE_SELL_LIMIT, ExtFibo50Level);
            ExtLimitOrderPlaced = true;
         }
      }
   }
  }

//+------------------------------------------------------------------+
//| Setup Invalidation (Early Exit & Limit Drop)                     |
//+------------------------------------------------------------------+
void CheckSetupInvalidation()
  {
   if(ExtBreakoutState == STATE_WAITING && !ExtLimitOrderPlaced && !HasOpenPositions()) return;
   
   if(CopyBuffer(ExtRSIHandle, 0, 0, 1, ExtRSIBuffer) <= 0) return;
   double rsiM5 = ExtRSIBuffer[0];
   
   bool isInvalid = false;
   if(ExtBreakoutState == STATE_VALID_BREAKOUT_BULLISH && rsiM5 < InpRSILongInvalidation) isInvalid = true;
   if(ExtBreakoutState == STATE_VALID_BREAKOUT_BEARISH && rsiM5 > InpRSIShortInvalidation) isInvalid = true;
   
   if(isInvalid) {
      if(ExtLimitOrderPlaced) {
         CancelAllLimits();
      }
      CloseAllPositions();
      ExtBreakoutState = STATE_WAITING;
   }
  }

//+------------------------------------------------------------------+
//| Market Order Execution                                           |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_ORDER_TYPE type, double price)
  {
   double sl = CalculateSL(type, price);
   double tp = CalculateTP(type, price, sl);
   double vol = CalculateLotSize(MathAbs(price - sl));
   
   if(type == ORDER_TYPE_BUY) {
      if(!ExtTrade.Buy(vol, _Symbol, price, sl, tp, "Super Breakout Market Buy")) {
         Print("Buy Error: ", GetLastError());
      }
   }
   else if(type == ORDER_TYPE_SELL) {
      if(!ExtTrade.Sell(vol, _Symbol, price, sl, tp, "Super Breakout Market Sell")) {
         Print("Sell Error: ", GetLastError());
      }
   }
  }

//+------------------------------------------------------------------+
//| Limit Order Execution                                            |
//+------------------------------------------------------------------+
void PlaceLimitOrder(ENUM_ORDER_TYPE type, double price)
  {
   double sl = CalculateSL(type == ORDER_TYPE_BUY_LIMIT ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, price);
   double tp = CalculateTP(type == ORDER_TYPE_BUY_LIMIT ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, price, sl);
   double vol = CalculateLotSize(MathAbs(price - sl));   
   
   if(type == ORDER_TYPE_BUY_LIMIT) {
      if(!ExtTrade.BuyLimit(vol, price, _Symbol, sl, tp, ORDER_TIME_DAY, 0, "SMC Limit Buy")) {
         Print("Buy Limit Error: ", GetLastError());
      }
   }
   else if(type == ORDER_TYPE_SELL_LIMIT) {
      if(!ExtTrade.SellLimit(vol, price, _Symbol, sl, tp, ORDER_TIME_DAY, 0, "SMC Limit Sell")) {
         Print("Sell Limit Error: ", GetLastError());
      }
   }
  }

//+------------------------------------------------------------------+
//| Calculations: SL, TP, and Lot Sizing                             |
//+------------------------------------------------------------------+
double CalculateSL(ENUM_ORDER_TYPE type, double price)
  {
   double sl = 0;
   if(InpSLMode == SL_ATR) {
      if(CopyBuffer(ExtATRHandle, 0, 1, 1, ExtATRBuffer) > 0) {
         double atrRaw = ExtATRBuffer[0];
         if(type == ORDER_TYPE_BUY) sl = price - (atrRaw * InpATRMultiplier);
         else if(type == ORDER_TYPE_SELL) sl = price + (atrRaw * InpATRMultiplier);
      }
   }
   return NormalizeDouble(sl, _Digits);
  }

double CalculateTP(ENUM_ORDER_TYPE type, double price, double sl)
  {
   double tp = 0;
   if(InpTPMode == TP_RISK_REWARD) {
      double riskDist = MathAbs(price - sl);
      if(type == ORDER_TYPE_BUY) tp = price + (riskDist * InpRRRatio);
      else if(type == ORDER_TYPE_SELL) tp = price - (riskDist * InpRRRatio);
   }
   return NormalizeDouble(tp, _Digits);
  }

double CalculateLotSize(double slDist)
  {
   if(InpRiskMode == FIXED_LOTS) return InpFixedLotSize;
   if(slDist == 0) return ExtSymbol.LotsMin();
   
   double accBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = accBal * (InpRiskPercent / 100.0);
   
   double tickValue = ExtSymbol.TickValue();
   double tickSize = ExtSymbol.TickSize();
   
   double pipsToLoss = slDist / tickSize;
   if(pipsToLoss * tickValue == 0) return ExtSymbol.LotsMin();
   
   double vol = riskMoney / (pipsToLoss * tickValue);
   
   double step = ExtSymbol.LotsStep();
   vol = MathFloor(vol / step) * step;
   
   if(vol < ExtSymbol.LotsMin()) vol = ExtSymbol.LotsMin();
   if(vol > ExtSymbol.LotsMax()) vol = ExtSymbol.LotsMax();
   
   return vol;
  }

//+------------------------------------------------------------------+
//| Position Modifiers: BE & Weekend Checks                          |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   if(!InpBreakEven) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(ExtPosition.SelectByIndex(i)) {
         if(ExtPosition.Symbol() == _Symbol && ExtPosition.Magic() == InpMagicNumber) {
            double entry = ExtPosition.PriceOpen();
            double sl = ExtPosition.StopLoss();
            double tp = ExtPosition.TakeProfit();
            double curPrice = ExtPosition.PriceCurrent();
            
            double expectedRisk = MathAbs(entry - sl); 
            if(expectedRisk == 0) continue;
            
            bool allowModify = false;
            double newSL = entry;
            
            if(ExtPosition.PositionType() == POSITION_TYPE_BUY) {
               if(curPrice >= entry + (expectedRisk * InpBreakEvenRR)) {
                  if(sl < entry) { // Not BE yet
                     newSL = entry + ExtSymbol.Spread() * ExtSymbol.Point();
                     allowModify = true;
                  }
               }
            }
            else {
               if(curPrice <= entry - (expectedRisk * InpBreakEvenRR)) {
                  if(sl > entry || sl == 0) { // Not BE yet
                     newSL = entry - ExtSymbol.Spread() * ExtSymbol.Point();
                     allowModify = true;
                  }
               }
            }
            
            if(allowModify) {
               if(!ExtTrade.PositionModify(ExtPosition.Ticket(), newSL, tp)) {
                  Print("BE Mod Error: ", GetLastError());
               }
            }
         }
      }
   }
  }

void HandleWeekendGap()
  {
   if(!InpWeekendGapProtection) return;
   
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   if(dt.day_of_week == 5) { // Friday
      if(dt.hour > InpFridayCloseHour || (dt.hour == InpFridayCloseHour && dt.min >= InpFridayCloseMinute)) {
         CloseAllPositions();
         CancelAllLimits();
         ExtBreakoutState = STATE_WAITING;
      }
   }
   
   if(dt.day_of_week == 1) { // Monday
      if(dt.hour < InpMondayOpenHour || (dt.hour == InpMondayOpenHour && dt.min < InpMondayOpenMinute)) {
         ExtBreakoutState = STATE_WAITING; // Lock out entries
      }
   }
  }

bool HasOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(ExtPosition.SelectByIndex(i)) {
         if(ExtPosition.Symbol() == _Symbol && ExtPosition.Magic() == InpMagicNumber) return true;
      }
   }
   return false;
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(ExtPosition.SelectByIndex(i)) {
         if(ExtPosition.Symbol() == _Symbol && ExtPosition.Magic() == InpMagicNumber) {
            ExtTrade.PositionClose(ExtPosition.Ticket());
         }
      }
   }
  }

void CancelAllLimits()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket)) {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
            ExtTrade.OrderDelete(ticket);
         }
      }
   }
   ExtLimitOrderPlaced = false;
  }

//+------------------------------------------------------------------+
//| Chart Information Update                                         |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
   double rsiM5 = 0;
   if(ExtRSIHandle != INVALID_HANDLE) {
      if(CopyBuffer(ExtRSIHandle, 0, 0, 1, ExtRSIBuffer) > 0) rsiM5 = ExtRSIBuffer[0];
   }
   
   string bStatus = "WAITING";
   if(ExtBreakoutState == STATE_VALID_BREAKOUT_BULLISH) bStatus = "BULLISH BREAKOUT - AWAITING TRIGGER";
   if(ExtBreakoutState == STATE_VALID_BREAKOUT_BEARISH) bStatus = "BEARISH BREAKOUT - AWAITING TRIGGER";
   
   string riskStr = (InpRiskMode == PERCENT_BALANCE) ? StringFormat("%.2f%% Base", InpRiskPercent) : StringFormat("%.2f Lots Base", InpFixedLotSize);
   
   string comment = "--- SUPER BREAKOUT SMC ---\n" +
                    "Symbol: " + _Symbol + "\n" +
                    "Broker GMT Offset: " + (CalculateGMTOffset() >= 0 ? "+" : "") + IntegerToString(CalculateGMTOffset()) + " hrs\n" +
                    "Risk Mode: " + riskStr + "\n" +
                    StringFormat("Session High: %.5f | Low: %.5f\n", ExtSessionHigh, ExtSessionLow) +
                    StringFormat("M5 RSI(9): %.2f\n", rsiM5) +
                    "State: " + bStatus + "\n" +
                    "Active Limits: " + (ExtLimitOrderPlaced ? "TRUE" : "FALSE") + "\n";
                    
   Comment(comment);
  }
//+------------------------------------------------------------------+
