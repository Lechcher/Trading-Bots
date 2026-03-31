# Super Breakout SMC EA - Strategy Summary

## Overview
This Expert Advisor is designed to trade Gold (XAUUSD) using a combination of Smart Money Concepts (SMC) and Momentum Breakout mechanics. The strategy aims to identify substantial breakouts from specific trading sessions, auto-calculate Fibonacci levels for entry, and utilize M5 RSI(9) to filter momentum and entry types.

## Strategy Specifications

### 1. Default Parameters
- **Symbol:** XAUUSD
- **Timeframes:** 
  - Main Structure = M15
  - Trigger/Momentum = M5
- **Trade Sessions (Killzones):**
  - Sydney: False
  - Tokyo: False
  - London: True (08:00 - 16:00 UTC)
  - New York: True (13:00 - 21:00 UTC)

### 2. Risk Management
- **Risk Mode:** Enum (`FixedLots`, `PercentBalance`) -> Default is `PercentBalance`.
- **Risk Dimension:** 
  - Risk Percent: 1.0%
  - Fixed Lot Size: 0.05 (If Risk Mode is `FixedLots`)
  
### 3. Exit Mechanics
- **Stop Loss (SL) Mode:** Enum (`FixedPips`, `ATR`, `Fibo`, `Structure`) -> Default is `ATR`.
  - ATR Multiplier: 1.6 * M15 ATR(14).
- **Take Profit (TP) Mode:** Enum (`FixedPips`, `ATR`, `FiboExtension`, `RiskReward`) -> Default is `RiskReward`.
  - RR Ratio: 2.0 (Target is 2R from entry).
- **Position Safety:** Break-Even mechanism that triggers at +1R and moves the SL to Entry Price + Spread.
- **Time Filter:** Weekend Gap Protection closes open trades on Friday at 21:45 UTC, and prevents new entries on Monday before 02:00 UTC.

### 4. Core Logic Setup
- **Step 1: Liquidity Mapping (M15)**: Find Highest High and Lowest Low of the most recently closed or currently active trading session (London/New York).
- **Step 2: Breakout Detection (M15)**: Wait for an M15 candle to stringently break and close *completely* outside the Session H/L boundary.
  - *Fakeout Protection*: Invalidate setup if price pierces the boundary but closes back inside with a strong opposite-colored candle.
- **Step 3: Auto-Fibonacci Entry Zone (M15)**: Calculate Impulse Leg from Swing Low/High to Breakout Apex. Define "Entry Zone" strictly at the 50% retracement.
- **Step 4: M5 Trigger & Execution**: 
  - *Healthy Momentum (Long)*: Price drops to 50% zone, M5 RSI(9) is between 60 and 85 -> Market Buy.
  - *Overextended (Long)*: Breakout happens but RSI > 85 -> No market entry. Place a Buy Limit at the 50% Fibo level and wait for the pullback.
  - *(Inverse logic for Shorts using 40-15 and < 15)*.
- **Step 5: Setup Invalidation**: Cancel Limit Orders or exit active trades if M5 RSI(9) drops below 20 (structural failure for Longs) or exceeds 80 (Shorts) before SL is hit.
