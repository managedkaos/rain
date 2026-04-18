import os
import json
import base64
import hashlib
import hmac
import secrets
import html
import urllib.request
import urllib.parse

CLIENT_ID = os.environ["CLIENT_ID"]
COGNITO_DOMAIN = os.environ["COGNITO_DOMAIN"]
REDIRECT_URI = os.environ["REDIRECT_URI"]
SECRET_KEY = os.environ["SECRET_KEY"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "")
VERSION = os.environ.get("VERSION", "")
PLATFORM = os.environ.get("PLATFORM", "")
BUILD_NUMBER = os.environ.get("BUILD_NUMBER", "")

_template_path = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "template.html"
)
with open(_template_path) as _f:
    TEMPLATE = _f.read()


def _parse_cookies(event):
    cookies = {}
    for c in event.get("cookies", []):
        if "=" in c:
            k, v = c.split("=", 1)
            cookies[k.strip()] = v.strip()
    hdrs = event.get("headers") or {}
    cookie_hdr = hdrs.get("cookie") or hdrs.get("Cookie")
    if cookie_hdr:
        for part in cookie_hdr.split(";"):
            part = part.strip()
            if "=" in part:
                k, v = part.split("=", 1)
                cookies[k.strip()] = v.strip()
    return cookies


def _b64url_encode(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def _b64url_decode(s):
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def _sign_session(data):
    raw = json.dumps(data, separators=(",", ":"), sort_keys=True).encode()
    payload = _b64url_encode(raw)
    sig = hmac.new(SECRET_KEY.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"


def _verify_session(value):
    try:
        payload, sig = value.rsplit(".", 1)
        expected = hmac.new(
            SECRET_KEY.encode(), payload.encode(), hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(sig, expected):
            return None
        return json.loads(_b64url_decode(payload))
    except Exception:
        return None


def _normalize_path(event):
    raw = event.get("rawPath", "/") or "/"
    segs = [s for s in raw.split("/") if s]
    return "/" + "/".join(segs) if segs else "/"


def handler(event, context):
    path = _normalize_path(event)
    cookies = _parse_cookies(event)
    user = _verify_session(cookies["session"]) if "session" in cookies else None

    if path == "/login":
        verifier = secrets.token_urlsafe(32)
        challenge = (
            base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
            .decode()
            .rstrip("=")
        )
        auth_url = (
            f"https://{COGNITO_DOMAIN}/oauth2/authorize?"
            + urllib.parse.urlencode(
                {
                    "client_id": CLIENT_ID,
                    "response_type": "code",
                    "scope": "openid email profile",
                    "redirect_uri": REDIRECT_URI,
                    "code_challenge": challenge,
                    "code_challenge_method": "S256",
                }
            )
        )
        return {
            "statusCode": 302,
            "headers": {"Location": auth_url},
            "cookies": [
                f"pkce={verifier}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=300"
            ],
        }

    if path == "/authorize":
        params = event.get("queryStringParameters", {}) or {}
        code = params.get("code")
        if not code:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "text/html"},
                "body": '<p>Missing authorization code. <a href="/">Home</a></p>',
            }
        token_body = urllib.parse.urlencode(
            {
                "grant_type": "authorization_code",
                "client_id": CLIENT_ID,
                "code": code,
                "redirect_uri": REDIRECT_URI,
                "code_verifier": cookies.get("pkce", ""),
            }
        ).encode()
        req = urllib.request.Request(
            f"https://{COGNITO_DOMAIN}/oauth2/token",
            data=token_body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            resp = urllib.request.urlopen(req)
            tokens = json.loads(resp.read())
        except Exception:
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "text/html"},
                "body": '<p>Authentication failed. <a href="/">Try again</a></p>',
            }
        id_payload = tokens["id_token"].split(".")[1]
        id_payload += "=" * (-len(id_payload) % 4)
        user_info = json.loads(base64.b64decode(id_payload))
        session_val = _sign_session({"email": user_info.get("email", "unknown")})
        return {
            "statusCode": 302,
            "headers": {"Location": "/"},
            "cookies": [
                f"session={session_val}; Path=/; HttpOnly; Secure; SameSite=Lax",
                "pkce=; Path=/; HttpOnly; Secure; Max-Age=0",
            ],
        }

    if path == "/logout":
        pu = urllib.parse.urlparse(REDIRECT_URI)
        logout_uri = f"{pu.scheme}://{pu.netloc}/"
        logout_url = f"https://{COGNITO_DOMAIN}/logout?" + urllib.parse.urlencode(
            {"client_id": CLIENT_ID, "logout_uri": logout_uri}
        )
        return {
            "statusCode": 302,
            "headers": {"Location": logout_url},
            "cookies": ["session=; Path=/; HttpOnly; Secure; Max-Age=0"],
        }

    if user:
        email = html.escape(user.get("email", "unknown"))
        content = f'Hello, {email}! <a href="/logout">Logout</a>'
    else:
        content = 'Welcome! Please <a href="/login">Login</a>.'

    page = TEMPLATE.format(
        content=content,
        environment=ENVIRONMENT,
        version=VERSION,
        platform=PLATFORM,
        build_number=BUILD_NUMBER,
    )
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": page,
    }
