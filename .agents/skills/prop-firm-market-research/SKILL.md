---
name: prop-firm-market-research
description: |
  Conducts deep research into the prop firm trading ecosystem — market sizing,
  trend analysis, trader demographics, prop firm economics, and emerging
  opportunities. Use when strategic decisions require current market intelligence
  about the prop firm industry and its adjacent markets.
---

# Prop Firm Market Research

## Objective

Generate actionable market intelligence about the proprietary trading firm ecosystem that directly informs Hedge Edge's strategic decisions. This is not generic fintech research — it is laser-focused on the economics, behavioral patterns, and structural dynamics of prop firm traders and the firms that serve them.

## When to Use This Skill

- Before making pricing, positioning, or product roadmap decisions
- When evaluating a new market segment (e.g., futures prop firms, crypto prop firms)
- When a competitor enters or exits the market
- Quarterly for trend refreshes
- When considering geographic expansion
- When broker partnership negotiations require market leverage data

## Input Specification

| Input | Type | Required | Description |
|-------|------|----------|-------------|
| research_topic | string | Yes | Specific research question or area (e.g., "prop firm failure rates by firm", "MT4 vs MT5 adoption trends") |
| depth | string | No | `quick` (30 min), `standard` (2 hr), `deep-dive` (full day). Default: `standard` |
| output_format | string | No | `brief` (1-page), `report` (5-10 pages), `data-pack` (structured JSON). Default: `report` |
| time_horizon | string | No | `current` (now), `6mo`, `12mo`, `3yr`. Default: `current` |

## Step-by-Step Process

### Phase 1: Define the Research Frame

1. Clarify the strategic question — what decision will this research inform?
2. Identify the 3-5 data points that would change the decision if different
3. Set boundaries — what's in scope, what's explicitly out

### Phase 2: Ecosystem Mapping

1. **Prop Firm Landscape**: Map active prop firms by:
   - Challenge fee structure ($25–$999+)
   - Payout splits and scaling plans
   - Platform support (MT4, MT5, cTrader, TradingView, DXtrade, Match-Trader)
   - Geographic concentration (US futures vs global forex)
   - Estimated trader volume
2. **Trader Demographics**: Profile the target customer:
   - Geographic distribution (Southeast Asia, Middle East, Africa emerging fast)
   - Experience level (mostly 1-3 years, some beginners chasing funded accounts)
   - Average monthly spend on challenges ($200-800/mo for serious traders)
   - Platform preferences by region
   - Pain points ranked by severity
3. **Adjacent Markets**: Identify expansion opportunities:
   - Crypto prop firms (emerging, less regulated)
   - Futures prop firms (Apex, TopStep — different mechanics)
   - Signal/copy trading services
   - Trading education platforms (overlap audience)

### Phase 3: Quantitative Analysis

1. **Market Sizing** (TAM/SAM/SOM):
   - TAM: Total global prop firm traders × average annual challenge spend
   - SAM: Traders on supported platforms (MT4/MT5/cTrader) who actively hedge
   - SOM: Realistically acquirable within 12 months given current channels
2. **Economics Modeling**:
   - Average prop firm challenge: $300-500 fee, 80% fail Phase 1, ~5% get funded
   - Hedge Edge value per user: (challenges_per_month × fee × recovery_rate) - subscription_cost
   - Break-even analysis: At what recovery rate does Hedge Edge pay for itself?
3. **Growth Rates**: Prop firm industry CAGR, regional growth differentials

### Phase 4: Trend Identification

1. **Regulatory Trends**: Which jurisdictions are cracking down on prop firms? Which are favorable?
2. **Technology Trends**: Platform fragmentation (DXtrade, Match-Trader adoption), cloud vs local execution shift
3. **Pricing Trends**: Race to the bottom on challenge fees? Premium tier emergence?
4. **Behavioral Trends**: Are traders getting savvier about hedging? Is hedging becoming mainstream or staying niche?

### Phase 5: Synthesis & Recommendations

1. Distill findings into 3-5 "so what" insights that directly impact Hedge Edge strategy
2. Assign confidence levels (high/medium/low) to each finding
3. Flag any findings that contradict current assumptions
4. Recommend specific follow-up research or experiments

## Execution Scripts

- [market_research_scraper.py](./execution/market_research_scraper.py) — Scrapes and aggregates prop firm data from public sources
- [market_sizing_calculator.py](./execution/market_sizing_calculator.py) — TAM/SAM/SOM calculation model with configurable assumptions

## Resources

- [hedge-edge-business-context.md](./resources/hedge-edge-business-context.md) — Complete Hedge Edge business context (product, pricing, positioning, tech stack)
- [prop-firm-directory.json](./resources/prop-firm-directory.json) — Database of major prop firms with key attributes

## Definition of Done

- [ ] Research question is clearly stated and bounded
- [ ] At least 3 quantified data points are provided (with sources or estimation methodology)
- [ ] Findings are connected to specific Hedge Edge strategic decisions
- [ ] Confidence levels assigned to each major finding
- [ ] Output matches requested format (brief/report/data-pack)
- [ ] Contradictions with current assumptions are explicitly flagged

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| Stale data | Prop firm landscape changes rapidly | Cross-reference multiple sources; flag data older than 90 days |
| Conflicting signals | Different sources disagree | Present both sides with confidence weighting; recommend validation experiment |
| Scope creep | Research expanding beyond useful bounds | Re-anchor to the original strategic question; cut tangential threads |
| Data gaps | Some metrics don't have public data | Use triangulation (e.g., SimilarWeb traffic × conversion benchmarks) and state assumptions explicitly |
