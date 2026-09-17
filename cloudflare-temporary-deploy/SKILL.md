---
name: cloudflare-temporary-deploy
description: Deploy a Cloudflare Worker live to a public workers.dev URL with zero account setup, via `wrangler deploy --temporary`. Use when the user wants agent-written code shipped to a real URL without creating a Cloudflare account, wants to prototype/evaluate a Worker quickly, or wants a self-verifying write-deploy-curl iteration loop. This creates a live, publicly reachable (if unclaimed, 60-minute) deployment — confirm with the user before the first deploy.
---

# Temporary Cloudflare deployment

Prepare a Worker and make the proposed deployment reviewable before the public
exposure step. Confirm authorization for the first public deployment unless the
user already explicitly authorized that action. Authorization persists for the
agreed scope; do not deploy as a side effect of ordinary editing or QA.

## Requirements and boundaries

- This workflow uses pinned `wrangler@4.102.0`, Node 22+, npm, and Python 3.
  [The release](https://github.com/cloudflare/workers-sdk/releases/tag/wrangler%404.102.0)
  supports temporary previews. Verify package/runtime compatibility before setup.
- A temporary deployment is public. Explain the claim/expiry information returned
  by Wrangler; do not promise production availability or permanent hosting.
- Do not remove existing Cloudflare credentials or log out to force this flow.
  If the user is authenticated, explain the conflict and resolve their intent.
- Respect the service's terms. Claim URLs grant ownership: keep them private.

## Workflow

1. Reuse the user's Worker project, or prepare a minimal Worker and configuration.
   Test locally and show the relevant changes before deployment approval.
2. Resolve this installed skill from its loaded path. From the Worker project,
   invoke the bundled helper using a new private log path:

   ```bash
   DEPLOY="/absolute/path/to/cloudflare-temporary-deploy/scripts/deploy.sh"
   bash "$DEPLOY" ./temporary-deploy-run-1.log
   ```

   The helper preserves Wrangler's exit status and parses only successful output.
   It refuses an existing log. A parser result alone is not deployment success.
3. Verify the returned live URL with a bounded request and expected content.
   Record deployment, HTTP verification, and any blocked checks separately.
4. For an authorized iteration, use a fresh log path. Stop on repeated errors or
   changed scope; do not loop deployments to discover missing information.
5. Reveal the claim URL only when delivering it privately to the user, by
   parsing the existing successful log. **Do not redeploy to retrieve it.**

   ```bash
   PARSER="/absolute/path/to/cloudflare-temporary-deploy/scripts/parse_deploy_output.py"
   python3 "$PARSER" --show-claim-url < ./temporary-deploy-run-1.log
   ```

   Normal parser output redacts the claim token. Retain sensitive logs only as
   needed and report their location, not their raw contents. Delete only owned
   logs when the user requests cleanup.

Verify the parser with `python3 scripts/parse_deploy_output.py --selftest` from
this skill directory. Repository tests mock Wrangler; no public deployment is
needed to test failure propagation, redaction, or log ownership.
