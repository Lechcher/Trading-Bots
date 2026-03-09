'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class ThesisManager {
    constructor(thesesDir = path.join(__dirname, '..', 'theses')) {
        this.thesesDir = thesesDir;
        if (!fs.existsSync(this.thesesDir)) {
            fs.mkdirSync(this.thesesDir, { recursive: true });
        }
    }

    createThesis({ symbol, direction, reasoning, invalidationConditions = [], fundamentalAnchors = [] }) {
        const date = new Date().toISOString().split('T')[0];
        const shortId = crypto.randomBytes(3).toString('hex');
        const filename = `${date}-${symbol}-${direction}-${shortId}.md`;
        const filepath = path.join(this.thesesDir, filename);
        const now = new Date().toISOString();

        const invalidationLines = invalidationConditions.map(c => `- ${c}`).join('\n');
        const anchorLines = fundamentalAnchors.map(a => `- ${a}`).join('\n');

        const content = `# ${symbol} ${direction} - ${date}

## Thesis
${reasoning}

## Entry Criteria
- AI agent identified opportunity based on fundamental analysis

## Invalidation Conditions
${invalidationLines || '- None specified'}

## Fundamental Anchors
${anchorLines || '- None specified'}

## Status: ACTIVE
Last checked: ${now}

## Check Log
- ${now}: Thesis created
`;

        fs.writeFileSync(filepath, content, 'utf8');
        return { filename, filepath };
    }

    getThesis(filename) {
        const filepath = path.join(this.thesesDir, filename);
        if (!fs.existsSync(filepath)) {
            return null;
        }

        const raw = fs.readFileSync(filepath, 'utf8');
        return this._parseThesis(filename, raw);
    }

    getActiveTheses() {
        const files = fs.readdirSync(this.thesesDir).filter(f => f.endsWith('.md'));
        const active = [];

        for (const file of files) {
            const thesis = this.getThesis(file);
            if (thesis && thesis.status === 'ACTIVE') {
                active.push(thesis);
            }
        }

        return active;
    }

    getThesesForComment(comment) {
        if (!comment) return null;
        const filename = comment.trim();
        return this.getThesis(filename);
    }

    updateThesisStatus(filename, status, checkNote = '') {
        const filepath = path.join(this.thesesDir, filename);
        if (!fs.existsSync(filepath)) return false;

        let content = fs.readFileSync(filepath, 'utf8');
        const now = new Date().toISOString();

        // Update status line
        content = content.replace(/## Status: \w+/, `## Status: ${status}`);

        // Update last checked
        content = content.replace(/Last checked: .+/, `Last checked: ${now}`);

        // Append to check log
        const logEntry = `- ${now}: ${checkNote || `Status changed to ${status}`}`;
        content = content.trimEnd() + '\n' + logEntry + '\n';

        fs.writeFileSync(filepath, content, 'utf8');
        return true;
    }

    _parseThesis(filename, raw) {
        const statusMatch = raw.match(/## Status: (\w+)/);
        const thesisMatch = raw.match(/## Thesis\n([\s\S]*?)(?=\n## )/);
        const invalidationMatch = raw.match(/## Invalidation Conditions\n([\s\S]*?)(?=\n## )/);
        const anchorsMatch = raw.match(/## Fundamental Anchors\n([\s\S]*?)(?=\n## )/);

        // Extract symbol and direction from filename: date-SYMBOL-Direction-id.md
        const parts = filename.replace('.md', '').split('-');
        // date is parts[0]-parts[1]-parts[2], symbol is parts[3], direction is parts[4]
        const symbol = parts.length >= 5 ? parts[3] : '';
        const direction = parts.length >= 6 ? parts[4] : '';

        return {
            filename,
            symbol,
            direction,
            status: statusMatch ? statusMatch[1] : 'UNKNOWN',
            reasoning: thesisMatch ? thesisMatch[1].trim() : '',
            invalidationConditions: this._parseListItems(invalidationMatch ? invalidationMatch[1] : ''),
            fundamentalAnchors: this._parseListItems(anchorsMatch ? anchorsMatch[1] : ''),
            raw,
        };
    }

    _parseListItems(text) {
        if (!text) return [];
        return text.split('\n')
            .map(line => line.replace(/^- /, '').trim())
            .filter(line => line.length > 0 && line !== 'None specified');
    }
}

module.exports = { ThesisManager };
