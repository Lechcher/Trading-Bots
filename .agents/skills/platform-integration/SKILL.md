---
name: platform-integration
description: |
  Manages the technical and product aspects of integrating new trading platforms
  (MT4, cTrader) and new broker APIs (beyond Vantage and BlackBull) into Hedge Edge.
  Produces integration specs, API compatibility matrices, phased rollout plans, and
  handles platform-specific edge cases like MT4 FIFO rules, cTrader OAuth lifecycle,
  and varying lot size precision across brokers.
---

# Platform Integration

## Objective

Expand Hedge Edge from its current MT5-only support to a multi-platform hedging solution covering MT4, cTrader, and additional broker APIs. Each integration must meet the same latency, reliability, and trader safety standards as the MT5 EA. Platform expansion is the primary growth driver: MT4 still commands a large share of prop firm traders, and cTrader adoption is accelerating at firms like The5%ers and IC Markets-backed props.

## When to Use This Skill

- A new platform integration is being scoped (MT4 EA, cTrader cBot, or a new API protocol)
- A new broker needs to be onboarded (API evaluation, account setup, IB agreement coordination)
- Platform-specific edge cases surface during development (MT4 order model conflicts, cTrader partial close behavior)
- Compatibility matrix needs updating after a broker API change or platform update
- A user requests support for a platform/broker combination not yet covered
- Cross-platform hedge synchronization architecture decisions are needed

## Input Specification

| Field | Type | Required | Description |
|---|---|---|---|
| integration_type | enum | Yes | new_platform, new_broker, edge_case_resolution, compatibility_update, architecture_decision |
| platform | string | Yes | mt4, mt5, ctrader, or a specific broker name |
| description | string | Yes | What needs to be integrated, resolved, or decided |
| urgency | enum | No | standard, elevated (user-blocking), critical (trader exposure risk) |
| affected_users | integer | No | Estimated number of users who need this integration |
| technical_constraints | string | No | Known limitations or blockers |

## Step-by-Step Process

### 1. Platform Assessment

For each new platform, evaluate along these dimensions:

**MT4 Integration Assessment**:
- Order model: MT4 uses a single-order model (no native hedging mode on many brokers). Hedge positions must be tracked via magic numbers and order comments to distinguish prop-account mirrors from personal-account hedges.
- API differences: OrderSend() vs MT5 PositionOpen(). MT4 lacks OnTradeTransaction() - must poll OrdersTotal() and compare against cached state to detect new positions.
- Latency implications: MT4 DLL-based IPC is less efficient than MT5. Target hedge latency may need to be relaxed to 200ms for MT4.
- FIFO rules: Some MT4 brokers enforce FIFO (First In, First Out) close ordering. If the prop account partially closes, the hedge close on FIFO brokers must close the oldest matching position, not the most recent.
- Testing environment: MT4 Strategy Tester does not support multi-symbol testing or real-time IPC. Integration testing requires dedicated demo accounts.

**cTrader Integration Assessment**:
- Architecture: cTrader uses cBots (C# .NET) running in the cTrader Automate environment. Communication with the Electron app via cTrader Open API (gRPC/protobuf).
- Authentication: OAuth 2.0 with refresh tokens. Token expires every 24 hours - must implement silent refresh without interrupting active hedges.
- Order model: cTrader supports native hedging. However, partial close behavior differs from MT5 - cTrader creates a new position ID on partial close, requiring position tracking logic rewrite.
- Lot size precision: cTrader uses volume in units (100,000 = 1 lot) while MT5 uses lots (1.0 = 1 lot). Conversion must account for broker-specific step sizes.
- Market data: cTrader provides different symbol naming conventions (e.g., EUR/USD vs EURUSD). Symbol mapping layer required.

**New Broker Assessment**:
- Server locations and ping latency from common user VPS providers (New York, London, Tokyo)
- API rate limits and throttling behavior under burst order flow
- Supported account types (hedging mode required on the personal broker side)
- Minimum lot sizes and step sizes (some brokers use 0.01 minimum, others 0.1)
- Commission structure compatibility with Hedge Edge IB program
- Regulatory jurisdiction and implications for user onboarding

### 2. Integration Specification

Write a platform integration spec in Notion with:

**Architecture Design**:
- Communication protocol between the platform EA/cBot and Electron main process
  - MT5: Named pipes or localhost TCP socket (current implementation)
  - MT4: DLL injection for IPC or localhost HTTP server in the EA
  - cTrader: cTrader Open API via gRPC from Electron Node.js process
- Message format: JSON payloads with trade event type, symbol, volume, direction, account ID, timestamp
- Heartbeat mechanism: Platform sends heartbeat every 5 seconds; if Electron misses 3 heartbeats, trigger reconnection alert
- Failover behavior: If IPC connection drops during an active hedge, the EA/cBot must:
  1. Continue running independently (do not close the hedge position)
  2. Queue trade events locally
  3. Resynchronize state when connection restores
  4. Alert the trader via the platform's native alert system (MT4/MT5 Alert(), cTrader Print())

**Position Mapping Logic**:
- How positions on the source (prop) account map to hedge positions on the personal account
- Handling partial closes, modifications (SL/TP changes), and position reversals
- Multi-account mapping: If 3 prop accounts trade EURUSD simultaneously, how are hedges distributed across personal accounts?
- Lot size normalization across platforms with different precision

**Compliance Layer**:
- Each platform integration must include prop firm rule checking:
  - Maximum daily drawdown proximity check before allowing new hedges
  - Maximum total drawdown proximity check
  - Position size limits per prop firm tier
  - News trading restrictions (if applicable for the prop firm)

### 3. API Compatibility Matrix

Maintain a living compatibility matrix:

| Feature | MT5 (Live) | MT4 (Alpha) | cTrader (Design) |
|---|---|---|---|
| Hedge execution | Yes, sub-100ms | In progress, target 200ms | Not started |
| Multi-account sync | Yes, up to 10 | Limited to 3 (DLL constraint) | Planned for 5 |
| Partial close handling | Yes | Blocked by FIFO edge case | Needs new position ID tracking |
| Broker reconnection | Yes, auto-recovery in 5s | Manual reconnect required | OAuth token refresh needed |
| Native hedging mode | Yes | Broker-dependent | Yes |
| Position event detection | OnTradeTransaction() | Polling OrdersTotal() | OnPositionOpened event |
| Lot size precision | 0.01 lots | 0.01 lots | Volume units (variable) |

### 4. Phased Rollout Plan

Each platform integration follows a phased rollout:

**Phase 1 - Lab (2-4 weeks)**:
- Core IPC and trade event detection working in test environment
- Single-account hedge execution with demo accounts
- Latency benchmarks established
- No real money, no user access

**Phase 2 - Closed Alpha (2-4 weeks)**:
- 5-10 selected beta testers with small demo accounts
- Multi-account support enabled
- Edge case testing: partial closes, SL/TP modifications, broker disconnects
- Daily monitoring of hedge success rate and latency
- Feedback collected via dedicated Discord thread

**Phase 3 - Open Beta (4-6 weeks)**:
- Available to all subscribers on Pro and Enterprise tiers
- Full feature parity with MT5 (or documented limitations)
- Staged rollout using feature flags in Supabase
- console logging (console logging later) monitoring with platform-specific error grouping

**Phase 4 - General Availability**:
- Available to all tiers
- Landing page updated with platform support
- IB broker partnerships confirmed for the platform
- Support documentation published

### 5. Edge Case Resolution

Document and resolve platform-specific edge cases:

**MT4 Edge Cases**:
- FIFO partial close: When prop account partially closes 0.5 lots of a 2.0 lot EURUSD position, and the personal broker is FIFO-only, the hedge close must target the oldest EURUSD position. Solution: maintain an ordered position queue per symbol per account.
- No hedging mode: Some MT4 brokers net positions. If the hedge and a pre-existing personal trade are on the same symbol, they'll net out instead of creating a separate hedge position. Solution: require hedging-mode brokers for personal accounts, validate on setup.
- Magic number collisions: If the trader uses other EAs on the same MT4 instance, magic numbers could collide. Solution: use a Hedge Edge-specific magic number range (900000-999999) and verify no conflicts on EA initialization.

**cTrader Edge Cases**:
- OAuth token expiry during active hedge: Token expires, API calls fail, hedge commands don't execute. Solution: pre-emptive token refresh 1 hour before expiry, with a fallback to cached credentials for read-only state monitoring.
- Position ID changes on partial close: cTrader assigns new position IDs when a position is partially closed. The hedge tracker must update its mapping. Solution: use deal history events to track position lineage.
- Symbol name mismatch: cTrader broker uses "EUR/USD" while prop MT5 account uses "EURUSD". Solution: configurable symbol mapping table in Electron settings, with auto-detection for common patterns.

**Cross-Platform Edge Cases**:
- Prop on MT5, hedge on MT4: Different latency profiles. The MT4 hedge may execute 100ms slower. Solution: document the latency delta for users, recommend MT5-to-MT5 for optimal performance.
- Prop on cTrader, hedge on MT5: Different lot size conventions. Solution: normalize to lots (1.0 = 100,000 units) in the Electron middleware before dispatching to the hedge platform.

### 6. Broker Onboarding

For each new broker:
1. Evaluate API access and demo account availability
2. Test connection from common VPS locations (latency benchmarks)
3. Validate hedging mode support on live accounts
4. Coordinate with Business Strategist Agent for IB partnership potential
5. Add broker to the Electron app's broker configuration dropdown
6. Create setup guide with screenshots for the specific broker's MT4/MT5/cTrader platform
7. Test with 3 users in closed alpha before general availability

## Output Specification

| Output Type | Format | Destination |
|---|---|---|
| Integration Spec | Structured Notion page with architecture, mapping, compliance | Notion Product Specs database |
| API Compatibility Matrix | Markdown table updated per platform milestone | Notion + GitHub wiki |
| Phased Rollout Plan | Timeline with milestones, gates, and metrics | Notion roadmap |
| Edge Case Documentation | Detailed scenarios with solutions | GitHub wiki + Notion |
| Broker Onboarding Checklist | Checklist with validation steps | Notion Broker database |
| Platform PR Requirements | GitHub Issue with acceptance criteria for platform PRs | hedge-edge-app repo |

## API and Platform Requirements

- GitHub API (GITHUB_TOKEN): Create platform integration issues, manage feature branches, track PR progress
- Supabase (SUPABASE_URL, SUPABASE_KEY): Feature flags for platform rollout (mt4_enabled, ctrader_enabled per user), broker configuration storage, trade event logs per platform
- Notion API (NOTION_API_KEY): Integration specs, compatibility matrices, broker database, rollout tracking
- Discord Bot (DISCORD_BOT_TOKEN): Platform-specific alpha testing threads, broker setup support, announcements
- MetaTrader Manager API (MT_MANAGER_API_KEY, future): EA distribution, remote configuration for MT4/MT5 EAs
- Local automation scripts deployed to Railway