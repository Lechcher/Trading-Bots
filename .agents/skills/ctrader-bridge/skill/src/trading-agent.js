'use strict';

const { OpenClawBridge } = require('openclaw-bridge');
const { ThesisManager } = require('./thesis-manager');
const { FundamentalChecker } = require('./fundamental-checker');

class TradingAgent {
    constructor({ bridgeAddress, thesesDir, checkIntervalMs } = {}) {
        this.bridge = new OpenClawBridge(bridgeAddress || 'tcp://144.76.7.79:51128');
        this.thesisManager = new ThesisManager(thesesDir);
        this.fundamentalChecker = new FundamentalChecker(checkIntervalMs);
    }

    async start() {
        await this.bridge.connect();

        // Verify connectivity
        const ping = await this.bridge.ping();
        console.log('[TradingAgent] Connected to AI Agent Bridge:', ping.status);

        // Start periodic fundamental checking
        this.fundamentalChecker.startPeriodicCheck(
            this.bridge,
            this.thesisManager,
            (thesis, positions, validation) => this.handleThesisInvalidation(thesis, positions, validation)
        );

        console.log('[TradingAgent] Agent started');
    }

    async stop() {
        this.fundamentalChecker.stopPeriodicCheck();
        await this.bridge.disconnect();
        console.log('[TradingAgent] Agent stopped');
    }

    async openTradeWithThesis({ symbol, side, volume, stopLoss, takeProfit, reasoning, invalidationConditions, fundamentalAnchors }) {
        // Create thesis first
        const thesis = this.thesisManager.createThesis({
            symbol,
            direction: side,
            reasoning,
            invalidationConditions,
            fundamentalAnchors,
        });

        // Open position with thesis filename as comment for linkage
        const position = await this.bridge.openPosition({
            symbol,
            side,
            volume,
            stopLoss,
            takeProfit,
            comment: thesis.filename,
        });

        // Update thesis with position info
        this.thesisManager.updateThesisStatus(
            thesis.filename,
            'ACTIVE',
            `Position opened: ${position.positionId} @ ${position.entryPrice}`
        );

        console.log(`[TradingAgent] Trade opened: ${symbol} ${side} ${position.lots} lots, thesis: ${thesis.filename}`);

        return { position, thesis };
    }

    async handleThesisInvalidation(thesis, positions, validation) {
        console.log(`[TradingAgent] Thesis invalidated: ${thesis.filename}`);
        console.log(`[TradingAgent] Reasons: ${validation.reasons.join('; ')}`);

        // Close all linked positions
        let closedCount = 0;
        let failedCount = 0;

        for (const pos of positions) {
            try {
                await this.bridge.closePosition(parseInt(pos.positionId));
                closedCount++;
                console.log(`[TradingAgent] Closed position ${pos.positionId} (${pos.symbol} ${pos.side})`);
            } catch (err) {
                failedCount++;
                console.error(`[TradingAgent] Failed to close position ${pos.positionId}: ${err.message}`);
            }
        }

        // Update thesis status
        this.thesisManager.updateThesisStatus(
            thesis.filename,
            'CLOSED',
            `Thesis invalidated. Closed ${closedCount} positions, ${failedCount} failed. Reasons: ${validation.reasons.join('; ')}`
        );

        return { closedCount, failedCount };
    }
}

module.exports = { TradingAgent };
