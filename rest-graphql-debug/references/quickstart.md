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

