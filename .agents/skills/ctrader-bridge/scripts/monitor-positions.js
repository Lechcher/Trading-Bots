#!/usr/bin/env node
'use strict';

/**
 * Position Monitor
 * Runs every 30 minutes on weekdays
 * 
 * Checks all open positions:
 * 1. Current P&L
 * 2. Thesis validity (looks up thesis file from comment)
 * 3. Suggests actions (move SL to BE, close, etc.)
 */

const path = require('path');
const fs = require('fs');
const { OpenClawBridge } = require('../bridge/src/index.js');

const THESES_DIR = path.join(__dirname, '..', 'skill', 'theses');
const bridge = new OpenClawBridge();

function loadThesis(filename) {
  if (!filename) return null;
  
  const filepath = path.join(THESES_DIR, filename);
  if (!fs.existsSync(filepath)) return null;
  
  try {
    const content = fs.readFileSync(filepath, 'utf8');
    
    // Parse key fields
    const statusMatch = content.match(/## Status: (\w+)/);
    const slMatch = content.match(/Stop-loss: ([\d.]+)/);
    const tpMatch = content.match(/Take-profit: ([\d.]+)/);
    const entryMatch = content.match(/Entry price: ([\d.]+)/);
    const riskMatch = content.match(/Risk: \$([\d.]+)/);
    
    // Extract invalidation conditions
    const invalidationMatch = content.match(/## Invalidation Conditions\n([\s\S]*?)(?=\n## )/);
    const invalidationConditions = [];
    if (invalidationMatch) {
      const lines = invalidationMatch[1].split('\n').filter(l => l.startsWith('- '));
      invalidationConditions.push(...lines.map(l => l.replace('- ', '')));
    }
    
    return {
      filename,
      status: statusMatch ? statusMatch[1] : 'UNKNOWN',
      entryPrice: entryMatch ? parseFloat(entryMatch[1]) : null,
      stopLoss: slMatch ? parseFloat(slMatch[1]) : null,
      takeProfit: tpMatch ? parseFloat(tpMatch[1]) : null,
      riskAmount: riskMatch ? parseFloat(riskMatch[1]) : null,
      invalidationConditions,
      raw: content
    };
  } catch (e) {
    return null;
  }
}

function analyzePosition(position, thesis, currentPrice) {
  const analysis = {
    positionId: position.positionId,
    symbol: position.symbol,
    side: position.side,
    lots: position.lots,
    entryPrice: position.entryPrice,
    currentPrice: currentPrice?.mid || position.currentPrice,
    netProfit: position.netProfit,
    grossProfit: position.grossProfit,
    stopLoss: position.stopLoss,
    takeProfit: position.takeProfit,
    hasThesis: !!thesis,
    thesisFile: position.comment || null,
    suggestions: [],
    warnings: []
  };
  
  const pipSize = currentPrice?.pipSize || 0.0001;
  const isJpy = position.symbol.includes('JPY') || position.symbol.includes('XAU');
  const effectivePipSize = isJpy ? (position.symbol.includes('XAU') ? 0.01 : 0.01) : pipSize;
  
  const entryPrice = position.entryPrice;
  const current = currentPrice?.mid || position.currentPrice;
  const isBuy = position.side === 'Buy';
  
  // Calculate pips in profit/loss
  const priceDiff = isBuy ? (current - entryPrice) : (entryPrice - current);
  const pipsProfit = priceDiff / effectivePipSize;
  
  analysis.pipsProfit = pipsProfit;
  
  // No SL warning
  if (!position.stopLoss) {
    analysis.warnings.push('NO STOP-LOSS SET - High risk!');
  }
  
  // No TP warning
  if (!position.takeProfit) {
    analysis.warnings.push('No take-profit set');
  }
  
  // Move SL to breakeven suggestion
  if (position.stopLoss && pipsProfit > 30) {
    const slPips = isBuy 
      ? (entryPrice - position.stopLoss) / effectivePipSize
      : (position.stopLoss - entryPrice) / effectivePipSize;
    
    if (slPips > 5) { // SL is still below entry
      analysis.suggestions.push(`Consider moving SL to breakeven (${entryPrice.toFixed(5)}) - currently ${pipsProfit.toFixed(1)} pips in profit`);
    }
  }
  
  // Large profit - consider partial close
  if (pipsProfit > 50 && position.lots >= 0.02) {
    analysis.suggestions.push(`Consider taking partial profit - ${pipsProfit.toFixed(1)} pips in profit`);
  }
  
  // Large loss warning
  if (pipsProfit < -30) {
    analysis.warnings.push(`Position ${Math.abs(pipsProfit).toFixed(1)} pips in loss`);
  }
  
  // No thesis warning
  if (!thesis) {
    analysis.warnings.push('No thesis file found - cannot validate trade rationale');
  } else if (thesis.status !== 'ACTIVE') {
    analysis.warnings.push(`Thesis status is ${thesis.status}, not ACTIVE`);
  }
  
  return analysis;
}

async function monitor() {
  const results = {
    timestamp: new Date().toISOString(),
    accountInfo: null,
    positions: [],
    summary: {
      totalPositions: 0,
      totalNetPnL: 0,
      positionsWithWarnings: 0,
      positionsNeedingAction: 0
    }
  };
  
  try {
    await bridge.connect();
    
    // Get account info
    const account = await bridge.getAccountInfo();
    results.accountInfo = {
      balance: account.balance,
      equity: account.equity,
      unrealizedPnL: account.unrealizedPnL,
      openPositionCount: account.openPositionCount
    };
    
    // Get positions
    const posData = await bridge.getPositions();
    const positions = posData.positions || [];
    
    results.summary.totalPositions = positions.length;
    
    if (positions.length === 0) {
      results.summary.message = 'No open positions';
      await bridge.disconnect();
      console.log(JSON.stringify(results, null, 2));
      return;
    }
    
    // Analyze each position
    for (const pos of positions) {
      // Get current price
      let currentPrice = null;
      try {
        currentPrice = await bridge.getPrice(pos.symbol);
      } catch (e) {
        // Use position's current price as fallback
      }
      
      // Load thesis
      const thesis = loadThesis(pos.comment);
      
      // Analyze
      const analysis = analyzePosition(pos, thesis, currentPrice);
      results.positions.push(analysis);
      
      results.summary.totalNetPnL += pos.netProfit;
      
      if (analysis.warnings.length > 0) {
        results.summary.positionsWithWarnings++;
      }
      if (analysis.suggestions.length > 0) {
        results.summary.positionsNeedingAction++;
      }
    }
    
    await bridge.disconnect();
    
  } catch (err) {
    results.error = err.message;
  }
  
  console.log(JSON.stringify(results, null, 2));
}

monitor().catch(err => {
  console.error('Monitor failed:', err.message);
  process.exit(1);
});
