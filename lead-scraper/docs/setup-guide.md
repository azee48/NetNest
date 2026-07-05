# Setup Guide — LA County Lead Scraper on Make.com

Total time: ~45 minutes. Do the steps in order.

## Step 0 — Accounts & API keys you need

| Service | Cost | Where to get it | Used by |
|---|---|---|---|
| Make.com account | Free tier works for testing; Core plan ($9/mo) recommended | make.com | everything |
| Google account (Sheets + Drive + Gmail) | Free | — | scenarios 01–05 |
| Socrata app token | **Free** | data.lacity.org → sign up → Developer Settings → Create App Token | scenario 01 |
| ATTOM Data API key | Free 30-day trial, then from ~$99/mo | api.developer.attomdata.com | scenario 02 |
| OpenCorporates API token | Free tier (limited calls) / paid | opencorporates.com/api_accounts/new | scenario 03 |
| CA SOS Calico API key (optional, official) | Free registration | calicodev.sos.ca.gov | scenario 03 (alt) |
| Facebook Lead Ads (optional) | Ad spend only | business.facebook.com | scenario 04 |

> The system runs end-to-end with only the **free** items: scenario 01 (permits), 03 (LLC, free tier),
> 04 (webhook), 05 (export). Scenario 02 is strongest with ATTOM's free trial key.

## Step 1 — Create the master Google Sheet

1. Create a Google Sheet named **`LA Leads Master`**.
2. Rename the first tab to **`Leads`**.
3. Copy row 1 of `templates/leads-master-schema.csv` (the header row, 41 columns) into row 1 of the tab.
4. Optional: row 2 of the template is a sample row showing what a filled lead looks like — paste it, look at it, delete it.

## Step 2 — Create the Make Data Store (deduplication)

1. In Make: left sidebar → **Data stores** → **Add data store**.
2. Name: `LA Leads Master`. Size: 10 MB (~50k records).
3. **Add data structure** → create fields exactly as listed in `templates/make-data-store-schema.json`
   (`dedupe_key`, `lead_id`, `lead_type`, `source`, `capture_date`, `full_name`, `property_address`,
   `zip`, `apn`, `lead_score`, `status`).

## Step 3 — Import the 5 blueprints

For each file in `make-blueprints/` (in numeric order):

1. Make → **Scenarios** → **Create a new scenario** → three-dots menu (⋯) → **Import Blueprint** → pick the JSON file.
2. Modules with a ⚠️ need re-linking (this is normal — connections never travel inside blueprints):
   - **Google Sheets / Drive / Email modules** → click, sign in with Google, select the `LA Leads Master` spreadsheet and `Leads` tab.
   - **Data store modules** → click, select the `LA Leads Master` data store.
   - **Webhook module (scenario 04)** → click → *Create a webhook* → copy the generated URL.
3. Open **module #1 (`CONFIG — edit me`)** in each scenario and paste your API keys / tune the settings. All knobs live there — you never edit other modules for config.

## Step 4 — Test each scenario once

Run each scenario manually with **Run once**:

| Scenario | How to test | Expected result |
|---|---|---|
| 01 Solar Permit Miner | Run once | Bundles of permits flow through; new rows appear in the sheet with `lead_type=solar` |
| 02 Recent-Buyer Miner | Run once | Rows with `lead_type=fthb`, sale price/date filled |
| 03 LLC Enrichment | Add a test row with `owner_name_raw` = `SUNSET HOLDINGS LLC`, run once | Columns `llc_name`, `llc_agent_name` fill in |
| 04 Intent Webhook | `curl -X POST <your-webhook-url> -H 'Content-Type: application/json' -d '{"full_name":"Test Lead","email":"test@example.com","phone":"3105551234","street":"123 Main St","city":"Los Angeles","zip":"90001","interest":"solar","source":"landing_page","consent_tcpa":true}'` | Row appears instantly, score ≥ 90 |
| 05 CSV Export | Run once | CSV lands in your Drive folder + inbox; exported rows flip `status` → `exported` |

**First-run tip for 01 and 02:** after the first successful run, click the enrichment module's
output bubble (the assessor portal HTTP call) to see the exact JSON it returned, then map
`OwnerNames`, mailing address, and homeowner-exemption fields into the Google Sheets module's
empty columns (6/7/20/21). Field names on undocumented county endpoints occasionally shift, which
is why these mappings are left for you to confirm live.

> ⚠️ If the Socrata request in scenario 01 returns a `no such column` error, the dataset's column
> names differ from the defaults. Open `https://data.lacity.org` → search "building permits" → API
> docs, and update `CFG_WHERE_CLAUSE` plus the field mappings. See `docs/data-sources.md`.

## Step 5 — Turn on the schedules

| Scenario | Schedule |
|---|---|
| 01 Solar Permit Miner | Daily 07:00 (America/Los_Angeles) |
| 02 Recent-Buyer Miner | Daily 07:30 |
| 03 LLC Enrichment | Every hour |
| 04 Intent Webhook | **Instant** (always on — just toggle the scenario ON) |
| 05 CSV Export | Weekly, Monday 08:00 (or daily if you prefer) |

Set schedules via the clock icon on the trigger module, then flip each scenario's ON switch.

## Step 6 — Point real lead sources at the webhook (scenario 04)

- **Facebook/Instagram Lead Ads:** in Make, you can replace the generic webhook with the native
  *Facebook Lead Ads → New Lead* trigger, or use a bridge (e.g. LeadsBridge) posting to the webhook URL.
- **Landing pages / forms:** Typeform, Webflow, WordPress (WPForms), Carrd, Framer — all can POST
  JSON to the webhook. Match the JSON keys in the webhook module's note.
- Suggested campaigns: "LA first-time home buyer programs — check your eligibility" and
  "How much would solar save on your DWP/SCE bill?" Both capture `consent_tcpa` at the form level —
  **make sure your form includes the consent checkbox language from `docs/compliance.md`.**

## Troubleshooting

- **Scenario stops with an error:** open the scenario's History tab, click the failed run — Make shows the failing module and the raw response.
- **Duplicate rows:** confirm both Data Store modules in the scenario point at the *same* data store, and the search module has "continue when no results" enabled.
- **Rate limits (429):** lower `CFG_MAX_ROWS` / the search `limit`, or space out schedules. Sequential processing is already enabled on scenarios 03 and 05.
- **Make operations budget:** each permit/sale consumes ~4–6 operations. 100 new leads/day ≈ 15–18k ops/month → Core plan covers it; scale plans as volume grows.
