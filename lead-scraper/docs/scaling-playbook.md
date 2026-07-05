# Scaling Playbook

The system is deliberately config-first: every scenario's knobs live in module #1 (`CONFIG`).
Scaling = clone a scenario, change the config, never rebuild logic.

## Phase 1 — Widen LA County coverage (free)

Scenario 01 covers the **City of LA** (~4M people). To cover the rest of the county:

1. **Clone scenario 01** per jurisdiction and change only `CFG_SODA_DATASET_URL` + field mappings:
   - Long Beach, Pasadena, Santa Monica, Glendale, Burbank — each has an open-data or Accela portal.
   - LA County unincorporated (~1M people): EPIC-LA (epicla.lacounty.gov).
2. Keep **one shared Data Store and one master sheet** — dedupe and export stay centralized automatically.
3. In scenario 02, grow `CFG_ZIP_LIST` from 10 ZIPs toward all ~300 LA County ZIPs (mind your ATTOM
   plan's monthly call quota; 300 ZIPs daily ≈ 9k calls/month).

## Phase 2 — Contact data (skip tracing)

Public records give you names + addresses; dialing needs phones/emails:

1. Add a scenario "06 Skip Trace": Google Sheets *Search Rows* (`phone` empty, `lead_score` ≥ 60,
   limit 50/run) → HTTP to BatchData / Endato / PeopleDataLabs person-search → *Update Row* with
   phone/email → set `status=enriched`.
2. Immediately after, scrub against the **DNC list** (see compliance.md) and set `dnc_checked`.
3. Cost control: only skip-trace leads above a score threshold — that's why scoring runs first.

## Phase 3 — Delivery beyond CSV

The weekly CSV stays your archive; add real-time routing:

- **CRM push:** add a module after the sheet-append in scenarios 01/02/04 — Make has native modules
  for HubSpot, GoHighLevel, Salesforce, Pipedrive, Close. Map the same 41 fields.
- **Hot-lead alerts:** router branch: `lead_score >= 85` → Slack/SMS/email notification within minutes
  of capture (a same-day call on a fresh re-roof permit or webhook lead converts dramatically better).
- **Dialer feed:** most dialers (CallTools, Mojo, ReadyMode) ingest CSV via email or API — point
  scenario 05's email at the dialer's intake address, or add an HTTP module.

## Phase 4 — More counties / states

1. Duplicate the whole scenario set per county; only CONFIG changes:
   - Permits: find the county/city's Socrata/Accela/ArcGIS permit feed (most metros have one).
   - Sales: ATTOM covers the whole country — change `postalcode` lists only.
   - LLC: OpenCorporates covers all US states — change `jurisdiction_code` (e.g. `us_az`, `us_nv`).
2. Add a `county` config variable and keep writing to the same master sheet, or one sheet per county
   with a consolidated export — both work; the schema already has a `county` column.

## Phase 5 — Volume hardening

When you pass ~500 leads/day:

- **Sheet → database:** swap Google Sheets modules for Airtable or Postgres (Make has native modules;
  the column schema is unchanged). Sheets slows past ~50k rows.
- **Data store size:** raise the Make data store cap, or key by APN only and prune `exported` records
  monthly with a cleanup scenario.
- **Ops budget:** Make pricing is per operation — batch with aggregators where possible; move the
  highest-volume miner to a 2×/day schedule with a 12-hour lookback instead of hourly polling.
- **CA SOS Master Unload ($100):** replaces per-call LLC lookups with a local table once LLC volume is high.

## Scoring tune-ups as you learn

Track `score_reasons` against actual conversions in the sheet (`status` → `dead`/`won` via your CRM)
and adjust the weights in each scenario's scoring module. Typical after-tuning weights:
webhook intent +60, TCPA consent +15, re-roof permit +65, owner-occupied +25, entry-level price +25,
FHA loan flag (ATTOM upper tiers) +25.
