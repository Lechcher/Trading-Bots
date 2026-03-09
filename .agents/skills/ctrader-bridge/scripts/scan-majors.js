#!/usr/bin/env node
'use strict';

/**
 * Major Pairs + Gold Scanner
 * Runs every 5 minutes on weekdays
 * 
 * Checks: EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD, XAUUSD
 * 
 * Logic:
 * 1. Fetch current prices
 * 2. Fetch H4 bars for key levels
 * 3. Detect significant conditions (breakouts, level tests, momentum)
 * 4. Output findings for the AI to analyze
 */

const path = require('path');
const fs = require('fs');
const { OpenClawBridge } = require('../bridge/src/index.js');

const MAJORS = ['EURUSD', 'GBPUSD', 'USDJPY', 'USDCHF', 'AUDUSD', 'USDCAD', 'NZDUSD', 'XAUUSD'];
const STATE_FILE = path.join(__dirname, '..', 'data', 'majors-state.json');

const bridge = new OpenClawBridge();

function ensureDataDir() {
  const dataDir = path.join(__dirname, '..', 'data');
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
}

function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    }
  } catch (e) {}
  return { lastPrices: {}, keyLevels: {}, lastScan: null };
}

function saveState(state) {
  ensureDataDir();
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

function calculateKeyLevels(bars) {
  if (!bars || bars.length < 20) return null;
  
  // Last 20 bars for recent S/R
  const recent = bars.slice(-20);
  const highs = recent.map(b => b.high);
  const lows = recent.map(b => b.low);
  const closes = recent.map(b => b.close);
  
  // Simple key levels: recent high, recent low, and round numbers
  const recentHigh = Math.max(...highs);
  const recentLow = Math.min(...lows);
  const currentPrice = closes[closes.length - 1];
  
  // Daily range
  const lastBar = recent[recent.length - 1];
  const prevBar = recent[recent.length - 2];
  
  return {
    recentHigh,
    recentLow,
    currentClose: currentPrice,
    prevClose: prevBar ? prevBar.close : null,
    prevHigh: prevBar ? prevBar.high : null,
    prevLow: prevBar ? prevBar.low : null
  };
}

function detectSignals(symbol, price, levels, prevPrice) {
  const signals = [];
  const { bid, ask, pipSize } = price;
  const mid = (bid + ask) / 2;
  
  if (!levels) return signals;
  
  const threshold = pipSize * 10; // 10 pips threshold
  
  // Breakout above recent high
  if (mid > levels.recentHigh && levels.prevClose <= levels.recentHigh) {
    signals.push({
      type: 'BREAKOUT_HIGH',
      message: `${symbol} breaking above recent H4 high ${levels.recentHigh.toFixed(5)}`
    });
  }
  
  // Breakdown below recent low
  if (mid < levels.recentLow && levels.prevClose >= levels.recentLow) {
    signals.push({
      type: 'BREAKDOWN_LOW',
      message: `${symbol} breaking below recent H4 low ${levels.recentLow.toFixed(5)}`
    });
  }
  
  // Testing key level (within threshold)
  if (Math.abs(mid - levels.recentHigh) < threshold) {
    signals.push({
      type: 'TESTING_RESISTANCE',
      message: `${symbol} testing resistance at ${levels.recentHigh.toFixed(5)}`
    });
  }
  
  if (Math.abs(mid - levels.recentLow) < threshold) {
    signals.push({
      type: 'TESTING_SUPPORT',
      message: `${symbol} testing support at ${levels.recentLow.toFixed(5)}`
    });
  }
  
  // Significant move from last scan
  if (prevPrice) {
    const movePips = Math.abs(mid - prevPrice) / pipSize;
    if (movePips > 20) {
      signals.push({
        type: 'SIGNIFICANT_MOVE',
        message: `${symbol} moved ${movePips.toFixed(1)} pips since last scan`
      });
    }
  }
  
  return signals;
}

async function scan() {
  const state = loadState();
  const results = {
    timestamp: new Date().toISOString(),
    symbols: {},
    signals: [],
    errors: []
  };
  
  try {
    await bridge.connect();
    
    // Fetch all prices at once
    const priceData = await bridge.getPrice(MAJORS);
    const prices = priceData.prices || [priceData]; // Handle single vs array
    
    for (const price of prices) {
      const symbol = price.symbol;
      results.symbols[symbol] = {
        bid: price.bid,
        ask: price.ask,
        spread: price.spread,
        mid: price.mid
      };
      
      // Fetch H4 bars for key levels (only every 30 min to save resources)
      let levels = state.keyLevels[symbol];
      const now = Date.now();
      const levelAge = state.levelUpdates?.[symbol] || 0;
      
      if (!levels || (now - levelAge) > 30 * 60 * 1000) {
        try {
          const barsData = await bridge.getBars(symbol, 'Hour4', 30);
          levels = calculateKeyLevels(barsData.bars);
          state.keyLevels[symbol] = levels;
          state.levelUpdates = state.levelUpdates || {};
          state.levelUpdates[symbol] = now;
        } catch (e) {
          results.errors.push(`Failed to get bars for ${symbol}: ${e.message}`);
        }
      }
      
      // Detect signals
      const prevPrice = state.lastPrices[symbol];
      const signals = detectSignals(symbol, price, levels, prevPrice);
      
      if (signals.length > 0) {
        results.signals.push(...signals);
      }
      
      // Update last price
      state.lastPrices[symbol] = price.mid;
    }
    
    await bridge.disconnect();
    
  } catch (err) {
    results.errors.push(`Bridge error: ${err.message}`);
  }
  
  state.lastScan = results.timestamp;
  saveState(state);
  
  // Output results
  console.log(JSON.stringify(results, null, 2));
  
  // Return non-zero if we have signals (for cron to know something interesting happened)
  if (results.signals.length > 0) {
    process.exit(0); // Signals found
  } else {
    process.exit(0); // No signals, but successful
  }
}

scan().catch(err => {
  console.error('Scan failed:', err.message);
  process.exit(1);
});
