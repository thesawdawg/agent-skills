# Threat Models

A catalog of threat categories DataSecurer draws from. Not every threat
applies to every project — the job is modeling the *realistic* threats
for this specific system, not listing every possible attack. But this
catalog ensures you don't miss a category.

## How to use this reference

For each category:
1. Does this apply to the project? (Based on data, users, architecture,
   deployment)
2. If yes, who is the realistic threat actor?
3. What is the realistic attack vector or failure path?
4. What is the likelihood and impact?

If a category doesn't apply, note why and move on. Don't invent threats
to seem thorough. Don't skip a category because it's uncomfortable.

---

## Threat actors — know your adversary

Before modeling threats, know who the adversaries actually are. This
changes everything.

| Actor | Motivation | Realistic for... |
|-------|-----------|-----------------|
| External attacker | Data theft, service disruption, financial gain | Any internet-facing system |
| Script kiddie / bot | Opportunistic scanning, known exploits | Any internet-facing system |
| Malicious insider | Data theft, sabotage, financial gain | Teams with prod access, disgruntled employees |
| Careless insider | Accidental deletion, misconfiguration, data leak | Every team, always |
| User error | Accidental data loss, account compromise | Every system with users |
| System failure | Hardware death, disk corruption, network partition | Every system |
| Dependency failure | Third-party API outage, library bug, supply chain attack | Any system with dependencies |
| Natural disaster | Data center loss, regional outage | Systems with a single-region deployment |

**The most under-modeled threat actor is the careless insider.** Most
data loss isn't malicious — it's a misplaced `rm`, a misconfigured
backup, a dev who ran a migration against production. Model this.

---

## 1. Unauthorized data access

**The threat:** Someone reads data they shouldn't have access to.

**Vectors:**
- Missing or broken access control (no authz check on a route)
- IDOR (insecure direct object reference — `/api/users/123` works for
  any user ID)
- SQL injection (user input reaches a query unsanitized)
- Exposed admin interface (no auth on admin routes)
- Overly broad query permissions (a user can query all records, not just
  theirs)
- Log files containing sensitive data
- Error messages leaking data ("user not found" vs "user exists but
  wrong password")

**Assess:** Does the architecture have clear access control boundaries?
Does Constructor's design separate user data? Are there admin routes?

---

## 2. Data exposure in transit

**The threat:** Data is intercepted while moving between client and
server, or between services.

**Vectors:**
- No TLS (HTTP instead of HTTPS)
- Self-signed certificates without proper pinning
- Internal service calls over plain HTTP
- API keys or tokens in URL parameters (logged by proxies)
- WebSocket without TLS

**Assess:** Is the system internet-facing? Are there inter-service
calls? What data flows over each connection?

---

## 3. Data exposure at rest

**The threat:** Data is readable by someone who gains access to the
storage (disk, database, backup, log).

**Vectors:**
- Unencrypted database (anyone with disk access reads everything)
- Backups stored unencrypted
- Secrets in source code or config files
- PII stored in logs
- Database snapshots shared for testing without redaction
- Disk theft or cloud storage misconfiguration (public S3 bucket)

**Assess:** What data is stored? Where? Who has access to the storage
layer? Are backups encrypted? Are secrets managed separately from data?

---

## 4. Authentication failures

**The threat:** Someone gains access as another user.

**Vectors:**
- Weak password policy (or none)
- Passwords stored in plain text or with weak hashing (MD5, SHA1, no
  salt)
- Session tokens that don't expire or aren't rotated
- JWT with `alg: none` or weak signing keys
- OAuth misconfiguration (open redirect, missing state parameter)
- Brute force without rate limiting
- Credential stuffing (no protection against reused passwords)
- Password reset flow that's exploitable (email enumeration, predictable
  tokens)

**Assess:** Does the system have authentication? Is it custom or
delegated? If custom, every item above is a risk. If delegated, the
provider handles most of this — but misconfiguration is still possible.

---

## 5. Authorization failures

**The threat:** An authenticated user does something they shouldn't be
able to do.

**Vectors:**
- Missing authz checks (auth ≠ authz — being logged in doesn't mean you
  can access everything)
- Role escalation (a user can change their own role)
- Horizontal privilege escalation (user A accesses user B's data)
- Vertical privilege escalation (regular user accesses admin functions)
- API endpoints with inconsistent authz (web UI checks, API doesn't)
- Stale permissions (permissions not revoked when access should end)

**Assess:** Are there different user roles? Is user data isolated? Are
there admin functions? How are permissions checked — per route, per
resource, or not at all?

---

## 6. Input validation failures

**The threat:** Untrusted input reaches a system that trusts it.

**Vectors:**
- SQL injection (input in queries)
- NoSQL injection (input in document queries)
- Command injection (input in shell commands)
- Path traversal (input in file paths)
- SSRF (server-side request forgery — input controls a URL the server
  fetches)
- XXE (XML external entity — input in XML parsers)
- Template injection (input in template engines)
- Deserialization attacks (input in object deserializers)
- XSS (input rendered in HTML without escaping)

**Assess:** Where does user input enter the system? Where does it go?
What parsers, query builders, or template engines does it touch?

---

## 7. Denial of service

**The threat:** The system becomes unavailable to legitimate users.

**Vectors:**
- No rate limiting (brute force, resource exhaustion)
- Expensive operations triggered by cheap input (regex DoS, hash
  collision, recursive parsing)
- Resource exhaustion (disk fill, memory exhaustion, connection
  exhaustion)
- Dependency outage cascading to your system
- Amplification attacks (DNS, NTP — less common for app-level)

**Assess:** Is the system internet-facing? Are there endpoints that do
expensive work? What happens under load? What happens when a dependency
is slow?

---

## 8. Data loss and corruption

**The threat:** Data is lost or corrupted and can't be recovered.

**Vectors:**
- Disk failure without redundancy (no RAID, no replication)
- Database corruption without backup
- Accidental deletion (dropping a table, deleting a record)
- Bug that corrupts data (a migration that overwrites instead of
  updates)
- Backup that doesn't restore (untested backups are not backups)
- Backup that's too old (RPO exceeded)
- Single-region deployment with no failover

**Assess:** What data is stored? Is there a backup? Has the backup been
tested? What's the RPO (acceptable data loss window)? What's the RTO
(recovery time)?

**This is the most common unmodeled threat.** Most teams have backups;
few have tested restoring from them. An untested backup is a hope, not
a plan.

---

## 9. Secrets management failures

**The threat:** Secrets (API keys, database passwords, signing keys) are
exposed.

**Vectors:**
- Secrets in source code (committed to git)
- Secrets in environment variables visible in process listings or crash
  dumps
- Secrets in CI logs
- Secrets shared via chat or email
- Secrets not rotated (a leaked key that's still valid)
- Secrets with too-broad permissions (one key that can do everything)
- Secrets in frontend code (accessible to anyone who opens dev tools)

**Assess:** Where are secrets stored? Who has access? How are they
rotated? Are they in the repo? (Check — this is more common than anyone
admits.)

---

## 10. Supply chain attacks

**The threat:** A dependency or tool is compromised.

**Vectors:**
- Malicious package published with a similar name (typosquatting)
- Legitimate package compromised (maintainer's account hacked)
- Dependency update introduces a vulnerability
- Build tool or CI compromised
- Base image compromised (Docker)

**Assess:** How many dependencies? Are they pinned? Is there a lockfile?
Are dependencies scanned? How are updates handled?

---

## 11. Audit and accountability gaps

**The threat:** Something bad happens and you can't tell what, when, or
who.

**Vectors:**
- No audit log for sensitive actions
- Logs that don't capture who did what
- Logs that are deleted or rotated too quickly
- Logs stored on the same system as the data (if the system is
  compromised, the logs are too)
- No alerting on suspicious patterns

**Assess:** What actions need an audit trail? Are they logged? Where are
logs stored? Who can read them? Who can delete them?

---

## Prioritization

After modeling threats, prioritize by:

1. **Catastrophic impact + non-trivial likelihood** → must mitigate
2. **Catastrophic impact + low likelihood** → document, let user decide
3. **Serious impact + high likelihood** → must mitigate
4. **Serious impact + low likelihood** → recommend mitigation
5. **Minor impact** → note and move on

Never present a threat without a priority. The user needs to know what
to fix first.
