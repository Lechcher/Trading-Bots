# MT5 EA Development Brief: "The Trend Terminator"

**Target Platform:** MetaTrader 5 (MQL5)
**Target Symbol:** EURUSD (Optimized for major pairs)
**Default Timeframe:** M15 (15 Minutes)
**Execution Type:** Market Execution

## 1. STRATEGY OVERVIEW
"The Trend Terminator" is a trend-following pullback system. It uses an EMA to determine the long-term trend, RSI to ensure the momentum is still valid during the pullback, and CCI as a precise entry trigger. The EA splits the entry into two parts (or manages a single position via partial close depending on the account system) to secure an initial fixed/ATR profit (TP1) and lets the rest ride until the trend exhausts (TP2 via CCI opposite signal), protecting the runner with a true break-even buffer.

## 2. ENTRY LOGIC
The EA must check conditions strictly on the close of the current bar (i.e., Shift 1) to prevent repainting. 

### BUY Condition (Must meet ALL 3 on Shift 1):
1. **Trend Filter:** Close[1] > EMA (200).
2. **Momentum Filter:** RSI (14) > 50 (Price is pulling back, but overall momentum is still bullish).
3. **Trigger:** CCI (20) crosses ABOVE the -100 level from below (CCI[2] < -100 AND CCI[1] >= -100).

### SELL Condition (Must meet ALL 3 on Shift 1):
1. **Trend Filter:** Close[1] < EMA (200).
2. **Momentum Filter:** RSI (14) < 50.
3. **Trigger:** CCI (20) crosses BELOW the +100 level from above (CCI[2] > 100 AND CCI[1] <= 100).

*Note: Max allowed open positions per symbol is 1 (or 2 tickets if Hedging mode is creating split orders for the same signal).*

## 3. TRADE MANAGEMENT
* **Order Execution:** The EA must automatically detect the account margin mode using `AccountInfoInteger(ACCOUNT_MARGIN_MODE)`.
    * For **MT5 Hedging accounts**: Open **2 separate tickets** of equal size (e.g., 0.5 lot each if total calculated risk is 1 lot) at the same time to manage TP1 and TP2 separately.
    * For **MT5 Netting accounts**: Open **1 single position**, close 50% of the volume at TP1, and manage the remaining volume for TP2.
* **Volume Edge Case (CRITICAL):** If the calculated lot size is minimal (e.g., 0.01) and cannot be divided by 2 based on the broker's `SYMBOL_VOLUME_STEP`, the EA must NOT split the trade. It should open a single 0.01 lot trade and apply TP2 logic directly (skipping TP1 partial close, but still applying Break-Even at TP1 distance).

## 4. STOP LOSS & TAKE PROFIT LOGIC
* **Stop Loss (SL):** * Option 1: Fixed Points.
    * Option 2: ATR Multiplier (Default: ATR 14, Multiplier 1.5). Apply to Entry Price.
* **Take Profit 1 (TP1):** * Option 1: Fixed Points.
    * Option 2: ATR Multiplier (Default: ATR 14, Multiplier 1.5).
    * *Action:* Close 50% of the initial position size.
* **Take Profit 2 (TP2):**
    * Option 1: Fixed Points.
    * Option 2: ATR Multiplier.
    * Option 3: **CCI Signal (Default)** - Close the remaining 50% when CCI reaches the opposite extreme AND hooks back. 
        * *For BUY:* Track if CCI > +100. If true, wait for CCI[1] < +100 to close.
        * *For SELL:* Track if CCI < -100. If true, wait for CCI[1] > -100 to close.
* **Break-Even (BE):**
    * Once price reaches TP1 distance, immediately move the SL of the remaining position to `Entry Price + Break-even Buffer`.
    * **Break-even Buffer:** Input in points (e.g., 20 points) to cover spread/commission.

## 5. REQUIRED INPUT PARAMETERS (Categorized)

### --- Money Management ---
* **Lot Sizing Method:** [Dropdown: Fixed Lots / % Risk per Trade] (Default: % Risk)
* **Risk %:** 1.0 (Risk 1% of Balance if SL is hit)
* **Fixed Lots:** 0.1

### --- Indicators Settings ---
* **EMA Period:** 200
* **RSI Period:** 14
* **RSI Center Line:** 50
* **CCI Period:** 20

### --- SL, TP & Break-Even ---
* **SL Calculation Method:** [Dropdown: ATR / Fixed Points] (Default: ATR)
* **TP1 Calculation Method:** [Dropdown: ATR / Fixed Points] (Default: ATR)
* **TP2 Calculation Method:** [Dropdown: CCI Signal / ATR / Fixed Points] (Default: CCI Signal)
* **ATR Period:** 14
* **SL ATR Multiplier:** 1.5
* **TP1 ATR Multiplier:** 1.5
* **TP2 ATR Multiplier:** 3.0 (Only used if TP2 method = ATR)
* **Fixed SL (Points):** 200
* **Fixed TP1 (Points):** 200
* **Fixed TP2 (Points):** 400
* **Break-Even Buffer (Points):** 20 (Added to Entry price for buys, subtracted for sells)

### --- Trading Sessions (Broker Server Time) ---
* **Enable Session Filter:** [True/False] (Default: True)
* **Sydney Session:** [True/False] | Start: 00:00 | End: 09:00
* **Tokyo Session:** [True/False] | Start: 02:00 | End: 11:00
* **London Session:** [True/False] | Start: 10:00 | End: 18:30
* **New York Session:** [True/False] | Start: 15:00 | End: 23:00

### --- News Filter (MT5 Built-in Economic Calendar) ---
* **Enable News Filter:** [True/False] (Default: True)
* **Filter High Impact News:** [True/False] (Default: True)
* **Filter Medium Impact News:** [True/False]
* **Filter Low Impact News:** [True/False]
* **Minutes Pause Before News:** 30
* **Minutes Pause After News:** 30
* *Action:* Do not open NEW trades during the restricted news windows. Existing trades continue to be managed by SL/TP/BE.

### --- Friday Close ---
* **Enable Friday Close:** [True/False] (Default: True)
* **Friday Close Time:** 22:45 (Broker Time)
* *Action:* At this exact time on Friday, the EA must force-close all open positions and delete any pending orders. No new trades until Monday.

## 6. DEVELOPMENT NOTES & REQUIREMENTS
1. **Strict Error Handling:** Use `MqlTradeRequest` and `MqlTradeResult` carefully. Handle requotes, check `SYMBOL_VOLUME_MIN` and `SYMBOL_VOLUME_STEP` for partial closing, and implement MT5 netting vs hedging checks natively via `AccountInfoInteger(ACCOUNT_MARGIN_MODE)`.
2. **No Repainting:** Indicators must only be read at index 1 and 2.
3. **Comments & Magic Number:** Input for Magic Number and custom Trade Comment.
4. **News Filter Backtest Fallback:** MT5 built-in Economic Calendar often fails in Strategy Tester. Please add a check: `if(MQLInfoInteger(MQL_TESTER))` bypass the news filter so the EA can be properly backtested.

## 7. AI INSTRUCTIONS (For Output Generation)
* Act as a senior MQL5 Algo-developer.
* Provide the full, complete `.mq5` code. DO NOT use placeholders like `// ... insert rest of code here`.
* Organize the code clearly with standard MQL5 structures: `OnInit`, `OnDeinit`, `OnTick`.
* Implement the Partial Close and Break-even logics in separate, clearly named void functions.
* If the code is too long for one response, stop cleanly and ask me to prompt "Continue" to generate the rest.