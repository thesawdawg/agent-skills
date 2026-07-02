---
name: rest-graphql-debug
description: Debug REST/GraphQL API failures — status codes, auth, TLS, schema drift, pagination — by isolating the failing layer before guessing at a fix. Use when an API returns an unexpected status or body, auth fails after a token refresh, something works in Postman but fails in code, or you're reviewing/writing API integration tests.
---

# API Testing & Debugging

Drive REST and GraphQL diagnosis with `curl` (via Bash) and Python's `requests` (via Bash). Isolate the failing layer before guessing at the fix.

## When to Use

- API returns unexpected status or body
- Auth fails (401/403 after token refresh, OAuth, API key)
- Works in Postman but fails in code
- Webhook / callback integration debugging
- Building or reviewing API integration tests
- Rate limiting or pagination issues

Skip for UI rendering, DB query tuning, or DNS/firewall infra (escalate).

## Core Principle

**Isolate the layer, then fix.** A 200 OK can hide broken data. A 500 can mask a one-character auth typo. Walk the chain in order; never skip a step.

```
1. Connectivity   → can we reach the host at all?
1.5 Timeouts      → connect-slow vs read-slow?
2. TLS/SSL        → cert valid and trusted?
3. Auth           → credentials correct and unexpired?
4. Request format → payload shape match server expectations?
5. Response parse → does our code accept what came back?
6. Semantics      → does the data mean what we assume?
```

## 5-Minute Quickstart

### REST via curl

```bash
# Verbose request/response exchange
curl -v https://api.example.com/users/1

# POST with JSON
curl -X POST https://api.example.com/users \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"test","email":"test@example.com"}'

# Headers only
curl -sI https://api.example.com/health

# Pretty-print JSON
curl -s https://api.example.com/users | python3 -m json.tool
```

### GraphQL via curl

```bash
curl -X POST https://api.example.com/graphql \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"{ user(id: 1) { name email } }"}'
```

**GraphQL gotcha:** servers often return HTTP 200 even when the query failed. Always inspect the `errors` field regardless of status code:

```python
import os, requests
resp = requests.post(
    "https://api.example.com/graphql",
    json={"query": "{ user(id: 1) { name email } }"},
    headers={"Authorization": f"Bearer {os.environ['TOKEN']}"},
    timeout=10,
)
data = resp.json()
if data.get("errors"):
    for err in data["errors"]:
        print(f"GraphQL error: {err['message']} (path: {err.get('path')})")
print(data.get("data"))
```

Run Python snippets like this with Bash: `python3 -c "..."` for one-liners, or write them to a scratch `.py` file and run `python3 script.py` for anything longer than a few lines.

### Python (requests)

```python
import requests
resp = requests.get(
    "https://api.example.com/users/1",
    headers={"Authorization": "Bearer <TOKEN>"},
    timeout=(3.05, 30),  # (connect, read)
)
print(resp.status_code, dict(resp.headers))
print(resp.text[:500])
```

## Layered Debug Flow

### Step 1 — Connectivity

```bash
nslookup api.example.com
curl -v --connect-timeout 5 https://api.example.com/health
```

Failures: DNS not resolving, firewall, VPN required, proxy missing.

### Step 1.5 — Timeouts

Distinguish *can't reach* from *reaches but slow*:

```bash
curl -w "dns:%{time_namelookup}s connect:%{time_connect}s tls:%{time_appconnect}s ttfb:%{time_starttransfer}s total:%{time_total}s\n" \
  -o /dev/null -s https://api.example.com/endpoint
```

In Python, always pass a tuple timeout — `requests` has no default and will hang forever:

```python
import requests
from requests.exceptions import ConnectTimeout, ReadTimeout
try:
    requests.get(url, timeout=(3.05, 30))
except ConnectTimeout:
    print("Cannot reach host — DNS, firewall, VPN")
except ReadTimeout:
    print("Connected but server is slow")
```

Diagnosis: high `time_connect` is network/firewall; high `time_starttransfer` with low `time_connect` is a slow server.

### Step 2 — TLS/SSL

```bash
curl -vI https://api.example.com 2>&1 | grep -E "SSL|subject|expire|issuer"
```

Failures: expired cert, self-signed, hostname mismatch, missing CA bundle. Use `-k` only for ad-hoc debug, never in code.

### Step 3 — Authentication

```bash
# Token validity check
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" https://api.example.com/me
```

```python
# Decode JWT exp claim — handles base64url padding correctly
import json, base64, os
tok = os.environ["TOKEN"]
payload = tok.split(".")[1]
payload += "=" * (-len(payload) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
```

Checklist:
- Token expired? (`exp` claim in JWT)
- Right scheme? Bearer vs Basic vs Token vs `X-Api-Key`
- Right environment? Staging key on prod is a classic
- API key in header vs query param (`?api_key=…`)?

### Step 4 — Request Format

```bash
curl -v -X POST https://api.example.com/endpoint \
  -H 'Content-Type: application/json' \
  -d '{"key":"value"}' 2>&1
```

**Content-Type / body mismatch — the silent 415/400:**

```python
# WRONG — data= sends form-encoded, header lies
requests.post(url, data='{"k":"v"}', headers={"Content-Type": "application/json"})

# RIGHT — json= auto-sets header AND serializes
requests.post(url, json={"k": "v"})

# WRONG — Accept says XML, code calls .json()
requests.get(url, headers={"Accept": "text/xml"})

# RIGHT — let requests build multipart with boundary, and close the file
# handle deterministically instead of leaving it to the garbage collector
with open("doc.pdf", "rb") as file_obj:
    requests.post(url, files={"file": file_obj}, timeout=30)
```

Common: form-encoded vs JSON, missing required fields, wrong HTTP method, unencoded query params.

### Step 5 — Response Parsing

Always inspect content-type before calling `.json()`:

```python
import requests
resp = requests.post(url, json=payload, timeout=10)
print(f"status={resp.status_code}")
print(f"headers={dict(resp.headers)}")
ct = resp.headers.get("Content-Type", "")
if "application/json" in ct:
    print(resp.json())
else:
    print(f"unexpected content-type {ct!r}, body={resp.text[:500]!r}")
```

Failures: HTML error page where JSON expected, empty body, wrong charset.

### Step 6 — Semantic Validation

Parsed cleanly — but is the data *correct*?

- Does `"status": "active"` mean what your code thinks?
- ID in response matches the one requested?
- Timestamps in expected timezone?
- Pagination returning all results, or just page 1?

## HTTP Status Playbook

### 401 Unauthorized — credentials missing or invalid

1. `Authorization` header actually present? (`curl -v` to confirm)
2. Token correct and unexpired?
3. Right auth scheme? (`Bearer` vs `Basic` vs `Token`)
4. Some APIs use query param (`?api_key=…`) instead of header.

### 403 Forbidden — authenticated but not authorized

1. Token has the required scopes/permissions?
2. Resource owned by a different account?
3. IP allowlist blocking you?
4. CORS in browser? (check `Access-Control-Allow-Origin`)

### 404 Not Found — resource doesn't exist or URL is wrong

1. Path correct? (trailing slash, typo, version prefix)
2. Resource ID exists?
3. Right API version (`/v1/` vs `/v2/`)?
4. Right base URL (staging vs prod)?

### 409 Conflict — state collision

1. Resource already exists (duplicate create)?
2. Stale `ETag` / `If-Match`?
3. Concurrent modification by another process?

### 422 Unprocessable Entity — valid JSON, invalid data

The error body usually names the bad fields. Check:
- Field types (string vs int, date format)
- Required vs optional
- Enum values inside the allowed set

### 429 Too Many Requests — rate limited

Check `Retry-After` and `X-RateLimit-*` headers. Exponential backoff with jitter:

**Only auto-retry idempotent methods (`GET`/`HEAD`/`PUT`/`DELETE`), or a `POST`/`PATCH` that carries a provider-supported idempotency key** (see "Pagination & Idempotency" below) — retrying a plain `POST` blind can double-create or double-charge.

```python
import email.utils
import random
import time

import requests


def _retry_after_seconds(resp: requests.Response, attempt: int) -> float:
    """Retry-After is either an integer number of seconds or an HTTP-date."""
    header = resp.headers.get("Retry-After")
    if header is None:
        base = 2**attempt
    elif header.strip().isdigit():
        base = int(header)
    else:
        try:
            when = email.utils.parsedate_to_datetime(header)
            base = max((when - email.utils.parsedate_to_datetime(resp.headers.get("Date", ""))).total_seconds(), 0)
        except (TypeError, ValueError):
            base = 2**attempt
    # Full jitter: spreads out retries from many clients instead of
    # thundering-herding back at the same instant.
    return random.uniform(0, base)


def with_backoff(method, url, *, max_attempts=5, **kwargs):
    resp = None
    for attempt in range(max_attempts):
        try:
            resp = requests.request(method, url, timeout=kwargs.pop("timeout", (3.05, 30)), **kwargs)
        except (requests.ConnectTimeout, requests.ConnectionError):
            if attempt == max_attempts - 1:
                raise
            time.sleep(random.uniform(0, 2**attempt))
            continue
        if resp.status_code != 429:
            return resp
        time.sleep(_retry_after_seconds(resp, attempt))
    return resp
```

### 5xx — server-side, usually not your fault

- **500** — server bug. Capture correlation ID, file with provider.
- **502** — upstream down. Backoff + retry.
- **503** — overloaded / maintenance. Check status page.
- **504** — upstream timeout. Reduce payload or raise timeout.

For all 5xx: backoff with jitter, alert on persistence.

## Pagination & Idempotency

**Pagination.** Verify you're getting *all* results. Look for `next_cursor`, `next_page`, `total_count`. Two patterns:
- Offset (`?limit=100&offset=200`) — simple, can skip items if data shifts.
- Cursor (`?cursor=abc123`) — preferred for live or large datasets.

**Idempotency.** For non-idempotent operations (POST), send `Idempotency-Key: <uuid>` so retries don't double-charge / double-create. Mandatory for payments and orders.

## Contract Validation

Catch schema drift before it hits production:

```python
import requests

def validate_user(data: dict) -> list[str]:
    errors = []
    required = {"id": int, "email": str, "created_at": str}
    for field, expected in required.items():
        if field not in data:
            errors.append(f"missing field: {field}")
        elif not isinstance(data[field], expected):
            errors.append(f"{field}: want {expected.__name__}, got {type(data[field]).__name__}")
    return errors

resp = requests.get(f"{BASE}/users/1", headers=HEADERS, timeout=10)
issues = validate_user(resp.json())
if issues:
    print(f"contract violations: {issues}")
```

Run after API upgrades, when integrating new third parties, or in CI smoke tests.

## Correlation IDs

Always capture the provider's request ID — fastest path to vendor support:

```python
import requests
resp = requests.post(url, json=payload, headers=headers, timeout=10)
request_id = (
    resp.headers.get("X-Request-Id")
    or resp.headers.get("X-Trace-Id")
    or resp.headers.get("CF-Ray")  # Cloudflare
)
if resp.status_code >= 400:
    print(f"failed status={resp.status_code} req_id={request_id} ts={resp.headers.get('Date')}")
```

**Vendor bug-report template:**

```
Endpoint:    POST /api/v1/orders
Request ID:  req_abc123xyz
Timestamp:   2026-03-17T14:30:00Z
Status:      500
Expected:    201 with order object
Actual:      500 {"error":"internal server error"}
Repro:       curl -X POST … (auth: <REDACTED>)
```

## Regression Test Template

Drop this into `tests/` and run via `pytest tests/test_api_smoke.py -v`:

```python
import os, requests, pytest

BASE_URL = os.environ.get("API_BASE_URL", "https://api.example.com")
TOKEN    = os.environ.get("API_TOKEN", "")
HEADERS  = {"Authorization": f"Bearer {TOKEN}"}

class TestAPISmoke:
    def test_health(self):
        resp = requests.get(f"{BASE_URL}/health", timeout=5)
        assert resp.status_code == 200

    def test_list_users_returns_array(self):
        resp = requests.get(f"{BASE_URL}/users", headers=HEADERS, timeout=10)
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data.get("data", data), list)

    def test_get_user_required_fields(self):
        resp = requests.get(f"{BASE_URL}/users/1", headers=HEADERS, timeout=10)
        assert resp.status_code in (200, 404)
        if resp.status_code == 200:
            user = resp.json()
            assert "id" in user and "email" in user

    def test_invalid_auth_returns_401(self):
        resp = requests.get(
            f"{BASE_URL}/users",
            headers={"Authorization": "Bearer invalid-token"},
            timeout=10,
        )
        assert resp.status_code == 401
```

## Security

### Token handling
- Never log full tokens. Redact: `Bearer <REDACTED>`.
- Never hardcode tokens in scripts. Read from env (`os.environ["API_TOKEN"]`).
- Rotate immediately if a token surfaces in logs, error messages, or git history.

### Safe logging

```python
def redact_auth(headers: dict) -> dict:
    sensitive = {"authorization", "x-api-key", "cookie", "set-cookie"}
    return {k: ("<REDACTED>" if k.lower() in sensitive else v) for k, v in headers.items()}
```

### Leak checklist

- [ ] **Credentials in URLs.** API keys in query strings end up in server logs, browser history, referrer headers — use headers.
- [ ] **PII in error responses.** `404 on /users/123` shouldn't reveal whether the user exists (enumeration).
- [ ] **Stack traces in prod.** 500s shouldn't leak file paths, framework versions.
- [ ] **Internal hostnames/IPs.** `10.x.x.x`, `internal-api.corp.local` in error bodies.
- [ ] **Tokens echoed back.** Some APIs include the auth token in error details. Verify they don't.
- [ ] **Verbose `Server` / `X-Powered-By`.** Stack-info leaks. Note for security review.

## Tool Notes (core four tools only)

Everything here runs with **Bash** — no harness-specific web or delegation tool is required.

- **curl / openssl / dig** — run directly via Bash.
  ```bash
  curl -sI https://api.example.com
  openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null 2>/dev/null | openssl x509 -noout -dates
  ```
- **Multi-step Python flows** (auth → fetch → paginate → validate) — Write the script to a scratch `.py` file and run it with Bash rather than chaining long inline `-c` strings; keeps token handling out of shell history.
- **Vendor API docs** — fetch the doc page with `curl` instead of guessing at the spec, then read it:
  ```bash
  curl -sSL "https://docs.example.com/api/v1/users" -o /tmp/apidoc.html
  # then Read /tmp/apidoc.html, or pipe through a text extractor:
  #   python3 -c "import sys,re,html; t=open('/tmp/apidoc.html').read(); print(re.sub('<[^>]+>',' ',t))" | head -200
  ```
  If your harness has a richer web-fetch or browser capability, use that instead — but plain `curl` is the portable baseline.
- **Full CRUD test sweeps across many endpoints** — if your harness supports subagent delegation, hand off the sweep with full context inlined (auth scheme, base URL, what to test per endpoint) and have it report pass/fail + correlation IDs. If not, write the sweep as one `.py` or shell script and run it in a single pass. Either way, don't make the worker re-read this whole skill file.

## Output Format

When reporting findings:

```
## Finding
Endpoint: POST /api/v1/users
Status:   422 Unprocessable Entity
Req ID:   req_abc123xyz

## Repro
curl -X POST https://api.example.com/api/v1/users \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <REDACTED>' \
  -d '{"name":"test"}'

## Root Cause
Missing required field `email`. Server validation rejects before processing.

## Fix
-d '{"name":"test","email":"test@example.com"}'
```
