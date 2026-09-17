# Redmine without MCP — the REST path

For harnesses with no MCP support (pi, and anything else whose core is just
Read/Write/Edit/Bash). Redmine's own REST API covers everything D.A.V.E. needs, over
plain `curl` and nothing else.

**On pi, check first whether you need this.** The `pi-mcp-adapter` extension gives
pi real MCP support for about 200 tokens, which lets you keep the same Redmine MCP
server you use elsewhere — see [INSTALL-PI.md](https://github.com/thesawdawg/agent-skills/blob/main/dave/INSTALL-PI.md). This file is
for when you'd rather not add a third-party extension, or the MCP server isn't
available. See [redmine.md](redmine.md) for the authority model and the approval
gate — **all of that still applies here, unchanged.** This file only replaces the
transport.

## Setup

The REST API is **off by default** in Redmine. An administrator enables it at
*Administration → Settings → API → Enable REST web service*. The user's personal key
is on their account page (*My account → API access key → Show*).

Store it outside the repo and outside `config.json`:

```bash
printf '%s\n' "<api-key>" > ~/.dave/.redmine-key && chmod 600 ~/.dave/.redmine-key
```

`config.json` holds `redmine.base_url` only. **Never write the key into
`config.json`**, never echo it into chat, and never put it in a URL query string
where it lands in shell history and server logs — use the header form below.

```bash
KEY="$(cat ~/.dave/.redmine-key)"
curl -sS -H "X-Redmine-API-Key: $KEY" "$BASE/issues.json?..."
```

## Reading

Open issues assigned to the user — the intake query. Ask only for the ranking
fields; pulling forty full issues to rank them is the context burn that makes
D.A.V.E. forget what you were doing.

```bash
curl -sS -H "X-Redmine-API-Key: $KEY" \
  "$BASE/issues.json?assigned_to_id=me&status_id=open&limit=100&sort=priority:desc,updated_on:desc" \
  | jq -r '.issues[] | "RM-\(.id)\t\(.status.name)\t\(.priority.name)\t\(.due_date // "-")\t\(.subject)"'
```

One issue, with its comment thread — only when the user opens a specific ticket:

```bash
curl -sS -H "X-Redmine-API-Key: $KEY" "$BASE/issues/4471.json?include=journals"
```

`total_count` in the response tells you whether the result was truncated. If it
exceeds what you fetched, page with `offset` rather than silently ranking a partial
list.

## The id lookups that must not be guessed

Writes take **numeric ids**, and they differ per install. Look them up once per
session and cache them in the mission or the session log. Guessing here silently
writes the wrong status to a real ticket.

```bash
curl -sS -H "X-Redmine-API-Key: $KEY" "$BASE/issue_statuses.json" \
  | jq -r '.issue_statuses[] | "\(.id)\t\(.name)"'
curl -sS -H "X-Redmine-API-Key: $KEY" "$BASE/enumerations/time_entry_activities.json" \
  | jq -r '.time_entry_activities[] | "\(.id)\t\(.name)"'
curl -sS -H "X-Redmine-API-Key: $KEY" "$BASE/users/current.json" | jq -r '.user.id'
```

## Writing

**Every rule from [redmine.md](redmine.md) holds.** Show the exact payload with
before/after for each changing field, get an explicit yes for *that* write, one
approval per write, itemize batches, never invent hours.

Build the body in a file rather than inline — it keeps quoting out of the shell and
lets the user read the exact bytes being sent before approving them:

```bash
cat > /tmp/dave-write.json <<'JSON'
{"issue": {"status_id": 3, "notes": "Root cause was the retry wrapper re-entering on 5xx. Fixed in a3f9c21."}}
JSON
```

Show that file's contents, ask, and only then:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X PUT \
  -H "X-Redmine-API-Key: $KEY" -H 'Content-Type: application/json' \
  --data @/tmp/dave-write.json "$BASE/issues/4471.json"
```

A successful `PUT` returns **204 No Content** with an empty body. Time entries:

```bash
cat > /tmp/dave-time.json <<'JSON'
{"time_entry": {"issue_id": 4471, "hours": 2.5, "activity_id": 9, "comments": "traced and fixed the retry double-fire"}}
JSON
curl -sS -w '\n%{http_code}\n' -X POST \
  -H "X-Redmine-API-Key: $KEY" -H 'Content-Type: application/json' \
  --data @/tmp/dave-time.json "$BASE/time_entries.json"
```

`POST /time_entries.json` returns **201** and the created entry.

## Verifying, and failing honestly

`curl` exits 0 on an HTTP 422 — the request reached the server and came back with a
body explaining what it rejected. **Always capture the status code** (`-w '%{http_code}'`
as above) and treat anything outside 200/201/204 as a failure.

On failure: report the code, print the body's `errors` array, and re-read the issue
to state its *actual* current status. Never retry silently, and never report a
success you did not observe.

```bash
jq -r '.errors[]?' /tmp/dave-response.json
```

Common causes: 401 (bad or unset key), 403 (no permission on that project, or a
workflow transition the user's role can't make), 404 (wrong id or the REST API is
off), 422 (a required custom field, or an invalid `status_id` for the current
workflow state — the usual reason a "closed" transition bounces).
