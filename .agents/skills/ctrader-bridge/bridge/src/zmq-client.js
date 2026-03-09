'use strict';

const zmq = require('zeromq');
const { v4: uuidv4 } = require('uuid');
const { buildRequest, parseResponse } = require('./protocol');

class TradingBridgeClient {
    constructor(address) {
        this.address = address;
        this.socket = null;
        this.connected = false;
        this.pendingRequests = new Map();
        this._receiveLoopRunning = false;
    }

    async connect() {
        if (this.connected) return;

        this.socket = new zmq.Dealer();
        this.socket.linger = 0;
        await this.socket.connect(this.address);
        this.connected = true;

        this._startReceiveLoop();
    }

    async disconnect() {
        this.connected = false;
        this._receiveLoopRunning = false;

        // Reject all pending requests
        for (const [reqId, pending] of this.pendingRequests) {
            clearTimeout(pending.timer);
            pending.reject(new Error('Client disconnected'));
        }
        this.pendingRequests.clear();

        if (this.socket) {
            this.socket.close();
            this.socket = null;
        }
    }

    async send(action, params = {}, timeoutMs = 5000) {
        if (!this.connected || !this.socket) {
            throw new Error('Not connected');
        }

        const requestId = uuidv4();
        const message = buildRequest(action, params, requestId);

        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pendingRequests.delete(requestId);
                reject(new Error(`Request timed out after ${timeoutMs}ms: ${action} (${requestId})`));
            }, timeoutMs);

            this.pendingRequests.set(requestId, { resolve, reject, timer, action });

            this.socket.send(message).catch(err => {
                clearTimeout(timer);
                this.pendingRequests.delete(requestId);
                reject(err);
            });
        });
    }

    _startReceiveLoop() {
        if (this._receiveLoopRunning) return;
        this._receiveLoopRunning = true;

        (async () => {
            try {
                for await (const [msg] of this.socket) {
                    if (!this._receiveLoopRunning) break;

                    try {
                        const response = parseResponse(msg.toString());
                        const pending = this.pendingRequests.get(response.requestId);
                        if (pending) {
                            clearTimeout(pending.timer);
                            this.pendingRequests.delete(response.requestId);

                            if (response.success) {
                                pending.resolve(response.data);
                            } else {
                                pending.reject(new Error(response.error || 'Request failed'));
                            }
                        }
                    } catch (parseErr) {
                        // Ignore malformed messages
                    }
                }
            } catch (err) {
                if (this._receiveLoopRunning) {
                    // Unexpected error in receive loop
                    this._receiveLoopRunning = false;
                }
            }
        })();
    }
}

module.exports = { TradingBridgeClient };
