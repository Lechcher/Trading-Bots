#pragma warning disable CS0618 // Suppress obsolete API warnings for seamless compilation across cTrader versions

using System;
using System.Linq;
using cAlgo.API;
using cAlgo.API.Indicators;
using cAlgo.API.Internals;

namespace cAlgo.Robots
{
    public enum LotMode 
    { 
        Fixed_Lots, 
        Risk_Percent 
    }

    public enum TpSlMode 
    { 
        Fixed_Pips, 
        ATR_Dynamic 
    }

    [Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class GoldBreakoutCBot : Robot
    {
        //+------------------------------------------------------------------+
        //| INPUT PARAMETERS                                                 |
        //+------------------------------------------------------------------+
        [Parameter("Restrict To Gold", Group = "Trade & Risk Management", DefaultValue = false)]
        public bool Restrict_To_Gold { get; set; }

        [Parameter("Lot Size Mode", Group = "Trade & Risk Management", DefaultValue = LotMode.Risk_Percent)]
        public LotMode Lot_Size_Mode { get; set; }

        [Parameter("Fixed Lots", Group = "Trade & Risk Management", DefaultValue = 0.01)]
        public double Lots { get; set; }

        [Parameter("Risk % of Balance", Group = "Trade & Risk Management", DefaultValue = 0.5)]
        public double RiskPercent { get; set; }

        [Parameter("Max Spread (Pips)", Group = "Trade & Risk Management", DefaultValue = 3.0)]
        public double Max_Spread_Pips { get; set; }

        [Parameter("Bot Label (Magic)", Group = "Trade & Risk Management", DefaultValue = "GoldBreakout")]
        public string BotLabel { get; set; }

        [Parameter("Calculation Timeframe", Group = "Strategy & Breakout Settings", DefaultValue = "Minute15")]
        public TimeFrame CalcTimeframe { get; set; }

        [Parameter("Lookback Bars (N)", Group = "Strategy & Breakout Settings", DefaultValue = 15)]
        public int BarsN { get; set; }

        [Parameter("Order Buffer Dist (Pips)", Group = "Strategy & Breakout Settings", DefaultValue = 1.0)]
        public double OrderDistPips { get; set; }

        [Parameter("Order Expiration (Hours)", Group = "Strategy & Breakout Settings", DefaultValue = 1)]
        public int ExpirationHours { get; set; }

        [Parameter("Use Trend Filter", Group = "Higher Timeframe Trend Filter", DefaultValue = true)]
        public bool Use_Trend_Filter { get; set; }

        [Parameter("Trend Timeframe", Group = "Higher Timeframe Trend Filter", DefaultValue = "Hour1")]
        public TimeFrame Trend_Timeframe { get; set; }

        [Parameter("Trend MA Period", Group = "Higher Timeframe Trend Filter", DefaultValue = 50)]
        public int Trend_MA_Period { get; set; }

        [Parameter("Trend MA Method", Group = "Higher Timeframe Trend Filter", DefaultValue = MovingAverageType.Exponential)]
        public MovingAverageType Trend_MA_Method { get; set; }

        [Parameter("TP & SL Mode", Group = "TP & SL Calculation Mode", DefaultValue = TpSlMode.ATR_Dynamic)]
        public TpSlMode TPSL_Mode { get; set; }

        [Parameter("Fixed TP (Pips)", Group = "TP & SL Calculation Mode", DefaultValue = 100.0)]
        public double TpPips { get; set; }

        [Parameter("Fixed SL (Pips)", Group = "TP & SL Calculation Mode", DefaultValue = 30.0)]
        public double SlPips { get; set; }

        [Parameter("ATR Period", Group = "TP & SL Calculation Mode", DefaultValue = 14)]
        public int ATR_Period { get; set; }

        [Parameter("ATR Multiplier for TP", Group = "TP & SL Calculation Mode", DefaultValue = 6.0)]
        public double ATR_TP_Multiplier { get; set; }

        [Parameter("ATR Multiplier for SL", Group = "TP & SL Calculation Mode", DefaultValue = 2.0)]
        public double ATR_SL_Multiplier { get; set; }

        [Parameter("TSL Trigger (Pips)", Group = "Trailing Stop Settings", DefaultValue = 1.5)]
        public double TslTriggerPips { get; set; }

        [Parameter("TSL Distance (Pips)", Group = "Trailing Stop Settings", DefaultValue = 1.0)]
        public double TslPips { get; set; }

        [Parameter("Close On Friday", Group = "Weekend Gap Protection", DefaultValue = true)]
        public bool Close_On_Friday { get; set; }

        [Parameter("Friday Close Hour", Group = "Weekend Gap Protection", DefaultValue = 22)]
        public int Friday_Close_Hour { get; set; }

        [Parameter("Friday Close Minute", Group = "Weekend Gap Protection", DefaultValue = 45)]
        public int Friday_Close_Minute { get; set; }

        //+------------------------------------------------------------------+
        //| GLOBAL VARIABLES & OBJECTS                                       |
        //+------------------------------------------------------------------+
        private AverageTrueRange _atr;
        private MovingAverage _trendMa;
        private Bars _calcBars;
        private Bars _trendBars;
        
        private int _lastCloseDay = -1;
        private DateTime _lastOcoTime = DateTime.MinValue;
        private DateTime _lastTrendDelTime = DateTime.MinValue;

        protected override void OnStart()
        {
            // Restrict EA to XAUUSD / Gold only
            if (Restrict_To_Gold)
            {
                string sym = SymbolName.ToUpper();
                if (!sym.Contains("XAU") && !sym.Contains("GOLD"))
                {
                    Print("Initialization Failed: This cBot is exclusively optimized for Gold. Current symbol: ", SymbolName);
                    Stop();
                    return;
                }
            }

            // Setup Bars and Indicators securely with null checks
            _calcBars = MarketData.GetBars(CalcTimeframe, SymbolName);
            
            if (_calcBars == null)
            {
                Print("Initialization Failed: Could not load market data for {0}. Stopping cBot.", CalcTimeframe);
                Stop();
                return;
            }

            if (TPSL_Mode == TpSlMode.ATR_Dynamic)
            {
                _atr = Indicators.AverageTrueRange(_calcBars, ATR_Period, MovingAverageType.Simple);
            }

            if (Use_Trend_Filter)
            {
                _trendBars = MarketData.GetBars(Trend_Timeframe, SymbolName);
                
                if (_trendBars == null)
                {
                    Print("Initialization Error: Failed to load higher timeframe ({0}) data. Disabling Trend Filter to prevent crash.", Trend_Timeframe);
                    Use_Trend_Filter = false; // Fallback so backtest doesn't completely die
                }
                else
                {
                    _trendMa = Indicators.MovingAverage(_trendBars.ClosePrices, Trend_MA_Period, Trend_MA_Method);
                }
            }
        }

        protected override void OnTick()
        {
            // Indicator Data Loading Protection (Prevents NRE errors during the initial bars of a backtest)
            if (_calcBars == null || _calcBars.Count <= BarsN) return;
            if (Use_Trend_Filter && (_trendBars == null || _trendBars.Count <= Trend_MA_Period)) return;
            if (TPSL_Mode == TpSlMode.ATR_Dynamic && _calcBars.Count <= ATR_Period) return;

            // Weekend Gap Protection (Highest Priority)
            if (!IsTradingAllowed())
            {
                CloseAllTradesAndOrders();
                return; 
            }

            // 1. Spread Check
            double currentSpreadPips = Symbol.Spread / Symbol.PipSize;
            if (currentSpreadPips > Max_Spread_Pips)
                return; 

            // 2. Manage Trailing Stop
            ManageTrailingStop();

            // 3. Check existing positions and pending orders (OCO Logic)
            var activePositions = Positions.FindAll(BotLabel, SymbolName);
            var pendingOrders = PendingOrders.Where(o => o != null && o.Label == BotLabel && o.SymbolName == SymbolName).ToArray();

            bool hasBuyStop = false;
            bool hasSellStop = false;
            PendingOrder buyStopOrder = null;
            PendingOrder sellStopOrder = null;

            foreach (var order in pendingOrders)
            {
                if (order.TradeType == TradeType.Buy && order.OrderType == PendingOrderType.Stop)
                {
                    hasBuyStop = true;
                    buyStopOrder = order;
                }
                else if (order.TradeType == TradeType.Sell && order.OrderType == PendingOrderType.Stop)
                {
                    hasSellStop = true;
                    sellStopOrder = order;
                }
            }

            // OCO Logic: If we have an active position, delete any remaining pending orders
            if (activePositions != null && activePositions.Length > 0)
            {
                if ((Server.Time - _lastOcoTime).TotalSeconds >= 60)
                {
                    bool ocoAttempt = false;
                    if (hasBuyStop && buyStopOrder != null) { CancelPendingOrder(buyStopOrder); ocoAttempt = true; }
                    if (hasSellStop && sellStopOrder != null) { CancelPendingOrder(sellStopOrder); ocoAttempt = true; }

                    if (ocoAttempt) _lastOcoTime = Server.Time;
                }
                return; // Do not place new breakouts while in a trade
            }

            // 4. Trend Filter Logic
            bool allowBuy = true;
            bool allowSell = true;

            if (Use_Trend_Filter)
            {
                // Ensure the MA is safely populated before attempting to extract a value
                if (_trendMa != null && _trendBars != null && _trendBars.Count > Trend_MA_Period)
                {
                    double maValue = _trendMa.Result.Last(1);
                    
                    if (!double.IsNaN(maValue))
                    {
                        double currentPrice = Symbol.Bid;
                        if (currentPrice <= maValue) allowBuy = false;
                        if (currentPrice >= maValue) allowSell = false;
                    }
                }
            }

            // Delete pending orders that violate the trend filter
            if ((!allowBuy && hasBuyStop) || (!allowSell && hasSellStop))
            {
                if ((Server.Time - _lastTrendDelTime).TotalSeconds >= 60)
                {
                    if (!allowBuy && hasBuyStop && buyStopOrder != null) { CancelPendingOrder(buyStopOrder); hasBuyStop = false; }
                    if (!allowSell && hasSellStop && sellStopOrder != null) { CancelPendingOrder(sellStopOrder); hasSellStop = false; }
                    _lastTrendDelTime = Server.Time;
                }
            }

            // 5. Breakout Logic (Place or Update Pending Orders)
            double highestHigh = _calcBars.HighPrices.Last(1);
            double lowestLow = _calcBars.LowPrices.Last(1);

            for (int i = 1; i <= BarsN; i++)
            {
                highestHigh = Math.Max(highestHigh, _calcBars.HighPrices.Last(i));
                lowestLow = Math.Min(lowestLow, _calcBars.LowPrices.Last(i));
            }

            // Calculate Order Prices
            double bufferDistPrice = OrderDistPips * Symbol.PipSize;
            double buyPrice = highestHigh + bufferDistPrice;
            double sellPrice = lowestLow - bufferDistPrice;

            // Stop Level (Freeze) Check
            double minLevelDist = 5.0 * Symbol.PipSize; // standard failsafe
            bool validBuyPrice = (buyPrice >= Symbol.Ask + minLevelDist);
            bool validSellPrice = (sellPrice <= Symbol.Bid - minLevelDist);

            // Calculate TP and SL actual price distances
            double tpDistPrice = 0, slDistPrice = 0;
            GetSLTPDistances(out tpDistPrice, out slDistPrice);

            // Calculate Volume based on Risk
            double volumeInUnits = GetVolume(slDistPrice);

            // Expiration Time
            DateTime expiration = Server.Time.AddHours(ExpirationHours);

            // Strict modification threshold (Require at least 0.3 pips of change to prevent tick spam)
            double modifyThreshold = 0.3 * Symbol.PipSize;

            // Manage Buy Stop Order
            if (allowBuy && validBuyPrice)
            {
                double buyTargetSl = buyPrice - slDistPrice;
                double buyTargetTp = buyPrice + tpDistPrice;

                if (!hasBuyStop)
                {
                    TradeResult res = PlaceStopOrder(TradeType.Buy, SymbolName, volumeInUnits, buyPrice, BotLabel, buyTargetSl, buyTargetTp, expiration);
                    if (res != null && !res.IsSuccessful) Print("Buy Stop Placement Failed: ", res.Error, " | Vol: ", volumeInUnits, " | Price: ", buyPrice);
                }
                else if (buyStopOrder != null)
                {
                    double currentBuyPrice = buyStopOrder.TargetPrice;
                    double currentBuySlDist = buyStopOrder.StopLoss.HasValue ? Math.Abs(currentBuyPrice - buyStopOrder.StopLoss.Value) : 0;
                    double currentBuyTpDist = buyStopOrder.TakeProfit.HasValue ? Math.Abs(buyStopOrder.TakeProfit.Value - currentBuyPrice) : 0;

                    if (Math.Abs(currentBuyPrice - buyPrice) > modifyThreshold ||
                        Math.Abs(currentBuySlDist - slDistPrice) > modifyThreshold ||
                        Math.Abs(currentBuyTpDist - tpDistPrice) > modifyThreshold)
                    {
                        if (currentBuyPrice >= Symbol.Ask + minLevelDist)
                        {
                            TradeResult res = ModifyPendingOrder(buyStopOrder, buyPrice, buyTargetSl, buyTargetTp, expiration);
                            if (res != null && !res.IsSuccessful) Print("Buy Stop Modification Failed: ", res.Error);
                        }
                    }
                }
            }

            // Manage Sell Stop Order
            if (allowSell && validSellPrice)
            {
                double sellTargetSl = sellPrice + slDistPrice;
                double sellTargetTp = sellPrice - tpDistPrice;

                if (!hasSellStop)
                {
                    TradeResult res = PlaceStopOrder(TradeType.Sell, SymbolName, volumeInUnits, sellPrice, BotLabel, sellTargetSl, sellTargetTp, expiration);
                    if (res != null && !res.IsSuccessful) Print("Sell Stop Placement Failed: ", res.Error, " | Vol: ", volumeInUnits, " | Price: ", sellPrice);
                }
                else if (sellStopOrder != null)
                {
                    double currentSellPrice = sellStopOrder.TargetPrice;
                    double currentSellSlDist = sellStopOrder.StopLoss.HasValue ? Math.Abs(sellStopOrder.StopLoss.Value - currentSellPrice) : 0;
                    double currentSellTpDist = sellStopOrder.TakeProfit.HasValue ? Math.Abs(currentSellPrice - sellStopOrder.TakeProfit.Value) : 0;

                    if (Math.Abs(currentSellPrice - sellPrice) > modifyThreshold ||
                        Math.Abs(currentSellSlDist - slDistPrice) > modifyThreshold ||
                        Math.Abs(currentSellTpDist - tpDistPrice) > modifyThreshold)
                    {
                        if (currentSellPrice <= Symbol.Bid - minLevelDist)
                        {
                            TradeResult res = ModifyPendingOrder(sellStopOrder, sellPrice, sellTargetSl, sellTargetTp, expiration);
                            if (res != null && !res.IsSuccessful) Print("Sell Stop Modification Failed: ", res.Error);
                        }
                    }
                }
            }
        }

        //+------------------------------------------------------------------+
        //| CALCULATE TP & SL DISTANCES (IN PRICE VALUE)                     |
        //+------------------------------------------------------------------+
        private void GetSLTPDistances(out double tpDistPrice, out double slDistPrice)
        {
            if (TPSL_Mode == TpSlMode.Fixed_Pips)
            {
                tpDistPrice = TpPips * Symbol.PipSize;
                slDistPrice = SlPips * Symbol.PipSize;
            }
            else // ATR_Dynamic
            {
                // Verify ATR indicator is valid and populated before accessing
                if (_atr != null && _calcBars != null && _calcBars.Count > ATR_Period) 
                {
                    double currentAtr = _atr.Result.Last(1);
                    tpDistPrice = currentAtr * ATR_TP_Multiplier;
                    slDistPrice = currentAtr * ATR_SL_Multiplier;
                }
                else
                {
                    // Fallback to fixed pips if ATR fails to load temporarily
                    tpDistPrice = TpPips * Symbol.PipSize;
                    slDistPrice = SlPips * Symbol.PipSize;
                }
            }
        }

        //+------------------------------------------------------------------+
        //| LOT SIZE CALCULATION (RISK MANAGEMENT)                           |
        //+------------------------------------------------------------------+
        private double GetVolume(double slDistPrice)
        {
            double volumeCalc = 0;

            if (Lot_Size_Mode == LotMode.Fixed_Lots) 
            {
                volumeCalc = Symbol.QuantityToVolumeInUnits(Lots);
            }
            else
            {
                double balance = Account.Balance;
                double riskMoney = balance * (RiskPercent / 100.0);

                if (slDistPrice <= 0 || Symbol.TickValue <= 0)
                    return Symbol.VolumeInUnitsMin;

                // Loss for 1 unit of volume (Price Distance * Value per Unit of price move)
                double valuePerUnit = Symbol.TickValue / Symbol.TickSize;
                double lossPerUnit = slDistPrice * valuePerUnit;

                if (lossPerUnit == 0) return Symbol.VolumeInUnitsMin;

                // Calculate raw lot size
                volumeCalc = riskMoney / lossPerUnit;
            }

            // Normalize strictly to Broker requirements
            double normalizedVol = Symbol.NormalizeVolumeInUnits(volumeCalc, RoundingMode.Down);
            
            // Failsafe: Ensure volume is not less than broker's absolute minimum (prevents silent order rejection)
            if (normalizedVol < Symbol.VolumeInUnitsMin) 
            {
                normalizedVol = Symbol.VolumeInUnitsMin;
            }

            return normalizedVol;
        }

        //+------------------------------------------------------------------+
        //| TRAILING STOP MANAGEMENT                                         |
        //+------------------------------------------------------------------+
        private void ManageTrailingStop()
        {
            if (TslTriggerPips <= 0 || TslPips <= 0) return;

            double tslTriggerPrice = TslTriggerPips * Symbol.PipSize;
            double tslDistPrice = TslPips * Symbol.PipSize;
            double minStep = 0.5 * Symbol.PipSize; // Require 0.5 pip change to send server request

            var activePositions = Positions.FindAll(BotLabel, SymbolName);
            if (activePositions == null) return;

            foreach (var pos in activePositions)
            {
                if (pos == null) continue;

                double minStopLevel = Symbol.Spread * 1.5 + (0.5 * Symbol.PipSize); 
                double minDistToTp = Math.Max(tslDistPrice, minStopLevel);

                if (pos.TradeType == TradeType.Buy)
                {
                    // FREEZE CHECK
                    if (pos.TakeProfit.HasValue && Math.Abs(pos.TakeProfit.Value - Symbol.Bid) <= minStopLevel) continue;
                    if (pos.StopLoss.HasValue && Math.Abs(Symbol.Bid - pos.StopLoss.Value) <= minStopLevel) continue;

                    if (Symbol.Bid - pos.EntryPrice >= tslTriggerPrice)
                    {
                        double newSl = Symbol.Bid - tslDistPrice;
                        double currentSl = pos.StopLoss ?? 0.0;

                        if (newSl > currentSl + minStep && newSl <= Symbol.Bid - minStopLevel)
                        {
                            if (!pos.TakeProfit.HasValue || (pos.TakeProfit.Value - newSl) >= minDistToTp)
                            {
                                pos.ModifyStopLossPrice(newSl); // Specific target modifier
                            }
                        }
                    }
                }
                else if (pos.TradeType == TradeType.Sell)
                {
                    // FREEZE CHECK
                    if (pos.TakeProfit.HasValue && Math.Abs(Symbol.Ask - pos.TakeProfit.Value) <= minStopLevel) continue;
                    if (pos.StopLoss.HasValue && Math.Abs(pos.StopLoss.Value - Symbol.Ask) <= minStopLevel) continue;

                    if (pos.EntryPrice - Symbol.Ask >= tslTriggerPrice)
                    {
                        double newSl = Symbol.Ask + tslDistPrice;
                        double currentSl = pos.StopLoss ?? double.MaxValue;

                        if ((!pos.StopLoss.HasValue || newSl < currentSl - minStep) && newSl >= Symbol.Ask + minStopLevel)
                        {
                            if (!pos.TakeProfit.HasValue || (newSl - pos.TakeProfit.Value) >= minDistToTp)
                            {
                                pos.ModifyStopLossPrice(newSl); // Specific target modifier
                            }
                        }
                    }
                }
            }
        }

        //+------------------------------------------------------------------+
        //| WEEKEND GAP PROTECTION LOGIC                                     |
        //+------------------------------------------------------------------+
        private bool IsTradingAllowed()
        {
            if (!Close_On_Friday) return true;

            DateTime dt = Server.Time;

            // Check if it's past the designated time on Friday
            if (dt.DayOfWeek == DayOfWeek.Friday)
            {
                if (dt.Hour > Friday_Close_Hour || (dt.Hour == Friday_Close_Hour && dt.Minute >= Friday_Close_Minute))
                    return false;
            }
            // Block trading on Saturday and Sunday
            else if (dt.DayOfWeek == DayOfWeek.Saturday || dt.DayOfWeek == DayOfWeek.Sunday)
            {
                return false;
            }

            return true;
        }

        //+------------------------------------------------------------------+
        //| CLOSE ALL TRADES AND PENDING ORDERS                              |
        //+------------------------------------------------------------------+
        private void CloseAllTradesAndOrders()
        {
            DateTime dt = Server.Time;

            // "One-Shot" Friday Close
            if (dt.DayOfYear == _lastCloseDay) return;

            bool actionTaken = false;

            var positions = Positions.FindAll(BotLabel, SymbolName);
            if (positions != null)
            {
                foreach (var pos in positions)
                {
                    if (pos != null) ClosePosition(pos);
                    actionTaken = true;
                }
            }

            var orders = PendingOrders.Where(o => o != null && o.Label == BotLabel && o.SymbolName == SymbolName).ToArray();
            if (orders != null)
            {
                foreach (var order in orders)
                {
                    if (order != null) CancelPendingOrder(order);
                    actionTaken = true;
                }
            }

            if (actionTaken) _lastCloseDay = dt.DayOfYear;
        }
    }
}