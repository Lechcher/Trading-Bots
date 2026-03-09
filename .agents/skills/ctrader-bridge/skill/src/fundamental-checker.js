'use strict';

const fetch = require('node-fetch');

class FundamentalChecker {
    constructor(checkIntervalMs = 30 * 60 * 1000) {
        this.checkIntervalMs = checkIntervalMs;
        this._intervalHandle = null;
    }

    async checkFundamentals(symbol) {
        const results = [];

        // Fetch from multiple sources with individual error handling
        const sources = [
            { name: 'fxstreet', fn: () => this._fetchFxStreet(symbol) },
            { name: 'reuters', fn: () => this._fetchReuters(symbol) },
        ];

        for (const source of sources) {
            try {
                const data = await source.fn();
                if (data) {
                    results.push({ source: source.name, ...data });
                }
            } catch (err) {
                results.push({ source: source.name, error: err.message, headlines: [] });
            }
        }

        return {
            symbol,
            checkedAt: new Date().toISOString(),
            sources: results,
        };
    }

    validateThesis(thesis, currentFundamentals) {
        const reasons = [];
        let valid = true;

        if (!thesis.invalidationConditions || thesis.invalidationConditions.length === 0) {
            return { valid: true, reasons: ['No invalidation conditions to check'] };
        }

        // Collect all headlines from all sources
        const allHeadlines = [];
        for (const source of (currentFundamentals.sources || [])) {
            if (source.headlines) {
                allHeadlines.push(...source.headlines.map(h => h.toLowerCase()));
            }
        }

        if (allHeadlines.length === 0) {
            return { valid: true, reasons: ['No fundamental data available to validate against'] };
        }

        // Check each invalidation condition against headlines
        for (const condition of thesis.invalidationConditions) {
            const condLower = condition.toLowerCase();

            // Extract key terms from the condition (words longer than 3 chars)
            const keyTerms = condLower
                .split(/[\s,;.!?()]+/)
                .filter(w => w.length > 3);

            // Check if any headline matches a significant portion of key terms
            for (const headline of allHeadlines) {
                const matchCount = keyTerms.filter(term => headline.includes(term)).length;
                const matchRatio = keyTerms.length > 0 ? matchCount / keyTerms.length : 0;

                if (matchRatio >= 0.5) {
                    valid = false;
                    reasons.push(`Invalidation condition may be triggered: "${condition}" (matched headline containing relevant terms)`);
                    break;
                }
            }
        }

        if (valid) {
            reasons.push('All invalidation conditions still hold');
        }

        return { valid, reasons };
    }

    startPeriodicCheck(bridge, thesisManager, onInvalidation) {
        if (this._intervalHandle) {
            clearInterval(this._intervalHandle);
        }

        const runCheck = async () => {
            try {
                const activeTheses = thesisManager.getActiveTheses();
                if (activeTheses.length === 0) return;

                let positionsData;
                try {
                    positionsData = await bridge.getPositions();
                } catch (err) {
                    return; // Bridge not available, skip this cycle
                }

                const positions = positionsData.positions || [];

                for (const thesis of activeTheses) {
                    // Find positions linked to this thesis
                    const linkedPositions = positions.filter(
                        p => p.comment === thesis.filename
                    );

                    if (linkedPositions.length === 0) {
                        // No linked positions - thesis may have been manually closed
                        thesisManager.updateThesisStatus(thesis.filename, 'ORPHANED', 'No linked positions found');
                        continue;
                    }

                    // Fetch fundamentals for this symbol
                    const fundamentals = await this.checkFundamentals(thesis.symbol);
                    const validation = this.validateThesis(thesis, fundamentals);

                    const note = validation.valid
                        ? 'Fundamentals support thesis'
                        : 'INVALIDATED: ' + validation.reasons.join('; ');

                    thesisManager.updateThesisStatus(thesis.filename, validation.valid ? 'ACTIVE' : 'ACTIVE', note);

                    if (!validation.valid && onInvalidation) {
                        await onInvalidation(thesis, linkedPositions, validation);
                    }
                }
            } catch (err) {
                // Don't crash on check errors - log and continue
                console.error('[FundamentalChecker] Periodic check error:', err.message);
            }
        };

        // Run first check immediately
        runCheck();

        this._intervalHandle = setInterval(runCheck, this.checkIntervalMs);
    }

    stopPeriodicCheck() {
        if (this._intervalHandle) {
            clearInterval(this._intervalHandle);
            this._intervalHandle = null;
        }
    }

    async _fetchFxStreet(symbol) {
        // Map forex pairs to FXStreet search format
        const pair = symbol.replace(/[^A-Za-z]/g, '').toUpperCase();
        const base = pair.substring(0, 3);
        const quote = pair.substring(3, 6);
        const searchTerm = `${base}/${quote}`;

        try {
            const url = `https://www.fxstreet.com/news?q=${encodeURIComponent(searchTerm)}`;
            const response = await fetch(url, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (compatible; OpenClaw/1.0)',
                    'Accept': 'text/html',
                },
                timeout: 10000,
            });

            if (!response.ok) {
                return { headlines: [], note: `HTTP ${response.status}` };
            }

            const html = await response.text();
            const headlines = this._extractHeadlines(html);
            return { headlines: headlines.slice(0, 10) };
        } catch (err) {
            return { headlines: [], note: err.message };
        }
    }

    async _fetchReuters(symbol) {
        const pair = symbol.replace(/[^A-Za-z]/g, '').toUpperCase();
        const base = pair.substring(0, 3);
        const quote = pair.substring(3, 6);

        try {
            const url = `https://www.reuters.com/site-search/?query=${encodeURIComponent(base + ' ' + quote)}&section=forex`;
            const response = await fetch(url, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (compatible; OpenClaw/1.0)',
                    'Accept': 'text/html',
                },
                timeout: 10000,
            });

            if (!response.ok) {
                return { headlines: [], note: `HTTP ${response.status}` };
            }

            const html = await response.text();
            const headlines = this._extractHeadlines(html);
            return { headlines: headlines.slice(0, 10) };
        } catch (err) {
            return { headlines: [], note: err.message };
        }
    }

    _extractHeadlines(html) {
        const headlines = [];
        // Extract text from common headline patterns
        const patterns = [
            /<h[1-4][^>]*>(.*?)<\/h[1-4]>/gi,
            /<a[^>]*class="[^"]*(?:title|headline)[^"]*"[^>]*>(.*?)<\/a>/gi,
            /data-analytics-headline="([^"]+)"/gi,
        ];

        for (const pattern of patterns) {
            let match;
            while ((match = pattern.exec(html)) !== null) {
                const text = match[1].replace(/<[^>]+>/g, '').trim();
                if (text.length > 10 && text.length < 300) {
                    headlines.push(text);
                }
            }
        }

        // Deduplicate
        return [...new Set(headlines)];
    }
}

module.exports = { FundamentalChecker };
