# Dependency Catalog

Guidance for recommending dependencies. Constructor's stance: a
dependency must earn its place. If 20 lines of code or a standard
library feature does the job, use the code. Every dependency is a
maintenance liability, a security surface, and a potential abandonment
risk.

## Decision criteria

Before recommending a dependency, check:

1. **Does the standard library already do this?** If yes, use it.
2. **Is this <20 lines of straightforward code?** If yes, write it.
3. **Does it solve a problem you have, or a problem you imagine?** Don't
   pull in a router library "in case we need complex routing later."
4. **Is it actively maintained?** Check last commit date, release
   frequency, open issue count relative to closed.
5. **Is it widely adopted?** Niche dependencies are higher risk — fewer
   answers on StackOverflow, fewer maintainers if the original author
   walks away.
6. **What's the exit cost?** If this dependency wraps a standard
   interface (e.g., an ORM over SQL), swapping is feasible. If it
   permeates your codebase with its own abstractions, exiting is
   expensive. State this honestly.

## Categories

For each category below, the stance is: recommend the minimum that
solves the real problem. Note alternatives when the user's constraints
(language, ecosystem, existing infrastructure) point elsewhere.

### Web framework

**The question:** Does the project need a full framework or a
micro-framework?

- **Full framework** (Rails, Django, Spring Boot, NestJS): batteries
  included — routing, ORM, auth, migrations, admin panel. Best when you
  want to move fast and the framework's conventions match your domain.
  Cost: you live in the framework's world; fighting it is expensive.
- **Micro-framework** (Express, Flask, FastAPI, Sinatra, Actix):
  routing and request/response, nothing else. You compose the rest.
  Best when you want control or the project is small. Cost: you build
  the plumbing yourself.

**Recommendation principle:** Default to the framework the team knows.
If greenfield, default to the most boring, well-documented option in
the ecosystem. "Boring" is a feature in infrastructure.

### Database / ORM

**The question:** Relational, document, key-value, or something else?

- **Relational (Postgres, MySQL, SQLite):** default. Use this unless
  there's a concrete reason not to. Postgres handles most workloads
  including JSON, full-text search, and geospatial.
- **Document (MongoDB, DynamoDB):** when the data is naturally
  document-shaped and relationships are sparse. Be honest about the
  cost — no joins, eventual consistency patterns, migration is harder.
- **Key-value / cache (Redis):** for caching, rate limiting, session
  storage, queues. Not a primary datastore for most apps.

**ORM stance:** An ORM is a trade-off, not a default. It speeds up
common operations but can hide expensive queries and make complex
queries harder. Recommend:
- **For CRUD-heavy apps:** a lightweight ORM or query builder (e.g.,
  SQLAlchemy, Prisma, Ecto, GORM). Get autocomplete and migrations.
- **For query-complex apps:** a query builder or raw SQL with a thin
  helper layer. Don't fight the ORM.
- **Always:** know what SQL your ORM generates. If you can't, that's a
  maintenance risk.

### Migration tool

Use whatever the framework/ORM provides. If none, use the ecosystem
standard (e.g., Alembic, Flyway, golang-migrate, knex). Don't
hand-roll migrations.

### Authentication

**Strong stance:** Don't build auth yourself. Use:
- **Hosted auth** (Auth0, Clerk, Supabase Auth, Cognito): fastest,
  safest. The provider handles password storage, MFA, OAuth flows,
  session management. Cost: vendor dependency, per-user pricing at
  scale.
- **Battle-tested library** (Passport.js, Devise, django-allauth,
  Authlib): more control, more responsibility. You handle session
  storage, password reset flows, MFA yourself.

**Never recommend:** rolling your own password hashing, session
management, or OAuth flow. This is a DataSecurer flag, not a
Constructor decision.

### Validation

Use the ecosystem standard (Pydantic, Zod, Joi, class-validator,
serde). Don't hand-roll validation — it's tedious, error-prone, and
the libraries are well-tested. This is one dependency that almost
always earns its place.

### HTTP client

Standard library (`fetch`, `requests`, `net/http`, `reqwest`) for
simple cases. A retry/wrapper library (e.g., `tenacity`, `got`,
`reqwest` with retries) when you need circuit breakers, retries, or
connection pooling. Don't pull in a client library for a single
endpoint call.

### Background jobs / queues

- **Simple / small scale:** database-backed queue (e.g., `django-rq`,
  `good_job` for Rails, a `jobs` table with a worker loop). Minimal
  infrastructure.
- **Medium scale:** Redis-backed (Sidekiq, Celery+Redis, BullMQ).
  Reliable, well-understood, good observability.
- **Large scale / event-driven:** Kafka, RabbitMQ, SQS. Only when
  you need the throughput or the event-driven semantics.

**Recommendation principle:** Start with the simplest option that
survives a crash. A database-backed job queue is boring, reliable, and
you can upgrade later. Don't reach for Kafka on day one.

### Logging

Standard library logger for most cases. A structured logging library
(`structlog`, `pino`, `zap`, `tracing`) when you need JSON output for
log aggregation. Don't over-engineer — a good log format matters more
than the library.

### Testing

- **Unit tests:** the framework's built-in runner, or the ecosystem
  standard (pytest, Jest, Go's testing, `cargo test`).
- **HTTP/integration:** a test client (e.g., `TestClient` in FastAPI,
  `supertest` in Node). Don't spin up a real server in tests unless
  you're testing the deployment.
- **Fixtures:** factory functions over fixture libraries. Keep it
  simple. A `make_user()` function is clearer than a complex fixture
  graph.

### Configuration

- **12-factor:** environment variables for everything that changes
  between environments.
- **A config loader** (`python-dotenv`, `dotenv`, `viper`) to read
  `.env` files in development. In production, the platform provides
  env vars.
- **Don't** use a config library with its own DSL for a small project.
  A module that reads env vars and exposes typed values is enough.

## The "you don't need this" list

Dependencies Constructor will push back on:

- **Utility libraries** (lodash, underscore, moment) when the standard
  library covers the use case. Modern JS/Python stdlibs have most of
  this.
- **ORMs for simple key-value access.** If you're doing `get`/`set`/
  `delete`, use the driver directly.
- **State management libraries** on the backend. Backend state lives in
  the database.
- **Micro-frameworks for everything.** If you have 3 endpoints, a
  switch statement on the path is fine.
- **"Framework" wrappers over standard tools.** A "configuration
  framework" that wraps env var reading. A "logging framework" that
  wraps the standard logger. The wrapper is the cost, not the benefit.
