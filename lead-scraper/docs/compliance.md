# Compliance — read before you dial, text, or mail

This system collects **public records** (permits, assessor data, corporate registrations) and
**consented intent leads**. Collecting is the easy part; *outreach* is where the legal risk lives.
This is a practical checklist, not legal advice — confirm with a lawyer before scaled outreach.

## TCPA (calls & texts) — the big one

- **Do not auto-dial or text any number without prior express written consent.** TCPA statutory
  damages are $500–$1,500 *per call/text*.
- Only scenario 04 leads with `consent_tcpa=true` have consent. Public-records leads
  (scenarios 01–02) have **no consent** — manual, non-autodialed calls to non-DNC numbers only,
  or use direct mail / door knocking instead.
- Form consent language must be explicit, e.g.:
  > "By submitting, I agree to receive calls and text messages (including via automated technology)
  > from [Your Company] about home-buying / solar services at the number provided. Consent is not a
  > condition of purchase. Msg & data rates may apply."
- Since the 2025 FCC one-to-one consent rulemaking saga, buy leads/consent **naming your specific
  company** — reused multi-buyer consent is a lawsuit magnet.

## DNC (Do Not Call)

- Scrub every phone number against the **National DNC Registry** (telemarketing SAN required:
  telemarketing.donotcall.gov) *and* California's rules before cold-calling.
- The sheet's `dnc_checked` column exists for this: only rows marked scrubbed-clean get dialed.
  Automate it in the Phase-2 skip-trace scenario with a DNC-scrub API (e.g. DNC.com, RealValidation).
- Honor internal opt-outs immediately: set `status=dnc` and the export scenario should filter them out.

## CCPA/CPRA (California privacy)

- You are collecting personal information of California residents; if your business meets CCPA
  thresholds you must: publish a privacy policy, honor deletion/opt-out requests, and disclose data
  sources on request.
- Keep the master sheet access-restricted, delete leads on request (sheet + data store + CSV archives),
  and don't sell the data without a "Do Not Sell" mechanism.

## Data-source terms

- **Socrata / open-data portals:** free to use including commercially; use an app token, don't hammer.
- **County assessor portal:** public endpoint; low volume only (this system: 1 call per new lead).
  Assessor data comes with a "not for direct mass-marketing" notice in some counties — LA County
  assessor data is public record; mail solicitation using recorded owner data is standard practice,
  but keep volumes and use reasonable.
- **ATTOM / OpenCorporates:** commercial licenses — follow your plan's caching and resale limits
  (you may generally use data internally for lead gen; you may not resell raw data).
- **No scraping behind logins or CAPTCHAs** and no evading blocks — every source in this system is
  either an official API or a public unauthenticated endpoint.

## Fair housing & solar-marketing rules

- **Fair Housing Act:** never filter, score, or target home-buyer leads by race, religion, national
  origin, familial status, disability, or proxies for them. Score on property/transaction facts only
  (this system's scoring uses price band, occupancy, permit type — keep it that way).
- **California solar consumer protection:** if you sell solar, the CPUC Solar Consumer Protection
  Guide and disclosure requirements apply at the sales stage; keep marketing claims (savings %) substantiated.

## Practical outreach ladder (lowest → highest risk)

1. **Direct mail** to property/mailing addresses — no TCPA exposure, ideal for permit & sale leads.
2. **Door knocking** re-roof permit leads — high conversion, no consent needed.
3. **Manual dialing** non-DNC, skip-traced numbers — allowed but keep call logs.
4. **Auto-dial/SMS** — only `consent_tcpa=true` webhook leads.
