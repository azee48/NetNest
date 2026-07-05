# Data Sources — endpoints, auth, and what we extract

All sources below are public records or officially published APIs. Respect each portal's
terms of use and rate limits; identify your app with tokens where offered.

## 1. LA City building permits (LADBS) — Socrata SODA API

- **What:** every building/electrical/mechanical permit issued in the City of Los Angeles, updated daily.
- **Endpoint pattern:** `https://data.lacity.org/resource/<dataset-id>.json`
- **Dataset ids:** `pi9x-tg5x` (current permits feed). Legacy: `yv23-pmwf` (2013–present archive).
  Confirm the live id at [data.lacity.org](https://data.lacity.org) → search "Building and Safety Permit".
- **Auth:** none required; a free app token (`X-App-Token` header) lifts throttling limits.
- **Query language:** SoQL — e.g.
  `?$where=issue_date >= '2026-06-28' AND upper(work_desc) LIKE '%ROOF%'&$order=issue_date DESC&$limit=1000`
- **Fields we use:** permit number, permit type, work description, issue date, address parts,
  ZIP, assessor book/page/parcel (→ APN), valuation, contractor business name, applicant name.
- **Lead value:** re-roof permits = solar-ready homeowners with budget (hot); solar/PV permits =
  homes to exclude + competitor/market intel.

## 2. LA County Assessor — portal API + open data

- **Portal API (used for enrichment):** `https://portal.assessor.lacounty.gov/api/search?search=<address or AIN>` —
  the JSON endpoint behind [portal.assessor.lacounty.gov](https://portal.assessor.lacounty.gov/). Returns parcel matches
  with AIN, current owner-of-record, situs + mailing address, use type, homeowner exemption, assessed values.
  Undocumented but publicly served; be gentle (we call it once per new lead only). Field names can change —
  verify on first run.
- **Open data:** [assessor.lacounty.gov/open-data-initiative](https://assessor.lacounty.gov/open-data-initiative/) and
  [data.lacounty.gov](https://data.lacounty.gov/) publish full annual parcel rolls (2.4M parcels) — useful for
  bulk backfills rather than daily polling.
- **Lead value:** owner name for permits/sales, owner-occupancy check (mailing = situs, homeowner
  exemption), property characteristics.

## 3. Recent sales / transfers — ATTOM Data API (primary for scenario 02)

- **Endpoint:** `https://api.gateway.attomdata.com/propertyapi/v1.0.0/sale/snapshot`
- **Auth:** `apikey` header — free 30-day trial at [api.developer.attomdata.com](https://api.developer.attomdata.com).
- **Params we use:** `postalcode`, `startsalesearchdate`, `endsalesearchdate`, `minsaleamt`, `maxsaleamt`, `pagesize`.
- **Fields:** sale price/date/type, address, APN, owner-occupancy (absentee indicator), property type,
  year built, size, beds/baths.
- **Why paid here:** LA County recorder deed data has no free real-time API; the assessor roll is annual.
  ATTOM (or PropertyRadar / BatchData / Estated — drop-in swaps in module 3 of scenario 02) is the
  standard way to get sales within days of recording.
- **FTHB proxy:** entry-level price band + owner-occupied + SFR/condo + resale + individual buyer.
  Higher ATTOM tiers expose buyer names and FHA/VA loan flags (FHA purchase ≈ strong first-time-buyer signal).

## 4. LLC / business entity data — OpenCorporates & CA SOS

- **OpenCorporates (default):**
  - Search: `https://api.opencorporates.com/v0.4/companies/search?q=<name>&jurisdiction_code=us_ca&api_token=<key>`
  - Detail: `https://api.opencorporates.com/v0.4/companies/us_ca/<company_number>?api_token=<key>`
  - Returns: legal name, status, incorporation date, registered agent name/address, registered office, officers (LLC managers/members).
- **CA Secretary of State — Calico API (official):** register at
  [calicodev.sos.ca.gov](https://calicodev.sos.ca.gov), subscribe to the Business Entities product, get a
  subscription key, and swap the URL + `Ocp-Apim-Subscription-Key` header into scenario 03. Free.
- **CA SOS bulk ("Master Unload"):** the full 17M-entity registry as flat files for $100 one-time —
  the cheapest path once you're doing high-volume LLC matching (load it into a database or a Make data store).
- **Lead value:** turns "1234 MAIN ST LLC" into a named registered agent/manager with a mailing address.

## 5. Intent leads — Facebook Lead Ads / web forms (scenario 04)

- **What:** self-declared first-time-buyer and solar-interest prospects — the only *pre-purchase* FTHB source.
- **How:** any tool that can POST JSON to the Make webhook. Payload contract is documented in the
  webhook module's note.
- **Quality:** highest of all sources (score starts at 60) because interest is explicit and TCPA
  consent is captured at the form.

## Expansion sources (see scaling-playbook.md)

- **LA County unincorporated permits:** EPIC-LA (epicla.lacounty.gov) — Accela-based; export/report endpoints.
- **Other incorporated cities:** Long Beach, Pasadena, Santa Monica, Glendale, Burbank each run their own
  permit portals (many are Socrata/Accela — same pattern as scenario 01, just a different CONFIG URL).
- **Skip tracing (phones/emails for public-records leads):** BatchData, Endato, PeopleDataLabs — HTTP module
  after the dedupe step. **Read compliance.md first.**
- **CSLB (Contractors State License Board):** verify/loookup solar contractors — useful for B2B partnerships.
