# Local App Setup for Runtime Testing

> Referenced from [SKILL.md](../SKILL.md) and [app-design's test battery](https://github.com/thesawdawg/agent-skills/blob/main/app-design/references/test-battery.md).

Safe pattern for standing up a local app so it can be exercised (by `dogfood`'s browser driver, or by `curl` for APIs) without corrupting real data or leaving orphaned processes behind.

## The pattern

1. **Use a throwaway datastore.** Point the app at a fresh/ephemeral DB — a `.env.test` override, an in-memory or tmp-file SQLite DB, a disposable Docker container, or a seeded test schema. Never point runtime QA at a database that holds real user data.
2. **Start the server in the background.** Launch it with `run_in_background: true` so it doesn't block the rest of the session, and keep the port fixed so later commands can target it.
3. **Wait for readiness, don't guess.** Poll the health/root endpoint until it responds instead of sleeping a fixed duration:
   ```sh
   until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:PORT/ | grep -q "200\|30[0-9]"; do sleep 1; done
   ```
4. **Run a route smoke pass first.** Before deep exploratory testing, hit each top-level route/endpoint once with `curl` (or a quick `navigate` for web apps) to confirm the app actually came up correctly — catches a broken build before you spend the session investigating phantom bugs.
5. **Stop the server when done.** Kill the background process explicitly at the end of the testing pass — an orphaned dev server left running is its own kind of mess to clean up later.

## Applying it

- **Web apps:** run this setup, then hand the ready URL to `dogfood` (see [`../SKILL.md`](../SKILL.md)) for the browser-driven pass.
- **APIs/backends:** run this setup, then probe directly with `curl` as described in app-design's [test battery](https://github.com/thesawdawg/agent-skills/blob/main/app-design/references/test-battery.md), section 3.

## See also

- [dogfood/SKILL.md](../SKILL.md) — the workflow that consumes a running app once it's up
- [app-design/references/test-battery.md](https://github.com/thesawdawg/agent-skills/blob/main/app-design/references/test-battery.md) — where this pattern is invoked from Mode A's Test phase
