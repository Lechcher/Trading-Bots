# Hedge Edge — Business Context Reference

> **Last Updated**: 2026-02-15
> **Status**: Beta (public)
> **URL**: hedgeedge.com

---

## What Hedge Edge Is

Hedge Edge is a **desktop application** (Electron + React) that provides **automated multi-account hedge management** for proprietary trading firm (prop firm) traders.

**Core mechanic**: When a trader opens a BUY on a prop firm challenge account, Hedge Edge instantly opens a SELL on a personal broker account (and vice versa). This ensures capital preservation regardless of whether the prop firm challenge passes or fails.

**Tagline**: *"Capital preservation through strategic hedging. Either secure a pass or recover your initial challenge fees — every trade is covered."*

---

## Target Customer

**Primary**: Prop firm traders running evaluation challenges at firms like FTMO, The5%ers, TopStep, Apex Trader Funding, MyForexFunds, etc.

**Profile**:
- 1-5 years trading experience
- Running 1-5 simultaneous challenges
- Spending $200-800/month on challenge fees
- Sophisticated enough to run multiple trading terminals
- Frustrated by manual hedging complexity
- Geographic concentration: Southeast Asia, Middle East, Africa (fast-growing), Europe, North America

**Pain point**: Losing $300-500 per failed challenge with no recovery mechanism. At 85-90% industry failure rates, most traders lose thousands before getting funded.

---

## Product

### Features
- **Reverse Copy Trading** (hedging) — automated hedge across accounts
- **Multi-Platform** — MT5 (live), MT4 (coming soon), cTrader (coming soon)
- **Multi-Account Management** — monitor all accounts in one dashboard
- **Real-Time Data** — live balances, equity, positions
- **Visual Hedge Map** — see hedged positions across accounts
- **Drawdown Monitoring** — track daily loss limits
- **Local-First Architecture** — runs on user's machine, zero cloud latency
- **License-Protected** — hardware-bound license key via Creem.io

### Technology Stack
- **Desktop App**: Electron + Vite + React 18 + TypeScript + Tailwind CSS + shadcn/ui
- **Trading Agents**: MQL5 (MT5), MQL4 (MT4), C# (cTrader)
- **Communication**: ZeroMQ (MT5), File IPC (MT4), Named Pipes (cTrader)
- **Backend**: Python 3.10+ (FastAPI), Supabase (PostgreSQL + Auth + Edge Functions)
- **Payments**: Creem.io (checkout, webhooks, license management)
- **Landing Page**: React + TypeScript on Vercel

---

## Revenue Model

### Stream 1: SaaS Subscriptions (Primary)

| Tier | Price | Status | Key Features |
|------|-------|--------|--------------|
| Free Guide | Free | Active | Tutorial, Discord access, single-phase guide |
| Starter | $29/mo | Active | Desktop app, 3 copier groups, 3 prop accounts, basic monitoring |
| Pro | $30/mo | Coming Soon | Unlimited groups, 5+5 accounts, hedge map, analytics |
| Hedger | $75/mo | Coming Soon | Everything + MT4/cTrader, API, webhooks, 10 devices |

**Note**: Pro at $30 is $1 above Starter — pricing gap needs fixing. Recommended: Pro at $59, Hedger at $99.

### Stream 2: IB Commissions (Secondary — But Strategic)

Per-lot rebates from partner brokers on hedge accounts opened by Hedge Edge users.

**Active Partners**:
- Vantage Markets (IB agreement signed)
- BlackBull Markets (IB agreement signed)

**Referred via**: `hedgedge.short.gy/vantage`, `hedgedge.short.gy/blackbull`

**Revenue model**: If 30% of users open partner broker accounts, trading 80 lots/month at $4/lot = ~$48K/month IB revenue at 500 users. At scale, IB can exceed SaaS revenue.

### Stream 3: Free Tier Funnel

Free hedge guide + Discord community converts to paid subscribers. Zero acquisition cost for organic funnel.

---

## Key Metrics (Estimates as of Feb 2026)

| Metric | Value |
|--------|-------|
| Active Users | ~500 |
| Paying Users | ~350 (est.) |
| MRR (SaaS) | ~$10-17K |
| Monthly Churn | ~8% (est.) |
| ARPU | ~$29-35 |
| LTV | ~$350-440 |
| Platforms Live | 1 (MT5) |
| Broker Partners | 2 (Vantage, BlackBull) |

---

## Competitive Landscape

### Direct Competitors (Hedge/Reverse Copy)
- Duplikium, Social Trader Tools, FX Blue, Local Trade Copier

### Adjacent Competitors (Generic Trade Copiers)
- MT4/MT5 copy plugins, MQL5 Signals, Signal Start

### Substitutes
- Manual hedging (two terminals), prop firm refund products, MQL5 marketplace EAs

### Hedge Edge Advantages
1. **Dedicated to hedging** — not a generic copier with a reverse button
2. **Local execution** — sub-millisecond latency vs cloud-based competitors
3. **Multi-platform roadmap** — MT4 + MT5 + cTrader (competitors typically support 1)
4. **IB revenue flywheel** — competitors don't monetize broker referrals effectively
5. **Community-first** — Discord as owned distribution channel

---

## Two Core Hedging Strategies

### Normal Hedge
Asymmetric lot sizing: Prop account carries directional exposure (e.g., 1.00 lot). Broker hedge uses small size (e.g., 0.05 lots) — just enough to recover the ~$500 challenge fee if the challenge fails.

### Over Hedge
Broker-side lot size exceeds fee recovery needs (e.g., 0.15 lots). Turns fee recovery into a profit strategy with higher risk/reward.

---

## Distribution Channels

| Channel | Status | Notes |
|---------|--------|-------|
| Landing page (hedgeedge.com) | Active | Hosted on Vercel |
| Discord community | Active | Primary community hub |
| YouTube | Active | Strategy demo videos |
| Broker referral links | Active | hedgedge.short.gy/* |
| Affiliate program | Not launched | High priority for growth |
| Social media (Twitter/X, TikTok, Reddit) | Minimal | Opportunity |
| Telegram groups | Not started | High potential for SEA/MENA |

---

## Strategic Priorities (Foundation Phase)

1. Launch MT4 and cTrader support → 2x addressable market
2. Fix pricing tiers (Pro at $59, Hedger at $99) → ARPU expansion
3. Launch affiliate program → zero-CAC acquisition
4. Sign 2 more broker partners → IB revenue diversification
5. Reach 1,000 paying users → milestone for next phase
