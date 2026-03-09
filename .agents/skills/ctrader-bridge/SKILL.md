---
name: ctrader-bridge
description: "Trade forex and gold on cTrader via ZMQ bridge. Autonomous trading with thesis-based position management."
metadata:
  openclaw:
    emoji: "📈"
    requires:
      bins: ["node"]
---

# cTrader Trading Bridge

AI-powered trading agent for cTrader. Connects via ZMQ to a cBot running on cTrader.

## Connection

- **Bridge address:** `tcp://144.76.7.79:51128`
- **Broker:** Raw Trading Ltd
- **Account:** #9659287

## Risk Parameters

- **Account equity:** ~$91,000 USD (demo)
- **Max risk per trade:** 1-2% of equity ($900-1800)
- **Max concurrent positions:** 4
- **Instruments:** Currency pairs and gold (XAUUSD) only
- **Trading style:** Intraday and swing trades

## Trading Philosophy

Every trade must have a **thesis** — a documented reason for entry with clear invalidation conditions. Theses are stored in `skill/theses/` as markdown files.

### Thesis Structure
- **Reasoning:** Why this trade makes sense
- **Entry criteria:** What triggered the entry
- **Invalidation conditions:** When to close regardless of P&L
- **Fundamental anchors:** Data points supporting the thesis

When fundamentals shift and invalidate the thesis, close the position — don't hope.

## Volume Units

**Volume is in UNITS, not lots!**
- EURUSD: 1000 units = 0.01 lots (lotSize = 100,000)
- XAUUSD: 1 unit = 0.01 lots (lotSize = 100)

## CLI Usage

All commands via: `node /root/clawd/skills/ctrader-bridge/scripts/trade.js <command>`

### Connection & Account
```bash
trade.js ping                    # Test connection
trade.js account                 # Get account info
trade.js positions               # List open positions
trade.js history [count]         # Get trade history
```

### Market Data
```bash
trade.js price <symbol>          # Get bid/ask price
trade.js price EURUSD,GBPUSD     # Multiple symbols
trade.js symbol <symbol>         # Get symbol specs
trade.js bars <symbol> [tf] [n]  # Get OHLCV candles
trade.js mtf <symbol>            # Multi-timeframe bars
```

### Trade Execution
```bash
trade.js open <symbol> <buy|sell> <volume> [sl] [tp] [comment]
trade.js close <positionId>
trade.js closeall
trade.js modify <positionId> [sl] [tp]
trade.js partial <positionId> <volume>
```

## Available Timeframes

For `getBars` and `getMultiTimeframeBars`:
```
Minute   Minute2  Minute3  Minute5  Minute10
Minute15 Minute30 Minute45
Hour     Hour2    Hour3    Hour4    Hour6    Hour8    Hour12
Daily    Day2     Day3     Weekly   Monthly
```

## Safety Guards (cBot side)

- **Max Positions:** 20 (configurable)
- **Max Volume Per Trade:** 100,000 units
- **Volume Normalization:** Rounded down to step size
- **Minimum Volume Check:** Orders below minimum rejected
- **Symbol Validation:** All symbols verified

## Risk Calculation

For a 1% risk trade on $91,000 equity = $910 max loss.

To calculate position size in units:
```
Units = Risk Amount / (SL Distance × Pip Value per Unit)
```

For EURUSD with 50 pip SL:
- Pip value per 1000 units = $0.10
- Units = $910 / (50 × $0.0001) = 182,000 units (1.82 lots)

## Example: Full Trade Flow

```javascript
const { OpenClawBridge } = require('./bridge/src/index');
const bridge = new OpenClawBridge();

await bridge.connect();

// 1. Get current price
const price = await bridge.getPrice('EURUSD');
// { symbol: 'EURUSD', bid: 1.0850, ask: 1.0852, spread: 0.00020 }

// 2. Get multi-timeframe analysis
const bars = await bridge.getMultiTimeframeBars('EURUSD', {
  Daily: 120,
  Hour4: 200,
  Minute15: 100
});

// 3. Open position with thesis link
const pos = await bridge.openPosition({
  symbol: 'EURUSD',
  side: 'Buy',
  volume: 10000,  // 0.1 lots
  stopLoss: 1.0800,
  takeProfit: 1.0950,
  comment: '2026-02-07-EURUSD-Buy-abc123.md'
});

// 4. Later: modify SL to breakeven
await bridge.modifyPosition(pos.positionId, { stopLoss: 1.0852 });

// 5. Close when thesis invalidates
await bridge.closePosition(pos.positionId);

await bridge.disconnect();
```

## Files

- `bridge/` — ZMQ client library
- `skill/` — Trading agent with thesis management
- `skill/theses/` — Thesis files for each trade
- `scripts/trade.js` — CLI helper
