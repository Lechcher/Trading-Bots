#!/usr/bin/env node
'use strict';

const path = require('path');
const { OpenClawBridge } = require('../bridge/src/index.js');

const bridge = new OpenClawBridge();

const commands = {
  async ping() {
    await bridge.connect();
    const result = await bridge.ping();
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async account() {
    await bridge.connect();
    const result = await bridge.getAccountInfo();
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async positions() {
    await bridge.connect();
    const result = await bridge.getPositions();
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async history(count = 50) {
    await bridge.connect();
    const result = await bridge.getHistory(parseInt(count));
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async symbol(sym) {
    if (!sym) {
      console.error('Usage: trade.js symbol <SYMBOL>');
      process.exit(1);
    }
    await bridge.connect();
    const result = await bridge.getSymbolInfo(sym);
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async price(symbols) {
    if (!symbols) {
      console.error('Usage: trade.js price <SYMBOL> or trade.js price EURUSD,GBPUSD');
      process.exit(1);
    }
    await bridge.connect();
    // Support comma-separated symbols
    const symbolArg = symbols.includes(',') ? symbols.split(',') : symbols;
    const result = await bridge.getPrice(symbolArg);
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async bars(symbol, timeframe = 'Hour4', count = 200) {
    if (!symbol) {
      console.error('Usage: trade.js bars <SYMBOL> [timeframe] [count]');
      console.error('Timeframes: Minute, Minute5, Minute15, Minute30, Hour, Hour4, Daily, Weekly');
      process.exit(1);
    }
    await bridge.connect();
    const result = await bridge.getBars(symbol, timeframe, parseInt(count));
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async mtf(symbol) {
    if (!symbol) {
      console.error('Usage: trade.js mtf <SYMBOL>');
      process.exit(1);
    }
    await bridge.connect();
    const result = await bridge.getMultiTimeframeBars(symbol, {
      Daily: 120,
      Hour4: 200,
      Minute15: 100
    });
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async open(...args) {
    // Parse arguments - support both positional and flag-based
    // Positional: <symbol> <buy|sell> <volume> [sl] [tp] [comment]
    // Flags: --sl <price> --tp <price> --comment <text>
    let symbol, side, volume, sl, tp, comment;
    
    const positionalArgs = [];
    for (let i = 0; i < args.length; i++) {
      const arg = args[i];
      if (arg === '--sl' && args[i + 1]) {
        sl = args[++i];
      } else if (arg === '--tp' && args[i + 1]) {
        tp = args[++i];
      } else if (arg === '--comment' && args[i + 1]) {
        comment = args[++i];
      } else if (!arg.startsWith('--')) {
        positionalArgs.push(arg);
      }
    }
    
    // Assign positional args
    [symbol, side, volume] = positionalArgs.slice(0, 3);
    // If sl/tp/comment not set via flags, try positional
    if (!sl && positionalArgs[3]) sl = positionalArgs[3];
    if (!tp && positionalArgs[4]) tp = positionalArgs[4];
    if (!comment && positionalArgs[5]) comment = positionalArgs[5];
    
    if (!symbol || !side || !volume) {
      console.error('Usage: trade.js open <symbol> <buy|sell> <volume> [--sl <price>] [--tp <price>] [--comment <text>]');
      console.error('       or: trade.js open <symbol> <buy|sell> <volume> <sl> <tp> [comment]');
      console.error('Volume is in UNITS: 1000 = 0.01 lots, 10000 = 0.1 lots, 100000 = 1 lot');
      process.exit(1);
    }
    await bridge.connect();
    const params = {
      symbol,
      side: side.charAt(0).toUpperCase() + side.slice(1).toLowerCase(),
      volume: parseFloat(volume),
    };
    if (sl) params.stopLoss = parseFloat(sl);
    if (tp) params.takeProfit = parseFloat(tp);
    if (comment) params.comment = comment;
    
    const result = await bridge.openPosition(params);
    
    // Verify SL/TP was set correctly
    if (result.positionId && (sl || tp)) {
      const positions = await bridge.getPositions();
      const openedPos = positions.positions?.find(p => p.positionId == result.positionId);
      if (openedPos) {
        const warnings = [];
        if (sl && !openedPos.stopLoss) warnings.push('SL NOT SET!');
        if (tp && !openedPos.takeProfit) warnings.push('TP NOT SET!');
        if (sl && openedPos.stopLoss && Math.abs(openedPos.stopLoss - parseFloat(sl)) > 0.0001) {
          warnings.push(`SL mismatch: requested ${sl}, got ${openedPos.stopLoss}`);
        }
        if (tp && openedPos.takeProfit && Math.abs(openedPos.takeProfit - parseFloat(tp)) > 0.0001) {
          warnings.push(`TP mismatch: requested ${tp}, got ${openedPos.takeProfit}`);
        }
        if (warnings.length > 0) {
          result.warnings = warnings;
          console.error('⚠️ SL/TP VERIFICATION FAILED:', warnings.join(', '));
        } else {
          result.verified = { stopLoss: openedPos.stopLoss, takeProfit: openedPos.takeProfit };
        }
      }
    }
    
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async close(positionId) {
    if (!positionId) {
      console.error('Usage: trade.js close <positionId>');
      process.exit(1);
    }
    await bridge.connect();
    
    // SAFETY: Verify position exists and show details before closing
    const positions = await bridge.getPositions();
    const targetPos = positions.positions?.find(p => p.positionId == positionId);
    
    if (!targetPos) {
      console.error(`Error: Position not found: ${positionId}`);
      console.error('\nOpen positions:');
      positions.positions?.forEach(p => {
        console.error(`  ${p.positionId}: ${p.symbol} ${p.side} ${p.lots}L @ ${p.entryPrice} (P&L: ${p.netProfit?.toFixed(2)})`);
      });
      process.exit(1);
    }
    
    // Show what we're about to close
    console.error(`Closing: ${targetPos.symbol} ${targetPos.side} ${targetPos.lots}L @ ${targetPos.entryPrice}`);
    console.error(`  Current P&L: ${targetPos.netProfit?.toFixed(2)}`);
    
    const result = await bridge.closePosition(parseInt(positionId));
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async closeall() {
    await bridge.connect();
    const result = await bridge.closeAllPositions();
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async modify(...args) {
    // Parse arguments - support both positional and flag-based
    // Positional: <positionId> [sl] [tp]
    // Flags: --sl <price> --tp <price>
    let positionId, sl, tp;
    
    const positionalArgs = [];
    for (let i = 0; i < args.length; i++) {
      const arg = args[i];
      if (arg === '--sl' && args[i + 1]) {
        sl = args[++i];
      } else if (arg === '--tp' && args[i + 1]) {
        tp = args[++i];
      } else if (!arg.startsWith('--')) {
        positionalArgs.push(arg);
      }
    }
    
    // First positional arg is positionId
    positionId = positionalArgs[0];
    // If sl/tp not set via flags, try positional
    if (!sl && positionalArgs[1]) sl = positionalArgs[1];
    if (!tp && positionalArgs[2]) tp = positionalArgs[2];
    
    if (!positionId) {
      console.error('Usage: trade.js modify <positionId> [--sl <price>] [--tp <price>]');
      console.error('       or: trade.js modify <positionId> <sl> <tp>');
      process.exit(1);
    }
    
    if (!sl && !tp) {
      console.error('Error: Must specify at least --sl or --tp');
      process.exit(1);
    }
    
    await bridge.connect();
    
    // SAFETY: Verify position exists and show details before modifying
    const positions = await bridge.getPositions();
    const targetPos = positions.positions?.find(p => p.positionId == positionId);
    
    if (!targetPos) {
      console.error(`Error: Position not found: ${positionId}`);
      console.error('\nOpen positions:');
      positions.positions?.forEach(p => {
        console.error(`  ${p.positionId}: ${p.symbol} ${p.side} ${p.lots}L @ ${p.entryPrice}`);
      });
      process.exit(1);
    }
    
    // Show what we're about to modify
    console.error(`Modifying: ${targetPos.symbol} ${targetPos.side} ${targetPos.lots}L (ID: ${positionId})`);
    console.error(`  Current SL: ${targetPos.stopLoss || 'none'} → ${sl ? `New: ${sl}` : 'unchanged'}`);
    console.error(`  Current TP: ${targetPos.takeProfit || 'none'} → ${tp ? `New: ${tp}` : 'unchanged'}`);
    
    const params = {};
    if (sl) params.stopLoss = parseFloat(sl);
    if (tp) params.takeProfit = parseFloat(tp);
    
    const result = await bridge.modifyPosition(parseInt(positionId), params);
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },

  async partial(positionId, volume) {
    if (!positionId || !volume) {
      console.error('Usage: trade.js partial <positionId> <volumeToClose>');
      process.exit(1);
    }
    await bridge.connect();
    const result = await bridge.partialClose(parseInt(positionId), parseFloat(volume));
    console.log(JSON.stringify(result, null, 2));
    await bridge.disconnect();
  },
};

async function main() {
  const [,, cmd, ...args] = process.argv;
  
  if (!cmd || !commands[cmd]) {
    console.log('cTrader Bridge CLI');
    console.log('');
    console.log('Connection & Account:');
    console.log('  ping                              - Test connection');
    console.log('  account                           - Get account info');
    console.log('  positions                         - List open positions');
    console.log('  history [count]                   - Get trade history');
    console.log('');
    console.log('Market Data:');
    console.log('  price <symbol>                    - Get bid/ask price');
    console.log('  price EURUSD,GBPUSD               - Multiple symbols');
    console.log('  symbol <symbol>                   - Get symbol specifications');
    console.log('  bars <symbol> [timeframe] [count] - Get OHLCV candles');
    console.log('  mtf <symbol>                      - Multi-timeframe bars (Daily/H4/M15)');
    console.log('');
    console.log('Trade Execution:');
    console.log('  open <symbol> <buy|sell> <vol> [--sl <p>] [--tp <p>] [--comment <t>]');
    console.log('  close <positionId>                - Close position (shows details first)');
    console.log('  closeall                          - Close all positions');
    console.log('  modify <positionId> [--sl <p>] [--tp <p>] - Modify SL/TP (verifies ID)');
    console.log('  partial <positionId> <volume>     - Partial close');
    console.log('');
    console.log('Volume is in UNITS: 1000 = 0.01 lots, 10000 = 0.1 lots, 100000 = 1 lot');
    process.exit(1);
  }

  try {
    await commands[cmd](...args);
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(1);
  }
}

main();
