# Mission Control — private war-room dashboard

A single-page, vanilla HTML/CSS/JS dashboard. Dark theme, mobile-first (built to check from your phone). 4 panels:

1. **Debt Command** — R524,043 across 7 real accounts in avalanche order (highest APR first), monthly burn, min payments, cash runway, and a live "what-if" payoff calculator.
2. **Outreach Pipeline** — reads `pipeline.json` (a sanitized snapshot of `outreach/crm.json`, **no emails**). Funnel by stage + "needs action today".
3. **Revenue Tracker** — type your current MRR (saved in this browser via `localStorage`); gauge from R0 → break-even (R10,596) → freedom (R74,000).
4. **The War** — the big number: **DAYS TO DEBT FREEDOM**, from a real month-by-month avalanche amortization driven by your MRR + weighted pipeline.

## Privacy
- `noindex` (meta + `robots.txt` + `X-Robots-Tag` header via `vercel.json`) — search engines won't list it.
- **Passcode gate** = obscurity, NOT encryption. The numbers live in this page's source, so anyone with the link *and* the passcode (or who reads view-source) can see them. Don't share the URL. For real protection, host behind Vercel Pro password-protection or keep it local.

## Change the passcode
Default is `debtfree`. To change it, hash your new code and paste it into `PASS_HASH` near the top of `index.html`:
```
py -c "import hashlib;print(hashlib.sha256(b'YOURNEWCODE').hexdigest())"
```

## Refresh the pipeline data
After the outreach pipeline moves (new sends, replies, wins):
```
py build_data.py          # regenerates pipeline.json from ../../outreach/crm.json (drops emails)
vercel deploy . --prod --yes
```

## Update debt / budget
Edit the `CONFIG` block at the top of `index.html` (`DEBT_ACCOUNTS`, `TOTAL_DEBT`, `MONTHLY_BURN`, `MONTHLY_INCOME`, `CASH_ON_HAND`, `MIN_PAYMENTS`, `RUNWAY_MONTHS`). Everything recomputes from those.

## Deploy
```
cd Websites/mission-control
vercel deploy . --prod --yes
```
