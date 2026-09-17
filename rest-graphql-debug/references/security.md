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

