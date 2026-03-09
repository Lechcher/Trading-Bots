'use strict';

const { TradingBridgeClient } = require('./zmq-client');
const { ACTIONS } = require('./protocol');

class OpenClawBridge {
    constructor(address = 'tcp://144.76.7.79:51128') {
        this.client = new TradingBridgeClient(address);
    }

    async connect() {
        await this.client.connect();
    }

    async disconnect() {
        await this.client.disconnect();
    }

    async ping() {
        return this.client.send(ACTIONS.PING, {}, 3000);
    }

    async getAccountInfo() {
        return this.client.send(ACTIONS.ACCOUNT_INFO);
    }

    async getPositions() {
        return this.client.send(ACTIONS.POSITIONS);
    }

    async getHistory(count = 50) {
        return this.client.send(ACTIONS.HISTORY, { count });
    }

    async getSymbolInfo(symbol) {
        return this.client.send(ACTIONS.SYMBOL_INFO, { symbol });
    }

    async openPosition({ symbol, side, volume, stopLoss, takeProfit, comment }) {
        const params = { symbol, side, volume };
        if (stopLoss != null) params.stopLoss = stopLoss;
        if (takeProfit != null) params.takeProfit = takeProfit;
        if (comment != null) params.comment = comment;
        return this.client.send(ACTIONS.OPEN_POSITION, params, 10000);
    }

    async modifyPosition(positionId, { stopLoss, takeProfit }) {
        const params = { positionId };
        if (stopLoss != null) params.stopLoss = stopLoss;
        if (takeProfit != null) params.takeProfit = takeProfit;
        return this.client.send(ACTIONS.MODIFY_POSITION, params, 10000);
    }

    async partialClose(positionId, volumeToClose) {
        return this.client.send(ACTIONS.PARTIAL_CLOSE, { positionId, volumeToClose }, 10000);
    }

    async closePosition(positionId) {
        return this.client.send(ACTIONS.CLOSE_POSITION, { positionId }, 10000);
    }

    async closeAllPositions() {
        return this.client.send(ACTIONS.CLOSE_ALL_POSITIONS, {}, 20000);
    }

    async getPrice(symbol) {
        return this.client.send(ACTIONS.GET_PRICE, { symbol }, 3000);
    }

    async getBars(symbol, timeframe = 'Hour4', count = 200) {
        return this.client.send(ACTIONS.GET_BARS, { symbol, timeframe, count }, 15000);
    }

    async getMultiTimeframeBars(symbol, timeframes = { Daily: 120, Hour4: 200, Minute15: 100 }) {
        return this.client.send(ACTIONS.GET_MULTI_TIMEFRAME_BARS, { symbol, timeframes }, 30000);
    }
}

module.exports = { OpenClawBridge, TradingBridgeClient, ACTIONS };
