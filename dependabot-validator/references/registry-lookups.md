# Registry and changelog lookups

Deterministic `curl` recipes for step 4. Extract fields with a small Python
filter — do **not** `head` a raw registry document (it's large, field order
isn't a contract, and you'll cut off exactly what you need).

## npm: repo/homepage and confirm both versions exist

```bash
curl -sSL "https://registry.npmjs.org/<pkg>" | python3 -c '
import sys, json, re
d = json.load(sys.stdin)
repo = re.sub(r"^git\+|\.git$", "", (d.get("repository") or {}).get("url") or "")
print("repo:", repo or "(none)")
print("homepage:", d.get("homepage") or "(none)")
vs = d.get("versions", {})
for v in ("<from_version>", "<to_version>"):
    print(v + ":", "present" if v in vs else "MISSING from registry")
'
```

## PyPI: repo/homepage and project URLs

```bash
curl -sSL "https://pypi.org/pypi/<pkg>/json" | python3 -c '
import sys, json
d = json.load(sys.stdin)["info"]
print("homepage:", d.get("home_page") or "(none)")
print("project_urls:", d.get("project_urls") or {})
'
```

## GitHub releases within the version range

Once you have `<owner>/<repo>`, print only releases whose tag is in
`(from_version, to_version]`, with full bodies (not truncated to a fixed
length):

```bash
curl -sSL "https://api.github.com/repos/<owner>/<repo>/releases?per_page=100" | python3 -c '
import sys, json, re
frm, to = "<from_version>", "<to_version>"
def key(t): return [int(x) for x in re.findall(r"\d+", t.lstrip("vV"))[:3]] or [0]
data = json.load(sys.stdin)
if isinstance(data, dict):                       # error object (rate-limited / not found)
    print("release lookup FAILED:", data.get("message")); sys.exit()
lo, hi = key(frm), key(to)
hits = sorted((r for r in data if lo < key(r["tag_name"]) <= hi), key=lambda r: key(r["tag_name"]))
for r in hits:
    print("###", r["tag_name"]); print((r["body"] or "").strip()); print()
if not hits:
    print("NO releases found in range", frm, "->", to, "— try tags or CHANGELOG fallback.")
'
```

## Fallback: CHANGELOG instead of GitHub Releases

```bash
curl -sSL "https://raw.githubusercontent.com/<owner>/<repo>/HEAD/CHANGELOG.md" | sed -n '1,200p'
```

Read the entries between the two versions.
