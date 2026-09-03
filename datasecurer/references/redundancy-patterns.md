# Redundancy Patterns

A catalog of redundancy and recovery patterns. DataSecurer draws from
this when designing the redundancy plan. The goal is not maximum
redundancy — it's matching the redundancy to the asset's impact rating
and the project's operational capacity.

## How to use this reference

For each asset that would cause serious or catastrophic impact if lost:
1. What failure scenarios apply?
2. What redundancy pattern prevents each?
3. What's the simplest pattern that covers the real scenarios?
4. What's the recovery procedure, and has it been tested?

Don't over-engineer redundancy for low-impact data. Don't under-engineer
it for catastrophic-loss data. Match the cost to the risk.

---

## Core concepts

### RPO and RTO — the two numbers that matter

- **RPO (Recovery Point Objective):** How much data can you afford to
  lose? Measured in time. RPO of 1 hour means "if we fail now, we lose
  the last hour of data."
- **RTO (Recovery Time Objective):** How fast must the system be back?
  Measured in time. RTO of 4 hours means "the system must be
  operational within 4 hours of failure."

Every redundancy decision is an RPO/RTO trade-off. State these numbers
for each asset before choosing a pattern.

| Asset impact | Typical RPO | Typical RTO |
|-------------|-------------|-------------|
| Catastrophic (user data, financial) | < 1 hour | < 4 hours |
| Serious (operational data) | < 24 hours | < 24 hours |
| Minor (cache, derived data) | reconstructable | whenever |

---

## Data redundancy patterns

### Database replication

**What it prevents:** Data loss from primary database failure.

**How it works:** A replica maintains a copy of the primary's data.
If the primary fails, the replica is promoted.

**Variants:**
- **Synchronous replication:** Primary waits for replica to confirm
  write before returning success. RPO = 0 (no data loss). Cost: write
  latency increases.
- **Asynchronous replication:** Primary returns success immediately,
  replica catches up. RPO = replication lag (seconds to minutes). Cost:
  potential data loss on failover.
- **Read replicas:** Primarily for read scaling, not failover. Can be
  promoted but may lag.

**When to use:** Any system where data loss is serious or catastrophic.
Synchronous for zero-data-loss requirements. Asynchronous for most
other cases.

**Maintenance cost:** Moderate. Replication lag monitoring, failover
procedure (and testing it), handling split-brain scenarios.

---

### Point-in-time backups

**What it prevents:** Data loss from corruption, accidental deletion, or
a bad migration.

**How it works:** Periodic snapshots of the database, retained for a
rolling window. Most managed databases (RDS, Cloud SQL, Postgres with
WAL archiving) support point-in-time recovery.

**Variants:**
- **Full snapshots:** Complete copy, periodic (daily/weekly).
- **Incremental + WAL:** Continuous WAL archiving + periodic snapshots.
  Enables recovery to any point in time within the retention window.
- **Logical exports:** `pg_dump` / equivalent. Slower to restore, but
  portable and storage-efficient.

**When to use:** Always. This is the baseline. Even with replication,
backups protect against corruption and accidental deletion that
replication would faithfully copy.

**RPO:** Depends on snapshot frequency and WAL retention. With WAL
archiving, RPO can be minutes. With daily snapshots only, RPO is up to
24 hours.

**The critical rule:** **An untested backup is not a backup.** A
recovery plan that has never been executed is a hypothesis. Require a
restore test as part of the plan.

---

### Backup storage strategy

**What it prevents:** Loss of backups when the primary system or region
fails.

**How it works:** Backups are stored separately from the primary data,
ideally in a different region or cloud account.

**Rules:**
- **3-2-1 rule:** 3 copies of data, on 2 different media, with 1 copy
  off-site. Still valid.
- **Separate access:** Backup access should be separate from production
  access. If your prod credentials are compromised, the attacker
  shouldn't be able to delete the backups.
- **Immutable backups:** Write-once, read-many storage for backups
  prevents ransomware or malicious deletion. Many cloud providers offer
  this (AWS S3 Object Lock, GCP Bucket Lock).

**When to use:** Any system with data you can't afford to lose. The
separate-access rule is especially important — backups on the same
account as production are not safe from a compromised account.

---

### Multi-region deployment

**What it prevents:** Regional outage — entire data center or cloud
region goes down.

**How it works:** The system runs in multiple regions, with data
replicated between them. Traffic routes to the healthy region.

**Cost:** High. Multi-region replication, global load balancing,
conflict resolution, operational complexity. 2–5x the cost of
single-region.

**When to use:** When regional outage is unacceptable (high-availability
SaaS, financial systems). Not justified for most early-stage projects.

**When not to use:** Solo projects, internal tools, anything where a
few hours of downtime is tolerable. A single-region deployment with
good backups covers most needs.

---

## Availability patterns

### Health checks and auto-restart

**What it prevents:** Silent failures where the process is running but
not serving.

**How it works:** A health check endpoint reports process status. The
orchestrator (systemd, Docker, Kubernetes, PM2, cloud platform) restarts
the process if the health check fails.

**When to use:** Always. This is the baseline for any production
deployment. Even a solo project should have `restart: always` on its
Docker container or a systemd `Restart=on-failure`.

**Cost:** Minimal. One endpoint, one config line.

---

### Graceful degradation

**What it prevents:** Total failure when a dependency fails.

**How it works:** When a non-critical dependency is unavailable, the
system continues serving with reduced functionality instead of failing
completely. Examples: serve cached data when the database is slow,
disable search when the search index is down, show a "feature
temporarily unavailable" message instead of a 500.

**When to use:** When the system has features that are valuable but not
critical. A system that either works perfectly or not at all is
fragile.

**Cost:** Moderate. Requires identifying which features are critical vs
degradable, and building fallback paths. But the fallback paths are
often simple (cached response, feature flag off).

---

### Circuit breakers

**What it prevents:** Cascading failure when a dependency is slow or
down.

**How it works:** When calls to a dependency fail repeatedly, the
circuit breaker "trips" and stops calling the dependency for a period.
This prevents resource exhaustion (thread pool, connection pool) from
waiting on a dead dependency.

**When to use:** Any system that calls external services (APIs,
databases) where a slow response could exhaust your resources.

**Cost:** Low to moderate. Libraries exist for most languages
(`circuitbreaker`, `hystrix`, `opossum`, `tenacity`). The main cost is
deciding what to do when the circuit is open (fail fast, return cached,
queue for later).

---

### Rate limiting and backpressure

**What it prevents:** Resource exhaustion from too many requests.

**How it works:** Limit the rate of incoming requests (per user, per
IP, global). When the limit is exceeded, reject or queue. This protects
the system from both legitimate overload and simple DoS.

**When to use:** Any internet-facing system. Even a side project should
have basic rate limiting on auth endpoints (brute force protection).

**Cost:** Low. A reverse proxy (nginx, Caddy, cloud load balancer) can
handle rate limiting at the edge. Application-level rate limiting
(Redis-backed) for per-user limits.

---

## Recovery procedures

For each redundancy pattern, document the recovery procedure:

1. **How to detect the failure** — what monitoring alerts, what symptom
   the user sees
2. **How to trigger recovery** — the command, the runbook step, the
   automated failover
3. **How to verify recovery** — what to check to confirm the system is
   healthy
4. **How to test this procedure** — when was it last tested, and how

**An untested recovery procedure is a hope, not a plan.** Require a
testing cadence: at least once for initial validation, then quarterly
for critical systems.

---

## Matching redundancy to impact

| Asset impact | Minimum redundancy | Recommended |
|-------------|-------------------|-------------|
| Catastrophic | Daily backup + replication | PITR + cross-region backup + replication + tested restore |
| Serious | Daily backup | PITR + replication + tested restore |
| Minor | Occasional backup | Reconstructable from source data |

**The testing requirement scales with impact.** A catastrophic-loss
asset with an untested backup is effectively unprotected. Require
restore testing for any serious or catastrophic asset.
