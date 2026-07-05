# LA County Lead Scraper — Make.com Automation System

A scalable lead-generation pipeline built on [Make.com](https://www.make.com) that mines
**public records** (county permit data, assessor/property data, LLC registrations) and
**inbound intent sources** (Facebook Lead Ads / web forms) to produce high-quality,
scored, deduplicated leads for:

- 🏠 **First-time home buyers** (recent purchasers + pre-purchase intent leads) in LA County
- ☀️ **Solar install prospects** (re-roof permits, recent buyers without solar, market intel from solar permits)

Everything lands in one **master Google Sheet** and is exported weekly (or on demand) as a **CSV file**.

---

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │                MAKE.COM SCENARIOS               │
                    │                                                 │
 LA City / County   │  01 Solar Permit Miner (daily)                  │
 Open Data (SODA) ──┼──► pull roof/solar permits ─► dedupe ─► score ──┤
                    │                                                 │
 Assessor / ATTOM   │  02 Recent-Buyer Miner (daily)                  │      ┌──────────────┐
 sales data ────────┼──► pull recent sales ─► FTHB score ─► dedupe ───┼────► │ Master Google│
                    │                                                 │      │ Sheet + Make │
 FB Lead Ads /      │  04 Intent Lead Webhook (instant)               │      │ Data Store   │
 web forms ─────────┼──► normalize ─► assessor enrich ─► write ───────┤      └──────┬───────┘
                    │                                                 │             │
 CA SOS / Open-     │  03 LLC Enrichment (hourly)                     │             │
 Corporates ────────┼──► find LLC owners ─► resolve agents ─► update ─┤             │
                    │                                                 │             ▼
                    │  05 Weekly CSV Export (weekly / webhook)        │      leads_YYYY-MM-DD.csv
                    │  ──► filter new rows ─► CSV ─► Drive + Email ───┼────► (Drive + inbox)
                    └─────────────────────────────────────────────────┘
```

## What's in this folder

| Path | What it is |
|---|---|
| `make-blueprints/01-solar-permit-miner.blueprint.json` | Daily miner: LADBS permits via Socrata SODA API. Re-roof permits = hot solar leads; solar permits = exclusion list + competitor intel. |
| `make-blueprints/02-recent-buyer-miner.blueprint.json` | Daily miner: recent LA County sales (ATTOM API, free-trial-key friendly) scored with first-time-buyer heuristics. |
| `make-blueprints/03-llc-enrichment.blueprint.json` | Hourly: rows whose owner is an LLC/trust/corp get resolved via OpenCorporates (default) or the official CA SOS Calico API. |
| `make-blueprints/04-intent-lead-webhook.blueprint.json` | Instant webhook: ingest first-time-buyer / solar intent leads from Facebook Lead Ads, landing pages, or any form tool; auto-enriched against the LA County Assessor portal. |
| `make-blueprints/05-weekly-csv-export.blueprint.json` | Weekly: new rows → CSV file → Google Drive + emailed as attachment. |
| `templates/leads-master-schema.csv` | The master column schema — paste row 1 into your Google Sheet, and this is also the CSV export layout. |
| `templates/make-data-store-schema.json` | Data structure for the Make Data Store used for deduplication. |
| `docs/setup-guide.md` | Click-by-click setup: import blueprints, connect accounts, get API keys, test. |
| `docs/data-sources.md` | Every data source with endpoint, auth, cost, and which fields we pull. |
| `docs/scaling-playbook.md` | How to add counties, add sources, add skip-tracing, push to a CRM/dialer. |
| `docs/compliance.md` | TCPA / DNC / CCPA rules you must follow before calling or texting these leads. |

## Quick start (~45 minutes)

1. Read `docs/setup-guide.md` end-to-end once.
2. Create the master Google Sheet from `templates/leads-master-schema.csv`.
3. Create a Make **Data Store** named `LA Leads Master` using `templates/make-data-store-schema.json`.
4. In Make: *Scenarios → Import Blueprint* — import the 5 JSON files in order.
5. Re-link connections (Google Sheets, Drive, Email) and paste API keys into the **CONFIG** module (module #1) of each scenario.
6. Run each scenario once manually, verify rows land in the sheet, then turn on scheduling.

## Why this produces *high-quality* leads

- **Re-roof permits** are the single best public-record solar signal: a homeowner who just re-roofed
  has a solar-ready roof and demonstrated budget. We pull them daily, hours after issuance.
- **Recent buyers** are prime for both audiences: new FTHB purchasers need insurance/warranty/upgrades,
  and buyers of homes *without* an existing solar permit are the ideal solar pitch.
- **Owner-occupancy check** (mailing address = property address, homeowner exemption) filters out
  landlords and flippers automatically.
- **LLC resolution** turns anonymous LLC owners into named registered agents/managers with addresses.
- **Lead scoring (0–100)** with human-readable score reasons, so your sales team calls the top of the list first.
- **Deduplication** by APN + permit number across all scenarios via the Make Data Store.

## Scaling later

The whole system is config-driven: each scenario's first module is a `CONFIG` variable block
(dataset URLs, keywords, lookback windows, price bands, API keys). To scale you clone a scenario
and change the config — no rebuilding. See `docs/scaling-playbook.md` for the full path:
more counties → paid property APIs → skip tracing (phones/emails) → CRM & dialer push → team routing.
