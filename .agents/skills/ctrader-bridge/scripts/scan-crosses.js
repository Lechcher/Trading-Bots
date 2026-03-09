#!/usr/bin/env node
'use strict';

/**
 * Cross Pairs Scanner
 * Runs every 30 minutes on weekdays
 * 
 * Checks: EURJPY, GBPJPY, EURGBP, AUDNZD, AUDJPY, NZDJPY, EURCHF, GBPCHF, CADJPY, CHFJPY
 */

const path = require('path');
const fs = require('fs');
const { OpenClawBridge } = require('../bridge/src/index.js');

const CROSSES = [
  'EURJPY', 'GBPJPY', 'EURGBP', 'AUDNZD', 'AUDJPY', 
  'NZDJPY', 'EURCHF', 'GBPCHF', 'CADJPY', 'CHFJPY'
];
const STATE_FILE = path.join(__dirname, '..', 'data', 'crosses-state.json');

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
  
  const recent = bars.slice(-20);
  const highs = recent.map(b => b.high);
  const lows = recent.map(b => b.low);
  const closes = recent.map(b => b.close);
  
  const recentHigh = Math.max(...highs);
  const recentLow = Math.min(...lows);
  const currentPrice = closes[closes.length - 1];
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
  
  // Use appropriate pip threshold based on pair
  const isJpy = symbol.includes('JPY');
  const threshold = isJpy ? 0.10 : pipSize * 15; // 10 pips for JPY, 15 for others
  
  if (mid > levels.recentHigh && levels.prevClose <= levels.recentHigh) {
    signals.push({
      type: 'BREAKOUT_HIGH',
      message: `${symbol} breaking above recent H4 high ${levels.recentHigh.toFixed(isJpy ? 3 : 5)}`
    });
  }
  
  if (mid < levels.recentLow && levels.prevClose >= levels.recentLow) {
    signals.push({
      type: 'BREAKDOWN_LOW',
      message: `${symbol} breaking below recent H4 low ${levels.recentLow.toFixed(isJpy ? 3 : 5)}`
    });
  }
  
  if (Math.abs(mid - levels.recentHigh) < threshold) {
    signals.push({
      type: 'TESTING_RESISTANCE',
      message: `${symbol} testing resistance at ${levels.recentHigh.toFixed(isJpy ? 3 : 5)}`
    });
  }
  
  if (Math.abs(mid - levels.recentLow) < threshold) {
    signals.push({
      type: 'TESTING_SUPPORT',
      message: `${symbol} testing support at ${levels.recentLow.toFixed(isJpy ? 3 : 5)}`
    });
  }
  
  if (prevPrice) {
    const effectivePipSize = isJpy ? 0.01 : (pipSize || 0.0001);
    const movePips = Math.abs(mid - prevPrice) / effectivePipSize;
    if (movePips > 30) {
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
    
    const priceData = await bridge.getPrice(CROSSES);
    const prices = priceData.prices || [priceData];
    
    for (const price of prices) {
      const symbol = price.symbol;
      results.symbols[symbol] = {
        bid: price.bid,
        ask: price.ask,
        spread: price.spread,
        mid: price.mid
      };
      
      // Always fetch bars for crosses (30 min interval is reasonable)
      let levels = null;
      try {
        const barsData = await bridge.getBars(symbol, 'Hour4', 30);
        levels = calculateKeyLevels(barsData.bars);
        state.keyLevels[symbol] = levels;
      } catch (e) {
        results.errors.push(`Failed to get bars for ${symbol}: ${e.message}`);
        levels = state.keyLevels[symbol];
      }
      
      const prevPrice = state.lastPrices[symbol];
      const signals = detectSignals(symbol, price, levels, prevPrice);
      
      if (signals.length > 0) {
        results.signals.push(...signals);
      }
      
      state.lastPrices[symbol] = price.mid;
    }
    
    await bridge.disconnect();
    
  } catch (err) {
    results.errors.push(`Bridge error: ${err.message}`);
  }
  
  state.lastScan = results.timestamp;
  saveState(state);
  
  console.log(JSON.stringify(results, null, 2));
}

scan().catch(err => {
  console.error('Scan failed:', err.message);
  process.exit(1);
});
