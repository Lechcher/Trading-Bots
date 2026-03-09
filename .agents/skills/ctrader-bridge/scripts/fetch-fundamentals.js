#!/usr/bin/env node
'use strict';

/**
 * Fundamental Data Fetcher
 * Fetches economic calendar and news from multiple sources
 */

const https = require('https');
const http = require('http');
const path = require('path');
const fs = require('fs');

const SOURCES = {
  calendar: 'https://nfs.faireconomy.media/ff_calendar_thisweek.json',
  investingNews: 'https://www.investing.com/rss/news.rss',
  forexliveNews: 'https://www.forexlive.com/feed/news',
};

const TAVILY_API_URL = 'https://api.tavily.com/search';
const TAVILY_QUERIES = [
  'latest central bank decisions and interest rate policy affecting EUR USD GBP JPY USDJPY XAUUSD',
  'major forex economic data surprises today FOMC ECB BoE BOJ RBA risk sentiment',
];

function loadTavilyApiKey() {
  if (process.env.TAVILY_API_KEY) return process.env.TAVILY_API_KEY;

  const envPath = path.resolve(__dirname, '..', '..', 'tavily-search', '.env');
  if (!fs.existsSync(envPath)) return null;

  const content = fs.readFileSync(envPath, 'utf8');
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq < 0) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^['\"]|['\"]$/g, '');
    if (key === 'TAVILY_API_KEY' && value) {
      process.env.TAVILY_API_KEY = value;
      return value;
    }
  }

  return null;
}

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https') ? https : http;
    const req = client.get(url, { 
      headers: { 
        'User-Agent': 'Mozilla/5.0 (compatible; OpenClaw/1.0)',
        'Accept': '*/*'
      },
      timeout: 10000 
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, data }));
    });
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Timeout'));
    });
  });
}

async function fetchTavilyNews(query, n = 5) {
  const key = loadTavilyApiKey();
  if (!key) {
    return { error: 'Missing TAVILY_API_KEY' };
  }

  try {
    const body = {
      api_key: key,
      query,
      search_depth: 'basic',
      topic: 'news',
      max_results: Math.max(1, Math.min(n, 20)),
      include_answer: false,
      include_raw_content: true,
      days: 14
    };

    const res = await fetch(TAVILY_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      return { error: `Tavily request failed (${res.status}): ${errText}` };
    }

    const payload = await res.json();
    const results = Array.isArray(payload.results) ? payload.results : [];

    return {
      query,
      answer: payload.answer || '',
      sources: results.slice(0, n).map((item) => ({
        title: String(item?.title || '').trim(),
        url: String(item?.url || '').trim(),
        rawContent: String(item?.raw_content || item?.content || '').trim(),
        publishedDate: item?.published_date || item?.publishedDate || null,
        score: item?.score || null,
      })),
    };
  } catch (err) {
    return { error: String(err?.message || err) };
  }
}

function parseRSS(xml) {
  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let match;
  
  while ((match = itemRegex.exec(xml)) !== null) {
    const itemXml = match[1];
    const title = (itemXml.match(/<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/title>/i) || [])[1] || '';
    const pubDate = (itemXml.match(/<pubDate>(.*?)<\/pubDate>/i) || [])[1] || '';
    const link = (itemXml.match(/<link>(.*?)<\/link>/i) || [])[1] || '';
    const author = (itemXml.match(/<author>(.*?)<\/author>/i) || itemXml.match(/<dc:creator>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/dc:creator>/i) || [])[1] || '';
    
    if (title) {
      items.push({
        title: title.replace(/<!\[CDATA\[|\]\]>/g, '').trim(),
        pubDate,
        link,
        author: author.replace(/<!\[CDATA\[|\]\]>/g, '').trim()
      });
    }
  }
  
  return items;
}

function filterRelevantNews(items, symbols = []) {
  const keywords = [
    // Currencies
    'USD', 'EUR', 'GBP', 'JPY', 'CHF', 'AUD', 'CAD', 'NZD',
    'dollar', 'euro', 'pound', 'yen', 'franc',
    // Central banks
    'Fed', 'ECB', 'BOE', 'BOJ', 'SNB', 'RBA', 'BOC', 'RBNZ',
    'Federal Reserve', 'central bank', 'rate', 'hike', 'cut',
    // Economic
    'inflation', 'CPI', 'GDP', 'employment', 'jobs', 'NFP', 'payroll',
    'PMI', 'retail sales', 'trade balance',
    // Markets
    'forex', 'gold', 'XAUUSD', 'oil', 'risk', 'haven'
  ];
  
  const symbolKeywords = symbols.flatMap(s => [
    s,
    s.substring(0, 3),
    s.substring(3, 6)
  ]);
  
  const allKeywords = [...keywords, ...symbolKeywords];
  const pattern = new RegExp(allKeywords.join('|'), 'i');
  
  return items.filter(item => pattern.test(item.title));
}

function getUpcomingHighImpactEvents(events, hoursAhead = 24) {
  const now = new Date();
  const cutoff = new Date(now.getTime() + hoursAhead * 60 * 60 * 1000);
  
  return events.filter(e => {
    if (e.impact !== 'High') return false;
    const eventDate = new Date(e.date);
    return eventDate >= now && eventDate <= cutoff;
  }).map(e => ({
    title: e.title,
    country: e.country,
    date: e.date,
    impact: e.impact,
    forecast: e.forecast,
    previous: e.previous
  }));
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'all';
  const results = { timestamp: new Date().toISOString() };
  
  try {
    if (command === 'calendar' || command === 'all') {
      try {
        const calRes = await fetchUrl(SOURCES.calendar);
        if (calRes.status === 200) {
          const events = JSON.parse(calRes.data);
          results.calendar = {
            totalEvents: events.length,
            upcomingHighImpact: getUpcomingHighImpactEvents(events, 24)
          };
        }
      } catch (e) {
        results.calendarError = e.message;
      }
    }
    
    if (command === 'news' || command === 'all') {
      results.news = [];
      
      // Investing.com
      try {
        const invRes = await fetchUrl(SOURCES.investingNews);
        if (invRes.status === 200) {
          const items = parseRSS(invRes.data);
          const relevant = filterRelevantNews(items.slice(0, 20));
          results.news.push(...relevant.map(n => ({ ...n, source: 'investing.com' })));
        }
      } catch (e) {
        results.investingError = e.message;
      }
      
      // ForexLive
      try {
        const flRes = await fetchUrl(SOURCES.forexliveNews);
        if (flRes.status === 200) {
          const items = parseRSS(flRes.data);
          results.news.push(...items.slice(0, 10).map(n => ({ ...n, source: 'forexlive' })));
        }
      } catch (e) {
        results.forexliveError = e.message;
      }

      // Tavily: fundamental + policy/econ context
      try {
        const tavilyResults = await Promise.all(
          TAVILY_QUERIES.map((query) => fetchTavilyNews(query, 4))
        );

        const valid = tavilyResults.filter(r => r && !r.error);
        const errors = tavilyResults.filter(r => r && r.error);

        results.newsTavily = {
          results: valid,
          errors: errors.map(r => r.error)
        };
      } catch (e) {
        results.tavilyError = e.message;
      }

      // Sort by date
      results.news.sort((a, b) => new Date(b.pubDate || 0) - new Date(a.pubDate || 0));
    }
    
    console.log(JSON.stringify(results, null, 2));
    
  } catch (e) {
    console.error(JSON.stringify({ error: e.message }));
    process.exit(1);
  }
}

main();
