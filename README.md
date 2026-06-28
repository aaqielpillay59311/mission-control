# Mission Control · Debt Freedom OS

Private financial command dashboard. Passcode-gated (obscurity layer, not encryption).

## Setup

1. **Passcode**: SHA-256 hash in `index.html` — default `debtfree`. To change, run:
   ```
   python3 -c "import hashlib; print(hashlib.sha256(b'YOURCODE').hexdigest())"
   ```
   Then paste the hash into `PASS_HASH` in `index.html`.

2. **Pipeline data**: Edit `pipeline.json` with your outreach companies.

3. **Email notification** (optional): Uses Resend API for daily summaries.

## Deploy

Deployed on Vercel. Push to GitHub → auto-deploys via Vercel integration.

## Built With

- UI/UX Pro Max design intelligence (97.3k ★ GitHub)
- Jack Roberts' Scroll-Stop Builder methodology
- Vanilla JS — zero framework dependencies