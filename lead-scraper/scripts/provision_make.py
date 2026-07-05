#!/usr/bin/env python3
"""
One-command provisioning for the NetNest LA County Lead Scraper on Make.com.

Creates in YOUR Make account, via the official Make API:
  1. The "LA Lead Record" data structure
  2. The "LA Leads Master" data store (deduplication)
  3. All 5 scenarios from ../make-blueprints/, with the data store ID
     pre-wired into every data-store module

Usage:
  1. In Make: click your avatar (bottom-left) -> Profile -> API tab ->
     "Add token". Enable at least these scopes:
       scenarios:read  scenarios:write
       datastores:read datastores:write
       udts:read       udts:write          (data structures)
       teams:read      organizations:read
  2. Note your zone from your Make URL: https://<zone>.make.com (us1, us2, eu1, eu2)
  3. Run:
       python3 provision_make.py --token YOUR_API_TOKEN --zone us1
     Optional: --team <teamId>   (auto-detected if you have exactly one team)
               --dry-run          (show what would be created, create nothing)

Python 3.8+, standard library only. Run it from your own computer
(the token stays between you and make.com).

What remains manual afterwards (Make security requires clicks in YOUR browser, ~5 min):
  - Attach your Google connection in the Sheets/Drive/Email modules
    and pick your "LA Leads Master" spreadsheet
  - Create the webhook in scenario 04 and copy its URL
  - Paste API keys (Socrata/ATTOM/OpenCorporates) into each CONFIG module
  - Turn each scenario ON
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

BLUEPRINT_DIR = Path(__file__).resolve().parent.parent / "make-blueprints"
TEMPLATE_DIR = Path(__file__).resolve().parent.parent / "templates"

SCHEDULING = {
    "01": {"type": "daily", "time": "07:00"},
    "02": {"type": "daily", "time": "07:30"},
    "03": {"type": "indefinitely", "interval": 3600},
    "04": {"type": "indefinitely", "interval": 900},
    "05": {"type": "weekly", "days": [1], "time": "08:00"},
}


class MakeAPI:
    def __init__(self, zone: str, token: str):
        self.base = f"https://{zone}.make.com/api/v2"
        self.token = token

    def call(self, method: str, path: str, body: Optional[dict] = None) -> dict:
        req = urllib.request.Request(
            f"{self.base}{path}",
            method=method,
            headers={
                "Authorization": f"Token {self.token}",
                "Content-Type": "application/json",
            },
            data=json.dumps(body).encode() if body is not None else None,
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise SystemExit(
                f"\nMake API error {e.code} on {method} {path}:\n{detail}\n"
                "Check your token scopes (see header of this script) and zone."
            )


def main() -> None:
    ap = argparse.ArgumentParser(description="Provision NetNest lead scraper into Make.com")
    ap.add_argument("--token", required=True, help="Make API token")
    ap.add_argument("--zone", default="us1", help="Make zone: us1, us2, eu1, eu2 (default us1)")
    ap.add_argument("--team", type=int, default=None, help="Team ID (auto-detected if omitted)")
    ap.add_argument("--dry-run", action="store_true", help="Show plan, create nothing")
    args = ap.parse_args()

    api = MakeAPI(args.zone, args.token)

    # ── 0. Validate token & find team ────────────────────────────────────
    me = api.call("GET", "/users/me")
    print(f"✔ Authenticated as: {me.get('authUser', {}).get('email', 'unknown')}")

    team_id = args.team
    if team_id is None:
        orgs = api.call("GET", "/organizations").get("organizations", [])
        if not orgs:
            raise SystemExit("No organizations visible to this token — add organizations:read scope.")
        teams = api.call("GET", f"/teams?organizationId={orgs[0]['id']}").get("teams", [])
        if not teams:
            raise SystemExit("No teams found — pass --team explicitly.")
        team_id = teams[0]["id"]
        print(f"✔ Using team: {teams[0].get('name', team_id)} (id {team_id})")

    if args.dry_run:
        print("\nDRY RUN — would create: 1 data structure, 1 data store, 5 scenarios. Exiting.")
        return

    # ── 1. Data structure ────────────────────────────────────────────────
    ds_schema = json.loads((TEMPLATE_DIR / "make-data-store-schema.json").read_text())
    spec = ds_schema["datastructure"]["spec"]
    structure = api.call(
        "POST",
        "/data-structures",
        {"name": ds_schema["datastructure"]["name"], "teamId": team_id, "spec": spec, "strict": False},
    )
    structure_id = structure.get("dataStructure", structure).get("id")
    print(f"✔ Data structure created (id {structure_id})")

    # ── 2. Data store ────────────────────────────────────────────────────
    store = api.call(
        "POST",
        "/data-stores",
        {
            "name": ds_schema["name"],
            "teamId": team_id,
            "datastructureId": structure_id,
            "maxSizeMB": ds_schema.get("maxSizeMB", 10),
        },
    )
    store_id = store.get("dataStore", store).get("id")
    print(f"✔ Data store '{ds_schema['name']}' created (id {store_id})")

    # ── 3. Scenarios ─────────────────────────────────────────────────────
    created = []
    for bp_file in sorted(BLUEPRINT_DIR.glob("*.blueprint.json")):
        bp = json.loads(bp_file.read_text())

        # Pre-wire the data store into every datastore module so you
        # don't have to select it by hand after import.
        def wire(modules: list) -> None:
            for m in modules:
                if str(m.get("module", "")).startswith("datastore:"):
                    m.setdefault("parameters", {})["datastore"] = store_id
                for route in m.get("routes", []) or []:
                    wire(route.get("flow", []) or [])

        wire(bp.get("flow", []))

        sched = SCHEDULING.get(bp_file.name[:2], {"type": "indefinitely", "interval": 900})
        scenario = api.call(
            "POST",
            "/scenarios",
            {
                "blueprint": json.dumps(bp),
                "teamId": team_id,
                "scheduling": json.dumps(sched),
            },
        )
        sid = scenario.get("scenario", scenario).get("id")
        created.append((sid, bp["name"]))
        print(f"✔ Scenario created (id {sid}): {bp['name']}")

    # ── 4. What's left for you ───────────────────────────────────────────
    print(f"""
────────────────────────────────────────────────────────────────────
DONE — {len(created)} scenarios + data store are now in your Make account.

Finish in your browser at https://{args.zone}.make.com (≈5 minutes):
  1. Create a Google Sheet 'LA Leads Master' (tab 'Leads') and paste the
     header row from templates/leads-master-schema.csv.
  2. Open each scenario -> click Google Sheets/Drive/Email modules ->
     'Add' connection -> sign in -> pick your spreadsheet.
  3. Scenario 04: click the webhook module -> Create a webhook -> copy
     the URL into your ad/form tools.
  4. Paste API keys into each scenario's first module (CONFIG — edit me):
     Socrata (free), ATTOM (free trial), OpenCorporates (free tier).
  5. Run each scenario once (Run once), then flip it ON.

Tip: revoke or rotate this API token in Make -> Profile -> API when done.
────────────────────────────────────────────────────────────────────""")


if __name__ == "__main__":
    if sys.version_info < (3, 8):
        raise SystemExit("Python 3.8+ required")
    main()
