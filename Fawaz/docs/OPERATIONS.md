# Operating the OMNIA backend

Release, migration, rollback, backup and secret procedures for `Fawaz/backend`, plus what the service reports about itself. Written for whoever deploys and runs it. Commands assume `docker compose` from `Fawaz/`; on another platform, run the same commands with the backend image.

## 1. Releasing a new version

Migrations are a separate, explicit release step. The API container never migrates on start (`backend/Dockerfile`): several replicas racing `alembic upgrade` is unsafe, and a failed migration should stop a release instead of crash-looping the API.

1. **Back up** the database (section 4). Never skip this before a migration.
2. **Build** the new image: `docker compose build`.
3. **Migrate**, once: `docker compose run --rm migrate` (runs `alembic upgrade head` and exits). If it fails, stop: the old API keeps running on the old schema. Fix forward or restore (section 3).
4. **Start or roll** the API: `docker compose up -d backend`. Locally, `docker compose up --build` does steps 2–4 in order; the `backend` service waits for `migrate` to succeed.
5. **Check** `GET /api/health/ready` returns `{"status":"ok","database":"ok"}`, then smoke-test sign-in and today's plan.

Migrations are written to be backward compatible with the previous API version where possible (add columns and tables first; remove them in a later release), so step 3 can run while the old API still serves traffic. CI applies every migration, checks the models match (`alembic check`), downgrades to base and re-applies, on SQLite and PostgreSQL.

## 2. Writing a migration

- One revision per change, in `backend/alembic/versions/`, numbered after the last (`0009_…`).
- Mirror the model exactly, including constraint names (`op.f("ck_<table>_<name>")`) and index names; `alembic check` fails otherwise.
- Booleans default with `sa.true()` / `sa.false()`, never `text("1")`: PostgreSQL rejects an integer default for a boolean (`tests/test_migrations.py` guards the models).
- Implement `downgrade()`, and test it: CI runs it.
- Data backfills run inside the migration and must work on PostgreSQL (see `0007`'s revision backfill and its PostgreSQL compile test).

## 3. Rolling back

Prefer **rolling forward**: a small fix release is safer than reverting a schema.

- **Code only** (no migration in the release): redeploy the previous image tag.
- **With a migration**, if the new API is broken but the data is fine: redeploy the previous image; it still works because migrations are additive (section 1). Remove the new schema later in a deliberate release.
- **A migration must be undone**: stop the API, run `docker compose run --rm migrate alembic downgrade <previous revision>`, redeploy the previous image. Downgrades drop the new tables or columns **and their data** (for example `0008` drops recorded plan outcomes, `0009` drops goals). If that data matters, restore a backup instead.
- **Data is damaged**: restore the backup taken in step 1 (section 4).

## 4. Backups and restore

The `db` service keeps data in the `db-data` volume. Back up with PostgreSQL's own tools:

```bash
# Backup (custom format, compressed). Store it off the host, encrypted.
docker compose exec -T db pg_dump -U omnia -d omnia -Fc > omnia-$(date +%F-%H%M).dump

# Restore into an empty database (stop the API first)
docker compose stop backend
docker compose exec -T db dropdb -U omnia omnia
docker compose exec -T db createdb -U omnia omnia
docker compose exec -T db pg_restore -U omnia -d omnia < omnia-YYYY-MM-DD-HHMM.dump
docker compose up -d backend
```

- Take one before every release, and on a schedule (at least daily) for production.
- Test a restore regularly; an untested backup is not a backup.
- Backups contain personal data (accounts, plans, logs). Treat them like the database: encrypted, access-controlled, deleted on schedule. Deleting an account removes its rows from the live database, not from old backups; say so in the privacy notice.

## 5. Secrets and rotation

All secrets come from the environment or an untracked `.env` (`backend/.env.example` lists them). The frontend holds none.

| Secret | Rotate by | Effect |
|---|---|---|
| `AUTH_SECRET` (32+ chars) | Set a new value and restart the API. | Every access token stops working; all users sign in again. Do this immediately if it may have leaked. |
| One user's tokens | The user signs out everywhere or changes password. | Bumps their `token_version`; their other tokens stop working. |
| `POSTGRES_PASSWORD` | `ALTER ROLE omnia PASSWORD '…'` in the database, update `.env`, restart `migrate`/`backend`. | Brief reconnect. |
| `AI_API_KEY`, `OPENROUTER_API_KEY` | Create a new key at the provider, update the environment, restart, then revoke the old key. | None if done in that order; if the key fails, planning falls back to the rules planner. |

Never commit a real `.env`; never paste secrets into logs, tickets or chat.

## 6. Monitoring

**Logs.** Requests are logged as method, path, status, duration and request id (`omnia.access`); unhandled errors with their stack trace and request id (`omnia.errors`). Clients see only a generic message plus the `X-Request-ID`, which finds the full trace in the logs. Passwords, tokens and request bodies are never logged.

**Events** (`omnia.metrics`): one line per event, for example `metric event=ai.plan provider=ollama result=fallback reason=timeout latency_ms=30012`. Values are names and numbers only, never user content or ids.

| Event | Fields | Watch for |
|---|---|---|
| `ai.plan` | `provider`, `result` (`primary`/`fallback`/`error`), `reason`, `latency_ms` | A rising fallback share or latency: the model is slow, down or returning invalid plans. |
| `ai.replan.proposal` | `provider`, `result` (`created`/`invalid`/`unavailable`/`stale`), `fallback_used`, `latency_ms` | `invalid`/`unavailable` growth: the model's proposals fail validation. |
| `ai.replan.apply` | `result` (`applied`/`stale`/`expired`/`invalid`/`not_pending`) | Many `stale`/`expired`: proposals take too long or plans change underneath them. |
| `ai.replan.dismiss` | `result` (`dismissed`/`expired`) | Dismissal rate: proposals people don't want. |
| `plan.outcome` | `status` (`done`/`partial`/`skipped`/`cleared`), `category` | How much of the plan actually happens. |

**Error reporting.** Unhandled errors are logged with a request id today. Forwarding them to a hosted error tracker (Sentry or similar) needs an account and a DSN secret, so it isn't configured; add it behind an environment variable when one is chosen.

## 7. Known limits before scaling out

- **Rate limiting is in memory** (`app/core/rate_limit.py`). With more than one API instance each has its own counters, so the effective limits multiply. Run one instance, or move the limiter to Redis or the gateway, before scaling out.
- **Access tokens last 12 hours with no refresh token** (`ACCESS_TOKEN_EXPIRE_MINUTES=720`). Accepted for now: a session survives a working day, tokens are revocable (`token_version`), and the app restores sign-in from secure storage. The cost is a sign-in prompt after 12 hours and a stolen token staying valid until it expires or the user signs out everywhere. Revisit (short access token plus rotating refresh token) before a public launch or for longer sessions.
- **Planning-state locks** use PostgreSQL row locks. They serialize per account, so they are safe across instances.
