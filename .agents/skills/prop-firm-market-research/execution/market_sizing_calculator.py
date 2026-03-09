#!/usr/bin/env python3
"""
market_sizing_calculator.py

Configurable TAM/SAM/SOM model for Hedge Edge's market opportunity.
Supports scenario analysis (bear/base/bull cases) and sensitivity testing.

Usage:
    python market_sizing_calculator.py --scenario base --output tmp/market_sizing.json
    python market_sizing_calculator.py --scenario bull --sensitivity hedging_awareness_pct
"""

import json
import argparse
from datetime import datetime, timezone
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
from shared.notion_client import add_row, log_task


# ── Scenario Definitions ─────────────────────────────────────────────────────

SCENARIOS = {
    "bear": {
        "label": "Conservative / Bear Case",
        "total_active_prop_traders": 400_000,
        "avg_challenges_per_month": 2,
        "avg_challenge_fee_usd": 350,
        "hedging_awareness_pct": 0.10,
        "hedging_tool_adoption_pct": 0.03,
        "supported_platform_pct": 0.65,
        "acquirable_share_12mo": 0.02,
        "avg_subscription_usd_monthly": 25,
        "ib_commission_per_lot_usd": 3.0,
        "avg_lots_per_user_monthly": 50,
        "monthly_churn_rate": 0.12,
    },
    "base": {
        "label": "Base Case",
        "total_active_prop_traders": 750_000,
        "avg_challenges_per_month": 3,
        "avg_challenge_fee_usd": 400,
        "hedging_awareness_pct": 0.20,
        "hedging_tool_adoption_pct": 0.07,
        "supported_platform_pct": 0.70,
        "acquirable_share_12mo": 0.05,
        "avg_subscription_usd_monthly": 35,
        "ib_commission_per_lot_usd": 4.0,
        "avg_lots_per_user_monthly": 80,
        "monthly_churn_rate": 0.08,
    },
    "bull": {
        "label": "Optimistic / Bull Case",
        "total_active_prop_traders": 1_200_000,
        "avg_challenges_per_month": 4,
        "avg_challenge_fee_usd": 450,
        "hedging_awareness_pct": 0.30,
        "hedging_tool_adoption_pct": 0.12,
        "supported_platform_pct": 0.80,
        "acquirable_share_12mo": 0.08,
        "avg_subscription_usd_monthly": 45,
        "ib_commission_per_lot_usd": 5.0,
        "avg_lots_per_user_monthly": 120,
        "monthly_churn_rate": 0.05,
    },
}


def calculate_market_size(params: dict) -> dict:
    """Full market sizing model."""
    
    # ── TAM: Total Addressable Market ─────────────────────────────────────
    # All prop firm traders × annual challenge spend
    tam_challenge_fees = (
        params["total_active_prop_traders"]
        * params["avg_challenges_per_month"]
        * params["avg_challenge_fee_usd"]
        * 12
    )
    
    # ── SAM: Serviceable Addressable Market ───────────────────────────────
    # On supported platforms × aware of hedging
    sam = (
        tam_challenge_fees
        * params["supported_platform_pct"]
        * params["hedging_awareness_pct"]
    )
    
    # ── SOM: Serviceable Obtainable Market (12-month) ─────────────────────
    som = sam * params["acquirable_share_12mo"]
    
    # ── Hedge Edge Revenue Model ──────────────────────────────────────────
    
    # Addressable users (people who would consider the tool)
    addressable_users = (
        params["total_active_prop_traders"]
        * params["supported_platform_pct"]
        * params["hedging_awareness_pct"]
        * params["hedging_tool_adoption_pct"]
    )
    
    # Acquirable users in 12 months
    acquired_users_12mo = addressable_users * params["acquirable_share_12mo"]
    
    # SaaS Revenue
    saas_mrr = acquired_users_12mo * params["avg_subscription_usd_monthly"]
    saas_arr = saas_mrr * 12
    
    # IB Revenue (secondary)
    ib_monthly_per_user = (
        params["ib_commission_per_lot_usd"]
        * params["avg_lots_per_user_monthly"]
    )
    ib_mrr = acquired_users_12mo * ib_monthly_per_user * 0.30  # 30% of users use partner brokers
    ib_arr = ib_mrr * 12
    
    # Blended
    total_mrr = saas_mrr + ib_mrr
    total_arr = total_mrr * 12
    
    # LTV calculation
    avg_customer_lifetime_months = 1 / params["monthly_churn_rate"]
    ltv_saas = params["avg_subscription_usd_monthly"] * avg_customer_lifetime_months
    ltv_ib = ib_monthly_per_user * 0.30 * avg_customer_lifetime_months
    ltv_total = ltv_saas + ltv_ib
    
    return {
        "scenario": params.get("label", "custom"),
        "calculated_at": datetime.now(timezone.utc).isoformat(),
        "market_sizing": {
            "tam_annual_usd": round(tam_challenge_fees),
            "sam_annual_usd": round(sam),
            "som_annual_usd": round(som),
        },
        "user_funnel": {
            "total_prop_traders": params["total_active_prop_traders"],
            "on_supported_platforms": round(params["total_active_prop_traders"] * params["supported_platform_pct"]),
            "aware_of_hedging": round(addressable_users / params["hedging_tool_adoption_pct"]),
            "would_use_tool": round(addressable_users),
            "acquirable_12mo": round(acquired_users_12mo),
        },
        "revenue_projection": {
            "saas_mrr": round(saas_mrr, 2),
            "saas_arr": round(saas_arr, 2),
            "ib_mrr": round(ib_mrr, 2),
            "ib_arr": round(ib_arr, 2),
            "total_mrr": round(total_mrr, 2),
            "total_arr": round(total_arr, 2),
        },
        "unit_economics": {
            "avg_customer_lifetime_months": round(avg_customer_lifetime_months, 1),
            "ltv_saas_usd": round(ltv_saas, 2),
            "ltv_ib_usd": round(ltv_ib, 2),
            "ltv_total_usd": round(ltv_total, 2),
            "monthly_churn_rate": params["monthly_churn_rate"],
        },
        "assumptions": params,
    }


def sensitivity_analysis(base_params: dict, variable: str, multipliers=None) -> list:
    """Run sensitivity analysis on a single variable."""
    if multipliers is None:
        multipliers = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    if variable not in base_params:
        raise ValueError(f"Variable '{variable}' not found in parameters")
    
    results = []
    base_value = base_params[variable]
    
    for mult in multipliers:
        test_params = {**base_params}
        test_params[variable] = base_value * mult
        result = calculate_market_size(test_params)
        result["sensitivity"] = {
            "variable": variable,
            "multiplier": mult,
            "base_value": base_value,
            "test_value": base_value * mult,
        }
        results.append(result)
    
    return results


def main():
    parser = argparse.ArgumentParser(description="Hedge Edge market sizing calculator")
    parser.add_argument("--scenario", default="base", choices=["bear", "base", "bull", "all"])
    parser.add_argument("--sensitivity", default=None, help="Variable name for sensitivity analysis")
    parser.add_argument("--output", default=None, help="Output file path")
    args = parser.parse_args()
    
    if args.scenario == "all":
        results = {}
        for name, params in SCENARIOS.items():
            results[name] = calculate_market_size(params)
            print(f"\n{'='*60}")
            print(f"  {params['label']}")
            print(f"{'='*60}")
            print(f"  TAM: ${results[name]['market_sizing']['tam_annual_usd']:,.0f}")
            print(f"  SAM: ${results[name]['market_sizing']['sam_annual_usd']:,.0f}")
            print(f"  SOM: ${results[name]['market_sizing']['som_annual_usd']:,.0f}")
            print(f"  Projected MRR: ${results[name]['revenue_projection']['total_mrr']:,.2f}")
            print(f"  Projected ARR: ${results[name]['revenue_projection']['total_arr']:,.2f}")
            print(f"  LTV (total): ${results[name]['unit_economics']['ltv_total_usd']:,.2f}")
        output = results
    elif args.sensitivity:
        params = SCENARIOS.get(args.scenario, SCENARIOS["base"])
        output = sensitivity_analysis(params, args.sensitivity)
        print(f"\nSensitivity Analysis: {args.sensitivity}")
        for r in output:
            s = r["sensitivity"]
            print(f"  {s['multiplier']}x ({s['test_value']:.4f}) → MRR: ${r['revenue_projection']['total_mrr']:,.2f}")
    else:
        params = SCENARIOS[args.scenario]
        output = calculate_market_size(params)
        print(f"\n{params['label']}")
        print(f"  TAM: ${output['market_sizing']['tam_annual_usd']:,.0f}")
        print(f"  SAM: ${output['market_sizing']['sam_annual_usd']:,.0f}")
        print(f"  SOM: ${output['market_sizing']['som_annual_usd']:,.0f}")
        print(f"  Projected MRR: ${output['revenue_projection']['total_mrr']:,.2f}")
        print(f"  Projected ARR: ${output['revenue_projection']['total_arr']:,.2f}")
        print(f"  Acquirable users (12mo): {output['user_funnel']['acquirable_12mo']:,}")
        print(f"  LTV (total): ${output['unit_economics']['ltv_total_usd']:,.2f}")
    
    log_task("Business Strategist", f"Market sizing: {args.scenario}", "Done", "Medium", json.dumps(output, default=str)[:500])

    if args.output:
        from pathlib import Path
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output, f, indent=2)
        print(f"\nResults saved to {args.output}")


if __name__ == "__main__":
    main()
