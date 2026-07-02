#!/usr/bin/env python3
"""Parse `wrangler deploy --temporary` output into structured JSON.

Reads wrangler's stdout/stderr from STDIN and extracts the live workers.dev
URL, the claim URL, the temporary account name/state, the claim window, and
whether a deploy actually happened. Stdlib only — no dependencies.

The claim URL is credential-equivalent (it grants ownership of the temporary
account), so it is REDACTED by default. Pass --show-claim-url to get the
real value when you actually need to hand it to the user.

Usage:
    npx wrangler@latest deploy --temporary 2>&1 | python3 parse_deploy_output.py
    npx wrangler@latest deploy --temporary 2>&1 | python3 parse_deploy_output.py --show-claim-url
    python3 parse_deploy_output.py --selftest
"""

from __future__ import annotations

import json
import re
import sys

# Match the live workers.dev URL (subdomain.subdomain.workers.dev). The tail
# is a positive-ish exclusion set rather than a bare \S* so we don't swallow
# ANSI escape codes, trailing punctuation, or surrounding quotes that a
# terminal or log line might glue onto the URL.
_URL_TAIL = r"""[^\s"'<>()\x00-\x1f]*"""
_LIVE_URL = re.compile(r"https://[A-Za-z0-9._-]+\.workers\.dev" + _URL_TAIL)
# Match the claim URL. Cloudflare uses dash.cloudflare.com/claim-preview?claimToken=...
# Keep it broad enough to survive minor path changes while still requiring a claim token.
_CLAIM_URL = re.compile(
    r"https://[^\s\"'<>()\x00-\x1f]*claim[^\s\"'<>()\x00-\x1f]*claimToken=[^\s\"'<>()\x00-\x1f]+",
    re.IGNORECASE,
)
# "Account: Serene Temple (created)"  /  "Account:  example-name (reused)"
# Account names can contain spaces (e.g. "Serene Temple"), so capture everything
# up to the trailing "(state)" marker rather than a single token.
_ACCOUNT = re.compile(
    r"Account:\s*(?P<name>.+?)\s*\((?P<state>created|reused)\)", re.IGNORECASE
)
# "Claim within:   60 minutes"
_CLAIM_WITHIN = re.compile(r"Claim within:\s*(?P<minutes>\d+)\s*minutes?", re.IGNORECASE)
# A successful deploy prints a "Deployed" / "Uploaded" line.
_DEPLOYED = re.compile(r"^\s*(Deployed|Uploaded)\b", re.IGNORECASE | re.MULTILINE)


def _last(pattern: re.Pattern, text: str) -> str | None:
    matches = pattern.findall(text) if pattern.groups else [m.group(0) for m in pattern.finditer(text)]
    if not matches:
        return None
    # If the deploy log mentions the live URL more than once (e.g. an
    # intermediate upload line plus the final confirmation), the last
    # occurrence is the one tied to the actual "Deployed" confirmation.
    return matches[-1]


def _redact_claim_url(claim_url: str | None) -> str | None:
    if claim_url is None:
        return None
    return re.sub(r"claimToken=[^\s\"'<>()]+", "claimToken=<REDACTED>", claim_url, flags=re.IGNORECASE)


def parse(text: str, *, show_claim_url: bool = False) -> dict:
    """Extract deploy facts from wrangler output text."""
    account = _ACCOUNT.search(text)
    claim_within = _CLAIM_WITHIN.search(text)
    claim_url = _last(_CLAIM_URL, text)
    if claim_url and not show_claim_url:
        claim_url = _redact_claim_url(claim_url)
    return {
        "live_url": _last(_LIVE_URL, text),
        "claim_url": claim_url,
        "account": account.group("name") if account else None,
        "account_state": account.group("state").lower() if account else None,
        "expires_minutes": int(claim_within.group("minutes")) if claim_within else None,
        "deployed": bool(_DEPLOYED.search(text)),
    }


_SAMPLE = """\
Continuing means you accept Cloudflare's Terms of Service and Privacy Policy.

Temporary account ready:
     Account:        example-name (created)
     Claim within:   60 minutes
     Claim URL:      https://dash.cloudflare.com/claim-preview?claimToken=abc123XYZ

Uploaded example-worker
Deployed example-worker triggers
     https://example-worker.example-name.workers.dev
"""

_SAMPLE_REUSED = """\
Temporary account ready:
     Account:        example-name (reused)
     Claim within:   42 minutes
     Claim URL:      https://dash.cloudflare.com/claim-preview?claimToken=def456
Deployed example-worker triggers
     https://example-worker.example-name.workers.dev
"""

_SAMPLE_NO_TEMP = """\
✘ [ERROR] You are not logged in.

To continue without logging in, rerun this command with `--temporary`.
"""

# ANSI-colored output (green for the URL, reset after) with no whitespace
# between the URL and the escape/reset sequence.
_SAMPLE_ANSI = (
    "Deployed example-worker triggers\n"
    "     \x1b[32mhttps://example-worker.example-name.workers.dev\x1b[0m\n"
)

# Live URL wrapped in markdown-style parens and trailing punctuation, plus a
# claim URL immediately followed by a closing quote — both should stop the
# match at the URL boundary, not swallow the wrapper.
_SAMPLE_WRAPPED = (
    'See the deploy at (https://example-worker.example-name.workers.dev).\n'
    'claim_url="https://dash.cloudflare.com/claim-preview?claimToken=zzz999"\n'
)

# Deploy that mentions the workers.dev URL twice — once during upload, once
# in the final confirmation — to check we take the confirmation occurrence.
_SAMPLE_MULTIPLE_URLS = """\
Uploading assets, will be served from https://example-worker.example-name.workers.dev/__old
Deployed example-worker triggers
     https://example-worker.example-name.workers.dev
"""

# A deploy that prints a live URL but never emits an explicit
# "Deployed"/"Uploaded" line (defensive — shouldn't normally happen, but the
# `deployed` flag should reflect what's actually in the text).
_SAMPLE_NO_DEPLOYED_LINE = """\
     https://example-worker.example-name.workers.dev
"""


def _selftest() -> int:
    r = parse(_SAMPLE)
    assert r["live_url"] == "https://example-worker.example-name.workers.dev", r
    assert r["claim_url"] == "https://dash.cloudflare.com/claim-preview?claimToken=<REDACTED>", r
    assert r["account"] == "example-name", r
    assert r["account_state"] == "created", r
    assert r["expires_minutes"] == 60, r
    assert r["deployed"] is True, r

    r_shown = parse(_SAMPLE, show_claim_url=True)
    assert r_shown["claim_url"] == "https://dash.cloudflare.com/claim-preview?claimToken=abc123XYZ", r_shown

    r2 = parse(_SAMPLE_REUSED)
    assert r2["account_state"] == "reused", r2
    assert r2["expires_minutes"] == 42, r2
    assert r2["deployed"] is True, r2

    r3 = parse(_SAMPLE_NO_TEMP)
    assert r3["live_url"] is None, r3
    assert r3["claim_url"] is None, r3
    assert r3["account"] is None, r3
    assert r3["deployed"] is False, r3

    r4 = parse(_SAMPLE_ANSI)
    assert r4["live_url"] == "https://example-worker.example-name.workers.dev", r4

    r5 = parse(_SAMPLE_WRAPPED, show_claim_url=True)
    assert r5["live_url"] == "https://example-worker.example-name.workers.dev", r5
    assert r5["claim_url"] == "https://dash.cloudflare.com/claim-preview?claimToken=zzz999", r5

    r6 = parse(_SAMPLE_MULTIPLE_URLS)
    assert r6["live_url"] == "https://example-worker.example-name.workers.dev", r6

    r7 = parse(_SAMPLE_NO_DEPLOYED_LINE)
    assert r7["live_url"] == "https://example-worker.example-name.workers.dev", r7
    assert r7["deployed"] is False, r7

    print("selftest: OK")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    show_claim_url = "--show-claim-url" in argv
    text = sys.stdin.read()
    result = parse(text, show_claim_url=show_claim_url)
    print(json.dumps(result, indent=2))
    # Non-zero exit if no live URL was found, so callers can branch on it.
    return 0 if result["live_url"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
