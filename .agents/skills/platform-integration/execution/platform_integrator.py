#!/usr/bin/env python3
"""
platform_integrator.py — Product Agent Platform Integration Tracker

Track and manage platform integrations (MT5, MT4, cTrader, broker APIs,
payment gateways) for the Hedge Edge prop-firm hedging tool.

Usage:
    python platform_integrator.py --action add-integration --platform mt4 --status in-development --priority P1
    python platform_integrator.py --action integration-status
    python platform_integrator.py --action update-status --platform ctrader --status testing --notes "Beta with 5 testers"
    python platform_integrator.py --action compatibility-matrix
    python platform_integrator.py --action integration-roadmap
"""

import sys, os, argparse, json
from datetime import datetime, timezone
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
from shared.notion_client import add_row, query_db, update_row, log_task

AGENT = "Product"

PLATFORMS = [
    "mt5", "mt4", "ctrader", "vantage-api", "blackbull-api",
    "creem", "supabase", "discord-bot", "railway",
]

STATUSES = ["planned", "in-development", "testing", "live", "deprecated"]

STATUS_ICONS = {
    "planned": "📋", "in-development": "🔧", "testing": "🧪",
    "live": "✅", "deprecated": "⛔",
}

# Platform metadata for display and compatibility
PLATFORM_META = {
    "mt5":          {"label": "MetaTrader 5",  "type": "Trading Platform", "category": "core"},
    "mt4":          {"label": "MetaTrader 4",  "type": "Trading Platform", "category": "core"},
    "ctrader":      {"label": "cTrader",       "type": "Trading Platform", "category": "core"},
    "vantage-api":  {"label": "Vantage API",   "type": "Broker API",      "category": "broker"},
    "blackbull-api":{"label": "BlackBull API", "type": "Broker API",      "category": "broker"},
    "creem":        {"label": "Creem",         "type": "Payment Gateway", "category": "infra"},
    "supabase":     {"label": "Supabase",      "type": "Backend DB",      "category": "infra"},
    "discord-bot":  {"label": "Discord Bot",   "type": "Community",       "category": "infra"},
    "railway":      {"label": "Railway",       "type": "Deployment",      "category": "infra"},
}

# Broker-platform compatibility (known/expected)
BROKER_COMPAT = {
    "Vantage":   {"mt5": "tested", "mt4": "pending", "ctrader": "n/a"},
    "BlackBull": {"mt5": "tested", "mt4": "planned", "ctrader": "planned"},
    "FTMO":      {"mt5": "tested", "mt4": "pending", "ctrader": "n/a"},
    "MFF":       {"mt5": "tested", "mt4": "pending", "ctrader": "n/a"},
    "TFT":       {"mt5": "tested", "mt4": "planned", "ctrader": "n/a"},
    "E8":        {"mt5": "tested", "mt4": "n/a",     "ctrader": "planned"},
}

COMPAT_ICONS = {"tested": "✅", "pending": "🟡", "planned": "📋", "n/a": "─"}


def _get_integrations():
    """Fetch all integration-type rows from feature_roadmap."""
    rows = query_db("feature_roadmap")
    return [r for r in rows if (r.get("Category") or "").lower() == "integration"]


def add_integration(args):
    """Register a new platform integration in feature_roadmap."""
    meta = PLATFORM_META.get(args.platform, {"label": args.platform.title(), "type": "Unknown"})
    status_label = args.status.replace("-", " ").title()

    row = {
        "Feature":    f"{meta['label']} Integration",
        "Status":     status_label,
        "Priority":   args.priority or "P2",
        "Category":   "Integration",
        "Quarter":    args.quarter or "",
        "Owner":      args.owner or "Product Team",
        "User Story": f"As a trader, I want {meta['label']} support so I can hedge across prop firm accounts.",
    }
    add_row("feature_roadmap", row)

    print("=" * 60)
    print("  🔌 INTEGRATION REGISTERED")
    print("=" * 60)
    print(f"  Platform:  {meta['label']} ({args.platform})")
    print(f"  Type:      {meta['type']}")
    print(f"  Status:    {STATUS_ICONS.get(args.status, '?')} {status_label}")
    print(f"  Priority:  {args.priority or 'P2'}")
    if args.quarter:
        print(f"  Quarter:   {args.quarter}")
    print("─" * 60)

    log_task(AGENT, f"Integration added: {meta['label']}",
             "Complete", args.priority or "P2",
             f"platform={args.platform}, status={args.status}")


def integration_status(args):
    """Show status of all platform integrations."""
    integrations = _get_integrations()

    print("=" * 60)
    print("  🔌 PLATFORM INTEGRATION STATUS")
    print("=" * 60)

    if not integrations:
        print("\n  No integrations tracked yet.")
        print("  Use --action add-integration to register one.")
        print("─" * 60)
        log_task(AGENT, "Integration status check", "Complete", "P3", "No integrations")
        return

    # Group by status
    by_status = defaultdict(list)
    for integ in integrations:
        raw = (integ.get("Status") or "planned").lower().replace(" ", "-")
        by_status[raw].append(integ)

    for status in STATUSES:
        items = by_status.get(status, [])
        if not items:
            continue
        icon = STATUS_ICONS.get(status, "?")
        label = status.replace("-", " ").title()
        print(f"\n  {icon} {label} ({len(items)})")
        print(f"  {'─' * 50}")
        for item in items:
            prio = item.get("Priority", "?")
            name = item.get("Feature", "?")
            quarter = item.get("Quarter") or "TBD"
            print(f"    [{prio}] {name}  — Q: {quarter}")

    # Summary bar
    total = len(integrations)
    live_count = len(by_status.get("live", []))
    dev_count = len(by_status.get("in-development", []))
    test_count = len(by_status.get("testing", []))
    planned_count = len(by_status.get("planned", []))

    print(f"\n  SUMMARY: {total} integrations")
    print(f"  ✅ Live: {live_count}  🔧 Dev: {dev_count}  🧪 Test: {test_count}  📋 Planned: {planned_count}")

    if total > 0:
        pct_live = live_count / total * 100
        bar_live = "█" * int(pct_live / 5) if pct_live > 0 else ""
        bar_rest = "░" * (20 - len(bar_live))
        print(f"  [{bar_live}{bar_rest}] {pct_live:.0f}% live")
    print("─" * 60)

    log_task(AGENT, "Integration status review", "Complete", "P3",
             f"total={total}, live={live_count}, dev={dev_count}")


def update_status(args):
    """Update a platform integration's status."""
    integrations = _get_integrations()
    meta = PLATFORM_META.get(args.platform, {"label": args.platform.title()})
    search_name = f"{meta['label']} Integration"

    match = None
    for integ in integrations:
        if search_name.lower() in (integ.get("Feature") or "").lower():
            match = integ
            break

    if not match:
        # Fallback: search by platform keyword
        for integ in integrations:
            if args.platform.replace("-", " ") in (integ.get("Feature") or "").lower():
                match = integ
                break

    if not match:
        print(f"❌ Integration not found for platform: {args.platform}")
        print(f"   Tracked integrations: {[i.get('Feature') for i in integrations]}")
        return

    old_status = match.get("Status", "?")
    new_label = args.status.replace("-", " ").title()
    updates = {"Status": new_label}
    if args.notes:
        updates["User Story"] = args.notes
    if args.status == "live":
        updates["Ship Date"] = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    update_row(match["_id"], "feature_roadmap", updates)

    print("=" * 60)
    print("  🔄 INTEGRATION STATUS UPDATED")
    print("=" * 60)
    print(f"  Platform:  {meta['label']}")
    print(f"  Previous:  {old_status}")
    print(f"  Current:   {STATUS_ICONS.get(args.status, '?')} {new_label}")
    if args.notes:
        print(f"  Notes:     {args.notes}")
    print("─" * 60)

    log_task(AGENT, f"Integration update: {meta['label']}",
             "Complete", "P2", f"{old_status} → {new_label}")


def compatibility_matrix(args):
    """Show broker × platform compatibility matrix."""
    trading_platforms = ["mt5", "mt4", "ctrader"]
    labels = {p: PLATFORM_META[p]["label"] for p in trading_platforms}

    print("=" * 60)
    print("  🧩 BROKER × PLATFORM COMPATIBILITY MATRIX")
    print("=" * 60)

    # Header
    header = f"  {'Broker':<12}"
    for plat in trading_platforms:
        header += f" {labels[plat]:>12}"
    print(f"\n{header}")
    print(f"  {'─' * 50}")

    tested_total = 0
    pending_total = 0
    planned_total = 0

    for broker, compat in BROKER_COMPAT.items():
        row_str = f"  {broker:<12}"
        for plat in trading_platforms:
            status = compat.get(plat, "n/a")
            icon = COMPAT_ICONS.get(status, "?")
            row_str += f" {icon:>12}"
            if status == "tested":
                tested_total += 1
            elif status == "pending":
                pending_total += 1
            elif status == "planned":
                planned_total += 1
        print(row_str)

    total_cells = len(BROKER_COMPAT) * len(trading_platforms)
    na_total = total_cells - tested_total - pending_total - planned_total

    print(f"  {'─' * 50}")
    print(f"\n  Legend: ✅ Tested  🟡 Pending  📋 Planned  ─ N/A")
    print(f"\n  Coverage: {tested_total}/{total_cells - na_total} actionable pairs tested "
          f"({tested_total / (total_cells - na_total) * 100:.0f}%)" if (total_cells - na_total) > 0 else "")
    print(f"  ✅ {tested_total} tested  🟡 {pending_total} pending  📋 {planned_total} planned")
    print("─" * 60)

    log_task(AGENT, "Compatibility matrix review", "Complete", "P3",
             f"tested={tested_total}, pending={pending_total}, planned={planned_total}")


def integration_roadmap(args):
    """Show integration roadmap timeline and dependencies."""
    integrations = _get_integrations()

    # Default roadmap timeline if DB is sparse
    ROADMAP_PHASES = [
        {"phase": "Phase 1 — Core (Live)",      "items": ["mt5"],
         "target": "Q4-2025", "deps": "None"},
        {"phase": "Phase 2 — MT4 Expansion",     "items": ["mt4", "vantage-api", "blackbull-api"],
         "target": "Q1-2026", "deps": "MT5 EA core stable"},
        {"phase": "Phase 3 — cTrader + Brokers", "items": ["ctrader"],
         "target": "Q2-2026", "deps": "MT4 complete, broker API layer abstracted"},
        {"phase": "Phase 4 — Infra Maturity",    "items": ["creem", "supabase", "discord-bot", "railway"],
         "target": "Ongoing", "deps": "Core platform live"},
    ]

    # Enrich with actual DB data
    integ_status = {}
    for integ in integrations:
        for plat_key, meta in PLATFORM_META.items():
            if meta["label"].lower() in (integ.get("Feature") or "").lower():
                integ_status[plat_key] = {
                    "status": (integ.get("Status") or "planned").lower().replace(" ", "-"),
                    "priority": integ.get("Priority", "?"),
                    "quarter": integ.get("Quarter") or "",
                }
                break

    print("=" * 60)
    print("  🗺️ INTEGRATION ROADMAP")
    print("=" * 60)

    for phase in ROADMAP_PHASES:
        print(f"\n  {phase['phase']}")
        print(f"  Target: {phase['target']}  |  Dependencies: {phase['deps']}")
        print(f"  {'─' * 48}")
        for plat_key in phase["items"]:
            meta = PLATFORM_META.get(plat_key, {"label": plat_key})
            db_info = integ_status.get(plat_key)
            if db_info:
                status = db_info["status"]
                prio = db_info["priority"]
                icon = STATUS_ICONS.get(status, "?")
                print(f"    {icon} {meta['label']:<18} [{prio}] {status.replace('-', ' ').title()}")
            else:
                print(f"    📋 {meta['label']:<18} [--] Not tracked yet")

    # Dependency graph (simplified ASCII)
    print(f"\n  DEPENDENCY CHAIN")
    print(f"  {'─' * 48}")
    print("    MT5 EA Core ──► MT4 Port ──► cTrader Port")
    print("         │              │")
    print("         ▼              ▼")
    print("    Broker API Layer (Vantage, BlackBull)")
    print("         │")
    print("         ▼")
    print("    Supabase ──► Railway ──► Creem Payments")
    print("         │")
    print("         ▼")
    print("    Discord Bot (community)")

    tracked = len(integ_status)
    total = len(PLATFORMS)
    print(f"\n  Tracked: {tracked}/{total} platforms in roadmap")
    print("─" * 60)

    log_task(AGENT, "Integration roadmap review", "Complete", "P2",
             f"tracked={tracked}/{total}")


# ─────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Product Agent — Platform Integration Tracker")
    parser.add_argument("--action", required=True,
                        choices=["add-integration", "integration-status", "update-status",
                                 "compatibility-matrix", "integration-roadmap"])
    parser.add_argument("--platform", choices=PLATFORMS)
    parser.add_argument("--status", choices=STATUSES)
    parser.add_argument("--priority", choices=["P1", "P2", "P3", "P4"])
    parser.add_argument("--quarter", help="Target quarter, e.g. Q2-2026")
    parser.add_argument("--owner", help="Owner team or person")
    parser.add_argument("--notes", help="Free-text notes for updates")
    args = parser.parse_args()

    dispatch = {
        "add-integration":     add_integration,
        "integration-status":  integration_status,
        "update-status":       update_status,
        "compatibility-matrix": compatibility_matrix,
        "integration-roadmap": integration_roadmap,
    }
    dispatch[args.action](args)
