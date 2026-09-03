# Architecture Patterns

A catalog of backend architecture patterns with honest trade-offs.
Constructor draws from this when recommending — never presents a pattern
as free. Every pattern has a cost. The job is matching the cost to the
project's reality.

## How to use this reference

For each pattern, know:
- **Best for** — the conditions where it shines
- **Cost** — what you pay in complexity, operations, or coupling
- **Maintenance impact** — how it affects the future developer
- **When to revisit** — signals that it's time to upgrade or migrate

---

## Modular Monolith

A single deployable unit with clear internal module boundaries. Modules
communicate via in-process function calls but are organized as if they
were separate services.

**Best for:** Small teams (1–5), evolving domain boundaries, projects
under 100k LOC, most B2B apps, anything where the boundaries aren't
stable yet.

**Cost:** Shared database (if not disciplined about module-owned
schemas), temptation to break boundaries via direct imports, deployment
is all-or-nothing.

**Maintenance impact:** Excellent. New dev onboards fast. Tests run in
one process. Debugging is straightforward. Refactoring across modules is
a search-and-replace, not a distributed trace.

**When to revisit:** When a module needs independent scaling, independent
deployment, or a different tech stack. When the team grows past ~8 and
merge conflicts cluster in shared modules.

**Constructor's default bias:** Start here unless there's a concrete
reason not to. Most projects never outgrow this.

---

## Microservices

Multiple independently deployable services, each owning its own data,
communicating via network calls (HTTP, gRPC, events).

**Best for:** Teams large enough to own services independently (>8
people), stable domain boundaries, genuine independent scaling needs,
polyglot environments, organizational scaling problems.

**Cost:** Distributed system complexity — network failures, partial
outages, eventual consistency, distributed tracing, service mesh,
CI/CD per service. Operational overhead is 3–10x a monolith.

**Maintenance impact:** Hard. Onboarding requires understanding the
system map. Debugging requires distributed tracing. A simple feature
may touch 3 services. Testing end-to-end flows is expensive.

**When to revisit:** You probably shouldn't start here. If you did,
revisit when you realize 3 of your 5 services always deploy together.

**Constructor's default bias:** Don't recommend this for greenfield
projects unless the user has a concrete, stated reason (organizational
structure, regulatory isolation, proven scale need). Say the quiet part
out loud: "You're choosing operational complexity. Are you resourced for
it?"

---

## Layered (N-Tier) Monolith

Classic separation: presentation → business logic → data access. Each
layer depends only on the one below.

**Best for:** CRUD-heavy apps, simple domains, teams that want clear
separation without the overhead of DDD or modular decomposition.

**Cost:** Layers can become pass-throughs (thin business logic layer
that just calls the data layer). Temptation to skip layers for
"performance." Hard to scale organizationally — everyone touches all
layers.

**Maintenance impact:** Good for simple apps. Degrades as domain
complexity grows — business logic leaks into the presentation or data
layer because the "layer" boundary doesn't match the "domain" boundary.

**When to revisit:** When business logic starts accumulating in
controllers or data access objects. That's the signal that layers
aren't the right boundary.

---

## Hexagonal / Ports & Adapters

Core domain logic is isolated from infrastructure via interfaces
("ports"). Infrastructure (DB, HTTP, queues) are "adapters" that plug
into ports.

**Best for:** Domains with complex business rules, projects that may
swap infrastructure (e.g., testing with a different DB), teams that
value testability of pure domain logic.

**Cost:** More interfaces and indirection. Can feel over-engineered for
simple CRUD. Adapter proliferation if not disciplined.

**Maintenance impact:** Excellent for domain-heavy projects. Domain
logic is fully testable without infrastructure. Swapping a database or
adding a queue is a new adapter, not a rewrite. But: the indirection
has a learning curve for new devs.

**When to revisit:** If most of your "ports" have exactly one adapter
and you can't articulate a scenario where you'd add a second, you may
be carrying the cost without the benefit.

---

## Event-Driven / CQRS

Commands produce events. State is built from event streams. Read models
are separate from write models, populated by event handlers.

**Best for:** Audit-heavy systems, systems where the "history" of
changes matters, systems with complex read patterns that differ from
write patterns, event-sourced domains.

**Cost:** Eventual consistency on reads. Event schema evolution is hard.
Debugging requires replaying events. Operational complexity of event
store + projections + read model sync.

**Maintenance impact:** Hard. New devs struggle with "where does the
state actually live?" Event versioning becomes a permanent maintenance
tax. But for the right domain (financial, audit, collaborative), it's
the only honest model.

**When to revisit:** If you don't need audit trails or temporal queries,
this is probably overkill. A simple append-only log + current-state
table gets you 80% of the benefit at 20% of the cost.

---

## Serverless Functions (FaaS)

Business logic deployed as individual functions triggered by HTTP,
events, or schedules. No long-running server.

**Best for:** Bursty/low-traffic workloads, simple request-response
flows, teams that want zero infrastructure management, glue code between
services.

**Cost:** Cold starts. Vendor lock-in. Hard to test locally. Function
granularity is a design challenge (too fine = distributed mess, too
coarse = just a serverless monolith). Limited execution time. State
must live externally.

**Maintenance impact:** Mixed. No servers to patch, but debugging is
hard (no local repro of the full trigger chain). Dependency management
per function. Deployment is easy but observability requires extra tooling.

**When to revisit:** If you're building long-lived connections,
streaming, or complex stateful workflows, serverless functions are the
wrong tool.

---

## Pipeline / Batch Processing

Data flows through a series of transformation stages. Each stage takes
input, produces output, passes to the next. Can be ETL, data
processing, ML pipelines.

**Best for:** Data transformation, ETL, report generation, ML training,
any "input → transform → output" workflow.

**Cost:** Hard to debug mid-pipeline. Failure handling (retry, skip,
dead-letter) must be designed explicitly. Backpressure and ordering
become issues at scale.

**Maintenance impact:** Good if stages are well-named and
self-contained. Each stage is independently testable. But the pipeline
as a whole needs integration tests.

---

## Choosing — the decision questions

When picking a pattern, answer these in order:

1. **How many people will maintain this?** <5 → monolith. 5–8 →
   modular monolith. >8 → consider service decomposition.
2. **Are the domain boundaries stable?** No → modular monolith (boundaries
   can evolve in-process). Yes → services become viable.
3. **Do parts need to scale independently?** No → single deployable.
   Yes → extract only the part that needs it.
4. **Is the domain logic complex?** Simple CRUD → layered. Complex rules
   → hexagonal or modular monolith with domain modules.
5. **Does the history of changes matter?** No → current-state storage.
   Yes → consider event sourcing (but understand the cost).
6. **What's the operational tolerance?** Solo dev → minimize moving parts.
   Team with DevOps → more options.

**The default path for most new projects:** Modular monolith → extract
services only when a concrete need appears. This is not laziness; it's
deferred complexity. You pay it when you know what you need, not when
you're guessing.
