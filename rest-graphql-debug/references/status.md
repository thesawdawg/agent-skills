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

