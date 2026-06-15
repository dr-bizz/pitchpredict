# Hosting PitchPredict — Render + Neon (free tier)

This guide deploys PitchPredict as a single **Render** free web service backed by
a single **Neon** Postgres database. Local development and test stay on
SQLite; only production uses Postgres.

> TL;DR: create a Neon project → copy its connection string → deploy this repo
> to Render as a **Blueprint** → set `RAILS_MASTER_KEY` and `DATABASE_URL` → done.

---

## Prerequisites

- This repository pushed to **GitHub** (Render deploys from a Git remote).
- A **Neon** account — <https://neon.tech>
- A **Render** account — <https://render.com>
- Your `config/master.key` (already in the repo locally; it is git-ignored, so
  you supply its contents to Render as an env var).

---

## 1. Create the Neon database

1. Create a new project at <https://neon.tech> (pick a region close to your
   Render region). Neon creates a database for you automatically.
2. On the project dashboard open **Connection Details** and copy the connection
   string. It looks like:

   ```
   postgresql://<user>:<password>@ep-<id>.<region>.aws.neon.tech/<dbname>?sslmode=require
   ```

   Either endpoint works:
   - **Direct connection** (default) — simplest, ideal for a single
     always-one-instance Rails server.
   - **Pooled connection** (toggle it on; the host gains `-pooler`) — PgBouncer
     in front of the database.

   The app sets `prepared_statements: false` **and** `advisory_locks: false` in
   `config/database.yml`, so it runs cleanly on **both** endpoints (transaction
   pooling forbids session-level prepared statements and advisory locks). Keep
   the `?sslmode=require` that Neon includes — Neon requires TLS. This whole
   string is your `DATABASE_URL`.

---

## 2. Deploy to Render via the Blueprint

The repo ships a [`render.yaml`](render.yaml) Blueprint, so you don't configure
the service by hand.

1. In the Render dashboard choose **New + → Blueprint** and point it at your
   GitHub repository. Render reads `render.yaml` and provisions the
   `pitchpredict` web service: free plan, native Ruby runtime, `/up` health
   check, and `bin/render-build.sh` as the build command.
2. When prompted, set the two **secret** environment variables (both are marked
   `sync: false` in the Blueprint, so Render asks for them):

   | Variable           | Value                                                      |
   | ------------------ | ---------------------------------------------------------- |
   | `RAILS_MASTER_KEY` | the contents of `config/master.key`                        |
   | `DATABASE_URL`     | the Neon connection string from step 1                     |

3. **(Recommended)** set your admin login as additional env vars:

   | Variable         | Default                  | Notes                                            |
   | ---------------- | ------------------------ | ------------------------------------------------ |
   | `ADMIN_EMAIL`    | `admin@pitchpredict.app` | The admin account's email.                       |
   | `ADMIN_PASSWORD` | _(generated)_            | If unset, a random one is generated and **printed once** in the deploy logs. |

4. Click **Apply**. The first deploy runs `bin/render-build.sh`, which:
   `bundle install` → `assets:precompile` → `db:prepare` (creates the schema and
   seeds **reference data only**: 48 teams, host stadiums, and an all-future
   fixture list — **no demo accounts**).

When the deploy goes green, open the service URL. Log in as your admin
(`ADMIN_EMAIL` / `ADMIN_PASSWORD`, or the generated password from the logs) and
start entering results from **Admin → Fixtures** as matches finish.

---

## Environment variables reference

| Variable              | Required | Set by      | Purpose                                                        |
| --------------------- | -------- | ----------- | -------------------------------------------------------------- |
| `RAILS_MASTER_KEY`    | yes      | you         | Decrypts `config/credentials.yml.enc` (and `secret_key_base`). |
| `DATABASE_URL`        | yes      | you         | Neon Postgres connection string (includes `?sslmode=require`). |
| `ADMIN_EMAIL`         | no       | you         | Admin login email (default `admin@pitchpredict.app`).          |
| `ADMIN_PASSWORD`      | no       | you         | Admin password; random + printed once if unset.                |
| `RAILS_ENV`           | —        | `render.yaml` | `production`.                                                 |
| `RAILS_MAX_THREADS`   | —        | `render.yaml` | Puma threads / DB pool size (`3`).                            |
| `SOLID_QUEUE_IN_PUMA` | —        | `render.yaml` | Runs Solid Queue inside Puma (`true`).                        |
| `WEB_CONCURRENCY`     | —        | `render.yaml` | Puma workers (`1` — keep at 1 on free tier).                  |
| `SEED_DEMO`           | no       | you         | Set `true` to seed the populated demo world in production (see Security). |

---

## Free-tier behaviour to expect

- **Render free spins down after ~15 minutes idle.** The next request triggers a
  cold start (a few seconds). Normal for a hobby app.
- **Neon free auto-suspends the database after ~5 minutes idle** and wakes
  automatically on the next query (sub-second) — no manual resume needed.
- **Background jobs run only while the web service is awake.** Solid Queue runs
  inside Puma (`SOLID_QUEUE_IN_PUMA=true`), so the scoring job processes in the
  same request window — which is exactly when an admin enters a score, so this
  is a non-issue for the manual-entry workflow.
- **WebSockets / live leaderboard** (Turbo Streams over Solid Cable) work while
  the service is awake; the connection re-establishes after a cold start.

---

## Security

A normal production deploy seeds **reference data only** and creates a **single
admin** from `ADMIN_EMAIL` / `ADMIN_PASSWORD`. The well-known `worldcup2026`
demo accounts are **not** created.

If you intentionally set `SEED_DEMO=true` in production (e.g. to show off the
populated leaderboard), the seeds create demo players **and** an admin with the
password `worldcup2026`. In that case you **must** rotate the admin password and
remove the demo users before sharing the URL — otherwise anyone who knows the
seed password can log in as admin and edit results.

---

## Updating the app

Push to the branch Render tracks (e.g. `main`) and Render auto-deploys. Every
deploy re-runs `bin/render-build.sh`; `db:prepare` runs pending migrations and
is a no-op when there are none. It does **not** re-seed an existing database.

To wipe and re-seed (destructive — recreates teams/fixtures and logs everyone
out), run in a Render Shell (paid feature) or locally against `DATABASE_URL`:

```bash
RAILS_ENV=production bin/rails db:seed
```

---

## Troubleshooting

| Symptom                                            | Likely cause / fix                                                                                 |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Build fails on `db:prepare` with a connection error | `DATABASE_URL` wrong, or missing `?sslmode=require` — copy the exact string from Neon's Connection Details. |
| `ActiveSupport::MessageEncryptor` / credentials error | `RAILS_MASTER_KEY` missing or wrong — paste the exact contents of `config/master.key`.            |
| First request hangs ~30–60s                         | Free-tier cold start after idle spin-down. Expected.                                                |
| Can't log in as admin                              | Check the deploy logs for the generated password, or set `ADMIN_PASSWORD` and redeploy.             |
| App boots but has no matches                        | `db:prepare` didn't seed — check build logs; run `RAILS_ENV=production bin/rails db:seed`.           |

For a deeper feature/architecture overview, see [`README.md`](README.md).
