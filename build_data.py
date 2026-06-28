#!/usr/bin/env python3
"""build_data.py - regenerate pipeline.json for the Mission Control dashboard.

Reads ../../outreach/crm.json and writes a SANITIZED snapshot (pipeline.json)
next to index.html. We deliberately DROP emails, sources and first_line copy so
the deployed dashboard never exposes contact addresses - it only needs the
pipeline (company, suburb, status, dates, deal value, channel).

Run this any time the pipeline changes, then redeploy:
    py build_data.py
    vercel deploy . --prod --yes      (from Websites/mission-control)
"""
import json, pathlib, datetime

HERE = pathlib.Path(__file__).parent
CRM = HERE.parent.parent / "outreach" / "crm.json"
OUT = HERE / "pipeline.json"

KEEP = ("slug", "company_name", "suburb", "outreach_status", "outreach_channel",
        "contacted_date", "followup_1_date", "followup_2_date", "reply_date",
        "next_action_date", "deal_value_zar")


def main():
    crm = json.loads(CRM.read_text(encoding="utf-8"))
    companies = [{k: c.get(k) for k in KEEP} for c in crm["companies"]]
    meta = crm.get("meta", {})
    snap = {
        "generated": datetime.date.today().isoformat(),
        "niche": "Pest Control",
        "default_deal_value_zar": meta.get("default_deal_value_zar"),
        "entry_deal_zar": meta.get("entry_deal_zar"),
        "full_stack_zar": meta.get("full_stack_zar"),
        "companies": companies,
    }
    OUT.write_text(json.dumps(snap, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote %s  (%d companies, no emails/sources included)" % (OUT.name, len(companies)))


if __name__ == "__main__":
    main()
