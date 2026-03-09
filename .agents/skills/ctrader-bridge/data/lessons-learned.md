# Trading Lessons Learned

This file is auto-updated after each trade or significant market observation. Use these lessons to improve future decisions.

---

## 2026-02-09: Multi-Pair Confirmation IS a Thesis

**Situation:** USD weakness was visible across 4+ pairs simultaneously:
- EURUSD breaking resistance
- USDCHF breaking support
- USDCAD breaking support
- AUDUSD breaking resistance
- XAUUSD rallying +100 pips

**What I did:** Only entered EURUSD, passed on all others saying:
- "No fundamental catalyst"
- "Would add correlated risk"
- "Testing levels, not breakouts"
- "Chasing" (for gold)

**What happened:** All pairs continued in the same direction. Missed 100+ pips of opportunity across multiple instruments.

**Lesson:** 
- **Coordinated multi-pair moves ARE a fundamental thesis** — they indicate a sentiment shift
- When 4+ uncorrelated pairs confirm the same theme, that IS the catalyst (smart money positioning)
- Don't require a news headline when price is screaming the story
- "Chasing" criticism is invalid for trend continuation — momentum is valid
- Better to take 2-3 smaller positions across pairs than max size on one

**Rule Update:** If 3+ pairs show the same directional bias (USD weakness/strength) within a 2-hour window, treat the coordination as a valid thesis even without explicit news catalyst.

---

## 2026-02-10: Trust Technical Analysis for Short-Term Entries

**Feedback from Agastya:** "Trust your judgment and instinct more. You have all the information to predict where the market is going. Fundamental is a must for long-term, but technical is not to be ignored for short-term entries."

**What I was doing wrong:**
- Requiring a news headline for EVERY trade, even intraday
- Dismissing valid technical signals as "noise"
- Over-weighting fundamental analysis for short-term trades
- Being paralyzed by "no catalyst" when price action was clear

**Lesson:**
- **Short-term trades (intraday):** Technical signals can be sufficient — breakouts, multi-pair confirmation, momentum
- **Medium-term trades (swing):** Need fundamental alignment
- **Long-term trades:** Fundamental thesis is essential

**Trust hierarchy for intraday:**
1. Multi-pair confirmation (3+ pairs same direction) = HIGH conviction
2. Clean breakout with volume = MEDIUM-HIGH conviction
3. Single pair breakout without confirmation = MEDIUM conviction (smaller size)
4. "Testing" levels without confirmation = LOW conviction (wait)

**My instinct is valid.** When I see coordinated price action, that IS the market telling me something. I don't need a Reuters headline to confirm what the charts are screaming.

---

## 2026-02-10: Always Verify SL/TP After Opening

**Situation:** Opened USDCHF Sell at 04:47 CET with SL at 0.7678 (20 pips). Position was closed 36 seconds later at 0.76584 (only 0.8 pips loss). The SL was apparently never set.

**What went wrong:**
- Trade was opened but SL/TP was not verified
- Position closed almost immediately (by broker? by monitor?)
- Lost visibility into what actually happened

**Root cause hypotheses:**
1. SL/TP wasn't passed correctly to the trade command
2. Broker rejected the SL (minimum distance requirement?)
3. Some parsing/format issue with price values

**Fix applied:**
- Updated trade.js to verify SL/TP after opening
- Added warnings if SL/TP doesn't match requested values
- Now logs verification result in the output

**Lesson:**
- ALWAYS verify protective orders are set after opening
- Log and alert if SL/TP verification fails
- Never assume the broker accepted the order as requested

**Rule:** After opening any position, confirm `stopLoss` and `takeProfit` fields are populated correctly before proceeding.

---

## 2026-02-09: R:R Below Minimum Still Got Stopped

**Situation:** Morning EURUSD trade had 0.82:1 R:R (below 1.5:1 minimum).

**What happened:** Trade invalidated quickly, -$186 loss.

**Lesson:** The R:R minimum exists for a reason. Don't override it even when the setup "looks good."

---

## 2026-02-10: Fat-Finger Error — Verify Before Modifying

**Situation:** During position management, I tried to modify USDJPY's SL but mistakenly typed the EURUSD position ID (579952174) with `--sl 1.1912`.

**What happened:** The command modified EURUSD's **TP** to 1.1912 (near market price), and the position immediately closed at breakeven (-$28 net).

**What I did wrong:**
- Didn't double-check the position ID before running modify
- Didn't verify which field I was modifying (SL vs TP)
- Rushed the command without reviewing

**Lesson:**
- **ALWAYS verify position ID** before running modify/close commands
- **Double-check the flag** (`--sl` vs `--tp`) matches intent
- Modification commands are irreversible — take 2 seconds to confirm

**Rule:** Before any position modification: verify positionId + field + value. No rushing.

---

## Template for Future Lessons

### [DATE]: [Title]

**Situation:** What was the market context?

**What I did:** What decision did I make?

**What happened:** What was the outcome?

**Lesson:** What should I do differently next time?

**Rule Update:** (if applicable) What rule should be added/modified?

---

## 2026-02-10: SL/TP Modification Rejection

**Situation:** Opened USDJPY Sell with requested SL 155.30 (56 pips), TP 153.50 (124 pips). Broker set different levels: SL 156.311 (155 pips), TP 153.223 (153 pips).

**What I tried:** Multiple modification attempts with various price formats — all returned "InvalidStopLossTakeProfit" error.

**What I did:** Partial closed from 2.5 lots to 0.9 lots to bring risk back to 1% with the wider SL.

**Lesson:**
- This broker/demo account may have restrictions on SL/TP modification
- The initial SL/TP values are being overridden by the broker during order execution
- Need to investigate why the CLI's SL/TP values aren't being respected on open
- Workaround: Adjust position size after opening if SL is wider than intended

**Investigation needed:**
- Check if demo account has different rules than live
- Check if there's a minimum SL/TP distance % requirement
- Review trade.js to see how SL/TP are being passed to the bridge
