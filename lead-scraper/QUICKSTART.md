# Plug-and-Play Quickstart

Two ways to get everything into your Make.com account. Either way, budget **~20 minutes** total.

## Option A — one command (recommended)

Creates the data store + all 5 scenarios in your account automatically, with the
data store pre-wired into every module.

1. In Make: avatar (bottom-left) → **Profile** → **API** tab → **Add token**.
   Scopes: `scenarios:read/write`, `datastores:read/write`, `udts:read/write`, `teams:read`, `organizations:read`.
2. Note your zone from your browser URL: `https://us1.make.com` → zone is `us1` (could be `us2`, `eu1`, `eu2`).
3. On your computer (needs Python 3.8+, no packages to install):

   ```bash
   python3 lead-scraper/scripts/provision_make.py --token YOUR_TOKEN --zone us1
   ```

4. The script prints the 5 remaining browser clicks (Google sign-in, webhook URL, API keys, turn ON).
5. Revoke the API token in Make when done.

## Option B — manual import (no script)

1. Make → **Data stores** → create `LA Leads Master` using `templates/make-data-store-schema.json` (2 min).
2. Make → **Scenarios** → **Create a new scenario** → ⋯ menu → **Import Blueprint** → import each file
   in `make-blueprints/` in order 01→05 (1 min each).
3. In each imported scenario, click the modules marked ⚠️: select your data store and Google connection.

## Both options finish the same way

| Step | Where | Time |
|---|---|---|
| Create Google Sheet `LA Leads Master`, tab `Leads`, paste header row from `templates/leads-master-schema.csv` | Google Sheets | 2 min |
| Attach Google connection + pick spreadsheet in Sheets/Drive/Email modules | each scenario | 3 min |
| Create webhook in scenario 04, copy URL into your form/ad tool | scenario 04 | 1 min |
| Paste API keys into each `CONFIG — edit me` module: Socrata (free, data.lacity.org), ATTOM (free trial, api.developer.attomdata.com), OpenCorporates (free tier) | module #1 of 01/02/03 | 5 min |
| **Run once** on each scenario, check rows land in the sheet | each scenario | 5 min |
| Toggle all 5 scenarios **ON** | scenario list | 1 min |

Schedules are pre-set by the script (01 daily 07:00, 02 daily 07:30, 03 hourly, 04 instant, 05 Monday 08:00).
If you imported manually (Option B), set those via the clock icon on each trigger module.

**Why can't this be 100% zero-click?** Make requires the Google/Gmail connection to be authorized
by you in your own browser (OAuth) — no script or third party can do that step for you. Everything
that *can* be automated has been.

Full detail: `docs/setup-guide.md`. Troubleshooting is at the bottom of that file.
