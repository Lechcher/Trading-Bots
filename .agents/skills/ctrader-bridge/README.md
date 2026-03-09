# OpenClaw - AI Trading Agent Bridge

OpenClaw connects an AI trading agent to a live cTrader trading account via ZeroMQ. It provides full programmatic access to account data, market data, and trade execution.

## Architecture

```
┌──────────────────────────────┐         ZeroMQ          ┌──────────────────────────────┐
│   OpenClaw (Node.js)         │    DEALER ──── ROUTER    │   AI Agent Bridge (cTrader)   │
│                              │                          │                              │
│  bridge/                     │   tcp://host:51128       │  cBot running inside cTrader  │
│    OpenClawBridge            │ ──────────────────────── │  Binds ROUTER socket          │
│    TradingBridgeClient       │   JSON request/response  │  Polls messages every 1s      │
│                              │                          │  Executes trades on account   │
│  skill/                      │                          │  Returns market data          │
│    TradingAgent              │                          │                              │
│    ThesisManager             │                          │  Panel UI shows:             │
│    FundamentalChecker        │                          │    - Bridge status            │
│                              │                          │    - Last command             │
└──────────────────────────────┘                          │    - Position count           │
                                                          └──────────────────────────────┘
```

**AI Agent Bridge cBot** (C#/.NET 6.0) runs inside cTrader desktop. It binds a ZeroMQ ROUTER socket and exposes the trading account to external clients. No license key needed - standalone from HeronCopier.

**OpenClaw Bridge Client** (Node.js) connects a DEALER socket to the cBot. It provides an async/await API with request/response correlation via UUIDs and automatic timeout handling.

## Protocol

All communication is JSON over ZeroMQ ROUTER/DEALER.

**Request format:**
```json
{
  "action": "getPrice",
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "params": { "symbol": "EURUSD" }
}
```

**Response format:**
```json
{
  "action": "getPriceResponse",
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "success": true,
  "data": { "symbol": "EURUSD", "bid": 1.18138, "ask": 1.18152, ... },
  "error": null
}
```

## Setup

### Bridge Client (Node.js)

```bash
cd OpenClaw/bridge
npm install
```

### AI Agent Bridge cBot (cTrader)

1. Open the solution `HeronCopier/cTrader/Heron Copier/AI Agent Bridge/AI Agent Bridge.sln` in Visual Studio
2. Build the project
3. In cTrader, load the "AI Agent Bridge" cBot onto any chart
4. Set the `Agent Bridge Address` parameter (default `tcp://0.0.0.0:51128`)
5. Ensure the port is open in your firewall

### Quick Test

```js
const { OpenClawBridge } = require('./bridge/src/index');

(async () => {
    const bridge = new OpenClawBridge('tcp://your-server:51128');
    await bridge.connect();

    console.log(await bridge.ping());
    // { status: 'ok', timestamp: '2026-02-07T21:30:04Z' }

    console.log(await bridge.getPrice('EURUSD'));
    // { symbol: 'EURUSD', bid: 1.18138, ask: 1.18152, spread: 0.00014, ... }

    await bridge.disconnect();
})();
```

## Available Actions

### Price & Market Data

#### `getPrice(symbol)`
Get current bid/ask price. Accepts a single symbol string or an array of symbols.

```js
// Single symbol
await bridge.getPrice('EURUSD')
// { symbol, bid, ask, spread, mid, pipSize, digits }

// Multiple symbols
await bridge.getPrice(['EURUSD', 'GBPUSD', 'USDJPY'])
// { prices: [ { symbol, bid, ask, spread, mid, pipSize, digits }, ... ] }
```

#### `getSymbolInfo(symbol)`
Get full symbol specifications including trading conditions.

```js
await bridge.getSymbolInfo('EURUSD')
// {
//   symbol, bid, ask, spread, digits,
//   pipSize, pipValue, tickSize, tickValue,
//   lotSize,          // 100000 (units per 1 lot)
//   minVolume,        // 1000 (0.01 lots)
//   maxVolume,        // 100000000
//   volumeStep,       // 1000
//   swapLong,         // -0.85
//   swapShort,        // 0.27
//   commission,       // 30 (per lot)
//   isTradingEnabled, // true
//   unrealizedNetProfit,
//   unrealizedGrossProfit
// }
```

#### `getBars(symbol, timeframe, count)`
Get OHLCV candle data for a single timeframe. The cBot automatically loads historical data if needed.

```js
// Last 120 daily candles (~6 months)
await bridge.getBars('EURUSD', 'Daily', 120)
// { symbol, timeframe, count: 120, bars: [
//   { openTime: '2026-01-25T22:00:00Z', open: 1.186, high: 1.190, low: 1.183, close: 1.187, volume: 111621 },
//   ...
// ]}

// Last 200 4-hour candles
await bridge.getBars('EURUSD', 'Hour4', 200)
```

**Available timeframes:**
```
Minute   Minute2  Minute3  Minute5  Minute10
Minute15 Minute30 Minute45
Hour     Hour2    Hour3    Hour4    Hour6    Hour8    Hour12
Daily    Day2     Day3     Weekly   Monthly
```

#### `getMultiTimeframeBars(symbol, timeframes)`
Get OHLCV data for multiple timeframes in a single request. Reduces round-trips when the agent needs both intraday and long-term data.

```js
await bridge.getMultiTimeframeBars('EURUSD', {
    Daily: 120,     // 6 months of daily candles
    Hour4: 200,     // ~33 days of 4h candles
    Minute15: 100   // ~25 hours of 15m candles
})
// { symbol, data: {
//   Daily: [ { openTime, open, high, low, close, volume }, ... ],
//   Hour4: [ ... ],
//   Minute15: [ ... ]
// }}
```

### Account & Positions

#### `ping()`
Connectivity check.

```js
await bridge.ping()
// { status: 'ok', timestamp: '2026-02-07T21:30:04Z' }
```

#### `getAccountInfo()`
Get account balance, equity, margin, and broker info.

```js
await bridge.getAccountInfo()
// {
//   balance: 19.62,
//   equity: 19.36,
//   freeMargin: 17.0,
//   usedMargin: 2.36,
//   unrealizedPnL: -0.26,
//   marginLevel: 821.61,
//   currency: 'USD',
//   broker: 'fpmarketsstl',
//   accountNumber: '2088766',
//   openPositionCount: 1
// }
```

#### `getPositions()`
Get all open positions with full details.

```js
await bridge.getPositions()
// { positions: [{
//   positionId: '61028556',
//   symbol: 'EURUSD',
//   side: 'Sell',
//   lots: 0.01,
//   volumeInUnits: 1000,
//   entryPrice: 1.18143,
//   currentPrice: 1.18168,
//   stopLoss: null,
//   takeProfit: null,
//   grossProfit: -0.25,
//   netProfit: -0.23,
//   commission: -0.03,
//   swap: 0.05,
//   comment: '',
//   openTime: '2026-02-06T21:48:23Z'
// }]}
```

#### `getHistory(count)`
Get last N closed trades (default 50).

```js
await bridge.getHistory(10)
// { history: [{
//   positionId, symbol, side, lots,
//   openPrice, closePrice, openTime, closeTime,
//   netProfit, commission, swap, comment
// }, ...]}
```

### Trade Execution

#### `openPosition({ symbol, side, volume, stopLoss, takeProfit, comment })`
Open a market order. Volume is in units (1000 = 0.01 lots for forex). The cBot validates the symbol, normalizes volume, and enforces max position/volume limits.

```js
await bridge.openPosition({
    symbol: 'EURUSD',
    side: 'Buy',           // 'Buy' or 'Sell'
    volume: 1000,           // in units (1000 = 0.01 lots)
    stopLoss: 1.1750,       // price (optional)
    takeProfit: 1.1900,     // price (optional)
    comment: 'thesis-file'  // optional, used to link to thesis
})
// { positionId: '61028600', entryPrice: 1.18152, volumeInUnits: 1000, lots: 0.01 }
```

#### `modifyPosition(positionId, { stopLoss, takeProfit })`
Modify SL/TP on an existing position.

```js
await bridge.modifyPosition(61028556, { stopLoss: 1.1850, takeProfit: 1.1750 })
// { positionId: '61028556', stopLoss: 1.185, takeProfit: 1.175 }
```

#### `partialClose(positionId, volumeToClose)`
Partially close a position. Volume must be less than total position volume.

```js
await bridge.partialClose(61028556, 500)
// { positionId: '61028556', remainingVolume: 500, closedVolume: 500 }
```

#### `closePosition(positionId)`
Fully close a position.

```js
await bridge.closePosition(61028556)
// { positionId: '61028556', closePrice: 1.18152, netProfit: -0.23 }
```

#### `closeAllPositions()`
Close every open position on the account.

```js
await bridge.closeAllPositions()
// { closedCount: 3, failedCount: 0 }
```

## Safety Guards (cBot)

The cBot enforces these limits on trade execution:

- **Max Positions** - Configurable limit (default 20). `openPosition` is rejected when at capacity.
- **Max Volume Per Trade** - Configurable limit (default 100,000 units). Orders exceeding this are rejected.
- **Volume Normalization** - All volumes are normalized to the symbol's step size (rounded down).
- **Minimum Volume Check** - Orders below the symbol's minimum volume are rejected.
- **Symbol Validation** - All symbol names are verified before any operation.

## Timeouts

Each action has a timeout configured in the bridge client. If the cBot doesn't respond in time, the promise rejects with a timeout error.

```
ping                    3s
getPrice                3s
getAccountInfo          5s
getPositions            5s
getHistory              5s
getSymbolInfo           5s
openPosition           10s
modifyPosition         10s
partialClose           10s
closePosition          10s
closeAllPositions      20s
getBars                15s
getMultiTimeframeBars  30s
```

## File Structure

```
OpenClaw/
  bridge/
    package.json
    src/
      index.js          # OpenClawBridge - high-level async API
      zmq-client.js     # TradingBridgeClient - DEALER socket, request correlation
      protocol.js       # Action constants, message serialization
  skill/
    package.json
    src/
      index.js              # Entry point, config, startup
      trading-agent.js      # TradingAgent - orchestrates trades with thesis linkage
      thesis-manager.js     # ThesisManager - markdown thesis CRUD
      fundamental-checker.js # FundamentalChecker - periodic news validation
    theses/                  # Trade thesis markdown files stored here

HeronCopier/cTrader/Heron Copier/AI Agent Bridge/
  AI Agent Bridge.sln
  AI Agent Bridge/
    AI Agent Bridge.cs       # cBot source - ROUTER socket, all action handlers
    AI Agent Bridge.csproj   # .NET 6.0, cTrader.Automate, NetMQ
```
