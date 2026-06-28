#!/usr/bin/env python3
"""
import_companies.py
===================
Imports all real CRM companies from the local outreach JSON files into the
Supabase `outreach_companies` table via the PostgREST REST API.

Steps performed:
  1. Read all 5 CRM JSON files (pest control, plumbers, electricians,
     roofers, gardeners) -> 100 companies total.
  2. Connect to Supabase via the REST API (requests).
  3. Delete the existing SAMPLE rows  (protocol_name = 'SAMPLE').
  4. Insert all 100 companies in batches of 20.
  5. Verify the row count is exactly 100.
  6. Print a summary.

Auth note
---------
PostgREST enforces row-level security (RLS). The `outreach_companies` table
ships with a SELECT-only policy for the `anon` role, so the public anon key
can READ but not WRITE. For writes this script prefers a service-role key if
one is present in the environment / .env (SUPABASE_SERVICE_ROLE_KEY), and
otherwise falls back to the anon key. If you run this with only the anon key,
make sure temporary anon INSERT/DELETE policies exist, or the writes will be
rejected by RLS.
"""

import json
import sys
from pathlib import Path

import requests

# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent          # .../Websites/mission-control
PROJECT_ROOT = SCRIPT_DIR.parents[1]                  # .../Pest Control
OUTREACH_DIR = PROJECT_ROOT / "outreach"
ENV_FILE = SCRIPT_DIR / ".env"

# CRM file -> niche label  (order = import order)
CRM_FILES = [
    (OUTREACH_DIR / "crm.json",                "pest control"),
    (OUTREACH_DIR / "plumbers" / "crm.json",   "plumbers"),
    (OUTREACH_DIR / "electricians" / "crm.json", "electricians"),
    (OUTREACH_DIR / "roofers" / "crm.json",    "roofers"),
    (OUTREACH_DIR / "gardens" / "crm.json",    "gardeners"),
]

TABLE = "outreach_companies"
BATCH_SIZE = 20

# CRM outreach_status -> DB outreach_status
STATUS_MAP = {
    "not_contacted":   "not_started",
    "cold_sent":       "contacted",
    "followup_1_sent": "followed_up",
    "followup_2_sent": "followed_up",
    "replied":         "replied",
    "won":             "won",
}
DEFAULT_STATUS = "not_started"

# Sentinel email values in the CRM that are NOT real addresses -> store as NULL
EMPTY_EMAILS = {"", "not_found", "none", "n/a", "na"}


# --------------------------------------------------------------------------
# .env loader (no external dependency)
# --------------------------------------------------------------------------
def load_env(path: Path) -> dict:
    env = {}
    if not path.exists():
        sys.exit(f"ERROR: .env not found at {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        env[key.strip()] = val.strip().strip('"').strip("'")
    return env


# --------------------------------------------------------------------------
# Transform one CRM company dict -> one DB row dict
# --------------------------------------------------------------------------
def to_row(company: dict, niche: str) -> dict:
    email = (company.get("email") or "").strip()
    if email.lower() in EMPTY_EMAILS:
        email = None

    raw_status = (company.get("outreach_status") or "").strip()
    status = STATUS_MAP.get(raw_status, DEFAULT_STATUS)

    deal = company.get("deal_value_zar")

    return {
        "company_name":   company.get("company_name"),
        "niche":          niche,
        "suburb":         company.get("suburb"),
        "email":          email,
        "website":        company.get("website"),
        "demo_site_url":  company.get("site_url"),   # site_url -> demo_site_url
        "protocol_name":  company.get("protocol_name"),
        "outreach_status": status,
        "deal_value_zar": deal,
    }


def read_all_companies() -> list:
    rows = []
    for path, niche in CRM_FILES:
        if not path.exists():
            sys.exit(f"ERROR: CRM file not found: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        companies = data.get("companies", [])
        print(f"  read {len(companies):>3} from {path.relative_to(PROJECT_ROOT)}  (niche='{niche}')")
        for c in companies:
            rows.append(to_row(c, niche))
    return rows


# --------------------------------------------------------------------------
# Supabase REST helpers
# --------------------------------------------------------------------------
class Supabase:
    def __init__(self, url: str, anon_key: str, write_key: str):
        self.base = f"{url.rstrip('/')}/rest/v1"
        self.anon_key = anon_key
        self.write_key = write_key

    def _headers(self, key: str, extra: dict = None) -> dict:
        h = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        }
        if extra:
            h.update(extra)
        return h

    def delete_samples(self) -> None:
        r = requests.delete(
            f"{self.base}/{TABLE}",
            headers=self._headers(self.write_key, {"Prefer": "return=representation"}),
            params={"protocol_name": "eq.SAMPLE"},
            timeout=30,
        )
        if r.status_code not in (200, 204):
            sys.exit(f"ERROR deleting SAMPLE rows: {r.status_code} {r.text}")
        deleted = len(r.json()) if r.text.strip() else 0
        print(f"  deleted {deleted} SAMPLE row(s)")

    def insert_batch(self, batch: list) -> int:
        r = requests.post(
            f"{self.base}/{TABLE}",
            headers=self._headers(self.write_key, {"Prefer": "return=representation"}),
            data=json.dumps(batch),
            timeout=30,
        )
        if r.status_code not in (200, 201):
            sys.exit(f"ERROR inserting batch: {r.status_code} {r.text}")
        return len(r.json())

    def count(self) -> int:
        # HEAD with Prefer: count=exact returns count in the Content-Range header.
        r = requests.get(
            f"{self.base}/{TABLE}",
            headers=self._headers(self.anon_key, {"Prefer": "count=exact"}),
            params={"select": "id"},
            timeout=30,
        )
        if r.status_code not in (200, 206):
            sys.exit(f"ERROR counting rows: {r.status_code} {r.text}")
        # Content-Range looks like "0-99/100"
        cr = r.headers.get("Content-Range", "")
        if "/" in cr:
            return int(cr.split("/")[-1])
        return len(r.json())

    def niche_breakdown(self) -> dict:
        r = requests.get(
            f"{self.base}/{TABLE}",
            headers=self._headers(self.anon_key),
            params={"select": "niche"},
            timeout=30,
        )
        r.raise_for_status()
        counts = {}
        for row in r.json():
            counts[row["niche"]] = counts.get(row["niche"], 0) + 1
        return counts


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main() -> None:
    print("=" * 60)
    print("  Supabase CRM import -> outreach_companies")
    print("=" * 60)

    env = load_env(ENV_FILE)
    url = env.get("SUPABASE_URL")
    anon_key = env.get("SUPABASE_ANON_KEY")
    # Prefer a service-role key for writes if available; else fall back to anon.
    write_key = env.get("SUPABASE_SERVICE_ROLE_KEY") or anon_key
    if not url or not anon_key:
        sys.exit("ERROR: SUPABASE_URL / SUPABASE_ANON_KEY missing from .env")
    using_service = bool(env.get("SUPABASE_SERVICE_ROLE_KEY"))
    print(f"  target : {url}")
    print(f"  write auth : {'service_role' if using_service else 'anon'} key")

    print("\n[1/5] Reading CRM files ...")
    rows = read_all_companies()
    print(f"  total companies to import: {len(rows)}")

    sb = Supabase(url, anon_key, write_key)

    print("\n[2/5] Deleting SAMPLE rows ...")
    sb.delete_samples()

    print(f"\n[3/5] Inserting {len(rows)} companies in batches of {BATCH_SIZE} ...")
    inserted = 0
    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i:i + BATCH_SIZE]
        n = sb.insert_batch(batch)
        inserted += n
        print(f"  batch {i // BATCH_SIZE + 1}: inserted {n:>2}  (running total {inserted})")
    print(f"  inserted {inserted} rows")

    print("\n[4/5] Verifying row count ...")
    total = sb.count()
    print(f"  outreach_companies now has {total} rows")

    print("\n[5/5] Summary")
    breakdown = sb.niche_breakdown()
    for niche in ["pest control", "plumbers", "electricians", "roofers", "gardeners"]:
        print(f"    {niche:<14} {breakdown.get(niche, 0):>3}")
    other = {k: v for k, v in breakdown.items()
             if k not in {"pest control", "plumbers", "electricians", "roofers", "gardeners"}}
    for k, v in other.items():
        print(f"    {k:<14} {v:>3}  (unexpected niche)")

    print("-" * 60)
    if total == 100:
        print("  [OK] SUCCESS - exactly 100 companies imported.")
    else:
        print(f"  [WARN] Expected 100 rows, found {total}. Review the output above.")
        sys.exit(1)
    print("=" * 60)


if __name__ == "__main__":
    main()
