'use strict';

const path = require('path');
const { TradingAgent } = require('./trading-agent');

const config = {
    bridgeAddress: process.env.BRIDGE_ADDRESS || 'tcp://144.76.7.79:51128',
    thesesDir: process.env.THESES_DIR || path.join(__dirname, '..', 'theses'),
    checkIntervalMs: parseInt(process.env.CHECK_INTERVAL_MS || '1800000', 10), // 30 minutes
};

const agent = new TradingAgent(config);

async function main() {
    console.log('[OpenClaw] Starting with config:', {
        bridgeAddress: config.bridgeAddress,
        thesesDir: config.thesesDir,
        checkIntervalMs: config.checkIntervalMs,
    });

    await agent.start();

    // Graceful shutdown
    const shutdown = async (signal) => {
        console.log(`[OpenClaw] Received ${signal}, shutting down...`);
        await agent.stop();
        process.exit(0);
    };

    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch(err => {
    console.error('[OpenClaw] Fatal error:', err.message);
    process.exit(1);
});

module.exports = { agent };
