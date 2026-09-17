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

