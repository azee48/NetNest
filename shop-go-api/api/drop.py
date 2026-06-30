"""
Vercel serverless endpoint: returns RTN lottery Money Drop.
Supports single-shift (default) and cumulative multi-shift modes.

Params:
  ?key=...              required auth key
  &cumulative=true      sum all today's RTN shifts
  &shifts=N             how many shifts to include in cumulative (1/2/3)

Env vars: LOTTERY_EMAIL, LOTTERY_PASSWORD, LOTTERY_SENDER, DROP_KEY
"""
from http.server import BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import os, re, zlib, json, imaplib, email
from email import policy
from datetime import date


def _pdf_text(pdf_bytes):
    out = []
    for m in re.finditer(rb"stream\r?\n(.*?)endstream", pdf_bytes, re.S):
        c = m.group(1)
        try:
            c = zlib.decompress(c)
        except Exception:
            pass
        for t in re.findall(rb"\((.*?)\)\s*Tj", c):
            out.append(t.decode("latin-1", "ignore"))
        for arr in re.findall(rb"\[(.*?)\]\s*TJ", c, re.S):
            parts = re.findall(rb"\((.*?)\)", arr)
            out.append("".join(p.decode("latin-1", "ignore") for p in parts))
    return "\n".join(out)


def _grab(text, label):
    m = re.search(re.escape(label) + r"\s*:?\s*\\?\(?\s*\$?\s*(-?[\d,]+\.\d{2})", text)
    return float(m.group(1).replace(",", "")) if m else None


def _parse_msg(msg):
    subject = msg.get("Subject", "")
    pdf = None
    for part in msg.walk():
        fn = part.get_filename()
        if fn and fn.lower().endswith(".pdf"):
            pdf = part.get_payload(decode=True)
            break
    if not pdf:
        return None
    text = _pdf_text(pdf)
    shift = None
    ms = re.search(r"Shift#\s*:?\s*Shift\s*(\d+)", text)
    if ms:
        shift = int(ms.group(1))
    close = None
    mc = re.search(r"Close Date\s*:?\s*([\d\-]+\s+[\d:apmAPM]+)", text)
    if mc:
        close = mc.group(1)
    return {
        "shift": shift,
        "close": close,
        "money_drop": _grab(text, "Money Drop"),
        "instant_sales": _grab(text, "Instant Sales"),
        "online_sales": _grab(text, "Online Sales"),
        "instant_cashout": _grab(text, "Instant CashOut"),
        "online_cashout": _grab(text, "Online CashOut"),
        "subject": subject,
    }


def _connect():
    M = imaplib.IMAP4_SSL("imap.gmail.com")
    M.login(os.environ["LOTTERY_EMAIL"], os.environ["LOTTERY_PASSWORD"])
    M.select("INBOX")
    return M


def _latest():
    M = _connect()
    sender = os.environ.get("LOTTERY_SENDER", "admin@realtnetworking.com")
    _, data = M.search(None, f'(FROM "{sender}")')
    ids = data[0].split()
    if not ids:
        M.logout()
        return {"error": "no RTN emails found"}
    _, msgdata = M.fetch(ids[-1], "(RFC822)")
    M.logout()
    msg = email.message_from_bytes(msgdata[0][1], policy=policy.default)
    result = _parse_msg(msg)
    return result or {"error": "no PDF in latest email", "subject": msg.get("Subject", "")}


def _is_today_eastern(msg_obj):
    """Return True if the email's Date header falls on today in Eastern time."""
    from datetime import datetime, timezone, timedelta
    import email.utils as eutils
    ET = timezone(timedelta(hours=-4))  # EDT; close enough year-round for this use
    try:
        ts = eutils.parsedate_to_datetime(msg_obj.get("Date", ""))
        return ts.astimezone(ET).date() == datetime.now(ET).date()
    except Exception:
        return False


def _cumulative(shifts_needed):
    """Grab the last 10 RTN emails, keep only today's (Eastern time), sum drops."""
    M = _connect()
    sender = os.environ.get("LOTTERY_SENDER", "admin@realtnetworking.com")
    _, data = M.search(None, f'(FROM "{sender}")')
    ids = data[0].split()
    # Look at most recent 10 emails — today's shifts will always be in there
    recent_ids = ids[-10:] if len(ids) >= 10 else ids
    parsed = []
    for uid in recent_ids:
        _, msgdata = M.fetch(uid, "(RFC822)")
        raw_msg = email.message_from_bytes(msgdata[0][1], policy=policy.default)
        if not _is_today_eastern(raw_msg):
            continue
        result = _parse_msg(raw_msg)
        if result and result.get("money_drop") is not None:
            parsed.append(result)
    M.logout()
    if not parsed:
        return {"error": "no RTN emails found for today — if the shift just closed, wait 1 minute and try again"}
    parsed.sort(key=lambda x: x.get("shift") or 0)
    take = parsed[:shifts_needed]
    total_drop = sum(s.get("money_drop") or 0 for s in take)
    return {
        "shift": shifts_needed,
        "close": take[-1].get("close") if take else None,
        "money_drop": total_drop,
        "cumulative": True,
        "shifts_included": [s.get("shift") for s in take],
        "shift_drops": [{"shift": s.get("shift"), "drop": s.get("money_drop")} for s in take],
        "subject": f"Cumulative {len(take)} of {len(parsed)} shifts today",
    }


def _debug_info():
    """Return diagnostic info: server UTC time, Eastern time, and last 5 RTN email dates."""
    from datetime import datetime, timezone, timedelta
    import email.utils as eutils
    ET = timezone(timedelta(hours=-4))
    now_utc = datetime.now(timezone.utc)
    now_et = datetime.now(ET)
    M = _connect()
    sender = os.environ.get("LOTTERY_SENDER", "admin@realtnetworking.com")
    _, data = M.search(None, f'(FROM "{sender}")')
    ids = data[0].split()
    recent = ids[-5:] if len(ids) >= 5 else ids
    emails = []
    for uid in recent:
        _, msgdata = M.fetch(uid, "(RFC822)")
        msg = email.message_from_bytes(msgdata[0][1], policy=policy.default)
        date_hdr = msg.get("Date", "")
        subject = msg.get("Subject", "")
        try:
            ts = eutils.parsedate_to_datetime(date_hdr)
            ts_et = ts.astimezone(ET)
            is_today = ts_et.date() == now_et.date()
        except Exception as ex:
            ts_et = None
            is_today = f"parse_error: {ex}"
        emails.append({
            "subject": subject,
            "date_header": date_hdr,
            "date_eastern": str(ts_et) if ts_et else None,
            "is_today_eastern": is_today,
        })
    M.logout()
    return {
        "server_utc": str(now_utc),
        "server_eastern": str(now_et),
        "today_eastern": str(now_et.date()),
        "rtn_email_count": len(ids),
        "last_5_emails": emails,
    }


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
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.end_headers()

    def do_GET(self):
        qs = parse_qs(urlparse(self.path).query)
        key = (qs.get("key") or [""])[0]
        if key != os.environ.get("DROP_KEY", ""):
            self._send(403, {"error": "forbidden"})
            return
        cumulative = (qs.get("cumulative") or [""])[0].lower() == "true"
        debug = (qs.get("debug") or [""])[0].lower() == "true"
        shifts_needed = int((qs.get("shifts") or ["1"])[0])
        try:
            if debug:
                self._send(200, _debug_info())
            elif cumulative:
                self._send(200, _cumulative(shifts_needed if shifts_needed > 0 else 99))
            else:
                self._send(200, _latest())
        except Exception as e:
            self._send(500, {"error": str(e)})
