'use strict';

const ACTIONS = {
    PING: 'ping',
    ACCOUNT_INFO: 'accountInfo',
    POSITIONS: 'positions',
    HISTORY: 'history',
    SYMBOL_INFO: 'symbolInfo',
    OPEN_POSITION: 'openPosition',
    MODIFY_POSITION: 'modifyPosition',
    PARTIAL_CLOSE: 'partialClose',
    CLOSE_POSITION: 'closePosition',
    CLOSE_ALL_POSITIONS: 'closeAllPositions',
    GET_PRICE: 'getPrice',
    GET_BARS: 'getBars',
    GET_MULTI_TIMEFRAME_BARS: 'getMultiTimeframeBars',
};

const RESPONSE_SUFFIX = 'Response';

function buildRequest(action, params, requestId) {
    const request = { action, requestId };
    if (params && Object.keys(params).length > 0) {
        request.params = params;
    }
    return JSON.stringify(request);
}

function parseResponse(raw) {
    const data = JSON.parse(raw);
    if (typeof data.action !== 'string' || typeof data.requestId !== 'string') {
        throw new Error('Invalid response: missing action or requestId');
    }
    return data;
}

function isValidAction(action) {
    return Object.values(ACTIONS).includes(action);
}

module.exports = {
    ACTIONS,
    RESPONSE_SUFFIX,
    buildRequest,
    parseResponse,
    isValidAction,
};
