"""
Vercel endpoint: receives a saved shift closeout (POST JSON) and emails it to
the owner + brother. Protected by the same DROP_KEY.

Env vars (Vercel): SENDER_EMAIL, SENDER_PASSWORD, REPORT_RECIPIENTS, DROP_KEY
"""
from http.server import BaseHTTPRequestHandler
import os
import json
import ssl
import smtplib
from email.mime.text import MIMEText


def _money(x):
    try:
        return "${:,.2f}".format(float(x or 0))
    except (TypeError, ValueError):
        return "$0.00"


def _build_body(d):
    diff = float(d.get("diff") or 0)
    if abs(diff) < 0.005:
        status = "BALANCED"
    elif diff > 0:
        status = "OVER by " + _money(diff)
    else:
        status = "SHORT by " + _money(-diff)

    L = []
    L.append("SHOP & GO — SHIFT CLOSEOUT")
    L.append(f"{d.get('date','')}   {d.get('shift','')} shift   closed by {d.get('who','') or '(no name)'}")
    L.append("=" * 44)
    final_flag = " [FINAL — cumulative]" if d.get("finalshift") == "yes" else ""
    L.append(f"Net sale:              {_money(d.get('netsale'))}")
    L.append(f"- Lottery on register: {_money(d.get('lottoreg'))}")
    L.append(f"- Debit card:          {_money(d.get('debit'))}")
    L.append(f"- Credit card:         {_money(d.get('credit'))}")
    L.append(f"  = Total card:        {_money(d.get('card'))}")
    L.append(f"+ Lottery drop{final_flag}: {_money(d.get('moneydrop'))}")
    # payout lines with notes
    for i in (1, 2, 3, 4, 5, 6, 7, 8):
        amt = d.get(f"payamt{i}")
        note = d.get(f"paynote{i}")
        if amt or note:
            L.append(f"- Cash payout: {_money(amt)}  ({note or 'no note'})")
    nc_total = sum(float(d.get(f"ncamt{i}") or 0) for i in (1,2,3,4))
    if nc_total > 0:
        L.append(f"Non-cash payouts:      {_money(nc_total)}")
        for i in (1, 2, 3, 4):
            amt = d.get(f"ncamt{i}")
            note = d.get(f"ncnote{i}")
            if amt or note:
                L.append(f"- Non-cash: {_money(amt)}  ({note or 'no note'})")
    L.append(f"Opening float:         {_money(d.get('float'))}")
    L.append(f"Drop (counted):        {_money(d.get('counted'))}")
    L.append("-" * 44)
    L.append(f"Cash should have:      {_money(d.get('expected'))}")
    L.append(f">>> {status} <<<")
    if diff < -0.005:
        L.append("")
        L.append("SHORT — recount, then follow up.")
    return "\n".join(L)


class handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            d = json.loads(self.rfile.read(length) or b"{}")
        except Exception as e:
            self._send(400, {"error": "bad json: " + str(e)})
            return
        if d.get("key") != os.environ.get("DROP_KEY", ""):
            self._send(403, {"error": "forbidden"})
            return
        recipients = [r.strip() for r in os.environ.get(
            "REPORT_RECIPIENTS",
            "nawazaarib@gmail.com,saribnawaz0@gmail.com").split(",") if r.strip()]
        try:
            msg = MIMEText(_build_body(d))
            diff = float(d.get("diff") or 0)
            tag = "BALANCED" if abs(diff) < 0.005 else ("OVER " + _money(diff) if diff > 0 else "SHORT " + _money(-diff))
            final_label = " · FINAL" if d.get("finalshift") == "yes" else ""
    msg["Subject"] = f"Closeout {d.get('date','')} {d.get('shift','')}{final_label} — {tag}"
            msg["From"] = os.environ["SENDER_EMAIL"]
            msg["To"] = ", ".join(recipients)
            ctx = ssl.create_default_context()
            with smtplib.SMTP("smtp.gmail.com", 587) as s:
                s.ehlo()
                s.starttls(context=ctx)
                s.login(os.environ["SENDER_EMAIL"], os.environ["SENDER_PASSWORD"])
                s.sendmail(os.environ["SENDER_EMAIL"], recipients, msg.as_string())
            self._send(200, {"ok": True, "sent_to": recipients})
        except Exception as e:
            self._send(500, {"error": str(e)})
