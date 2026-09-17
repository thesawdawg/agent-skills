---
name: rest-graphql-debug
description: Debug REST/GraphQL API failures — status codes, auth, TLS, schema drift, pagination — by isolating the failing layer before guessing at a fix. Use when an API returns an unexpected status or body, auth fails after a token refresh, something works in Postman but fails in code, or you're reviewing/writing API integration tests.
---

# REST and GraphQL debugging

Diagnose the smallest reproducible failing request. Confirm target, expected
behavior, credentials source, and whether state-changing requests are authorized.
Use an available HTTP tool or shell with curl. Python examples require the
optional `requests` package; check before use and prefer curl if unavailable.
Do not install dependencies into the user's environment implicitly.

1. Capture the failing request, status, headers, request ID, and sanitized body.
2. Work outward-in: connectivity → timeouts → TLS → authentication → request
   format → response parsing → business semantics. Change one variable at a time.
3. For GraphQL, inspect `errors` even on HTTP 200. A transport success does not
   establish a successful operation.
4. Reproduce a fix and verify failure cases, pagination, or idempotency where
   relevant. Do not retry state-changing requests without establishing safety.
5. Report observed vs expected behavior, sanitized repro, root cause confidence,
   proposed fix, and tests run/not run. Never expose credentials in logs or chat.

Read only the relevant lookup:

- [Quickstart](references/quickstart.md): curl and optional Python examples.
- [Layered diagnosis](references/layers.md): connectivity through semantics.
- [Status playbook](references/status.md): 401/403/404/409/422/429/5xx.
- [Contracts and regression](references/contracts.md): pagination, schemas,
  correlation IDs, and test examples.
- [Credential handling](references/security.md): read before handling secrets.

Use explicit timeouts. Redact tokens, cookies, personal data, and secrets from
all shared evidence. Preserve TLS validation; diagnostic bypasses do not count
as a production fix.
