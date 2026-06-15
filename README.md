# ⚽ PitchPredict

PitchPredict is a World Cup 2026 score-prediction game built with Rails 8.
Players predict the score of every match before kickoff, pick a tournament
champion, and climb a live-updating leaderboard as admins enter real results.

- **Predict** – enter a scoreline for any fixture until it kicks off; predictions
  lock automatically at kickoff (or earlier, the moment a result is recorded).
  All kickoff times are shown in UTC.
- **Champion pick** – choose the team you think lifts the trophy before the
  tournament's first match; correct picks earn a bonus once the final is decided.
- **Score** – when an admin records a result, a background job rescores every
  prediction for that fixture and broadcasts the new leaderboard to every open
  browser over Turbo Streams — no refresh needed.

## Running the app

Requires Ruby 3.3.10 (see `.ruby-version`).

```bash
bin/setup        # bundle install, create + migrate + seed all databases, then boot bin/dev
# or, without booting the server:
bin/setup --skip-server
bin/dev          # Puma (with Solid Queue running in-process) + Tailwind watcher
```

The app runs at http://localhost:3000. Background jobs are processed inside the
Puma process in development (`SOLID_QUEUE_IN_PUMA=1` is exported by `bin/dev`),
so `bin/dev` is the only process manager you need.

Tests and linting:

```bash
bin/rails test:all   # unit + controller + system tests (headless Chrome)
bin/rubocop
```

> **Note:** `bin/rails db:seed` performs a *destructive replant* — it wipes all
> tables (including users and sessions) and rebuilds the deterministic demo
> world. Re-running it logs everyone out.

## Seeded logins

| Role  | Email                    | Password       |
| ----- | ------------------------ | -------------- |
| Admin | `admin@pitchpredict.app` | `worldcup2026` |
| Demo  | `demo@pitchpredict.app`  | `worldcup2026` |

Twelve more players (`player1@pitchpredict.app` … `player12@pitchpredict.app`,
same password) populate the leaderboard with realistic predictions.

## Scoring rules

| Outcome                                                  | Points  |
| -------------------------------------------------------- | ------- |
| Exact score (e.g. predicted 2–1, result 2–1)              | **4**   |
| Correct goal difference (e.g. predicted 3–2, result 2–1)  | **3**   |
| Correct tendency only (right winner, or a draw)           | **2**   |
| Anything else                                             | **0**   |
| Champion pick is the World Cup winner                     | **+10** |

The champion bonus is never persisted — `LeaderboardService` adds it at read
time by comparing each `ChampionPick` against the finished final, so correcting
the final's result automatically corrects every total.

## Models & services

| Class | Role |
| ----- | ---- |
| `User` | `has_secure_password`, `enum :role, { player:, admin: }`; owns predictions and one champion pick |
| `Session` | database-backed sessions from the Rails 8 authentication generator |
| `Team` | 48 teams in groups A–L, unique 3-letter FIFA code, flag emoji |
| `Stadium` | 16 host venues (table name `stadia`) |
| `Fixture` | match between two teams at a stadium; `enum :stage` (group → final) and `enum :status` (scheduled/live/finished); `locked?` once `kickoff_at` passes or the fixture leaves `scheduled` (early result entry must close predicting) |
| `Prediction` | a user's scoreline (0–20) for one fixture; unique per user+fixture; rejects create/edit once the fixture is locked; `points_awarded` set by scoring |
| `ChampionPick` | one per user; locked once the tournament's first fixture kicks off |
| `ScoringService` | pure scoring rules (`points_for`), idempotent `score_fixture!`, and `champion_team_id` from the finished final |
| `LeaderboardService` | ranked rows (total points, exact/diff/tendency counts) in two SQL queries, with standard competition ranking and the champion bonus applied at read time |
| `ScoreFixtureJob` | rescoring on result entry + Turbo Streams broadcast of the leaderboard table |

Key flows: `PredictionsController` upserts via a nested singular route
(`POST/PATCH /fixtures/:fixture_id/prediction`) and re-renders each fixture's
Turbo Frame card; `Admin::FixturesController` records results and enqueues
`ScoreFixtureJob`; the leaderboard page subscribes with
`turbo_stream_from "leaderboard"`.

## Rails 8 features used

- **Authentication generator** – `bin/rails generate authentication` provides
  sessions, password resets, and the `Authentication` concern
  (`app/controllers/concerns/authentication.rb`); signup added on top in
  `RegistrationsController`.
- **SQLite locally, Postgres in production** – SQLite backs development and
  test; production runs on a single managed PostgreSQL database (Neon) read
  from `DATABASE_URL` (`config/database.yml`). The whole Solid stack (Queue,
  Cache, Cable) lives on the **primary** connection in every environment for
  full dev/prod parity — their tables are created as ordinary migrations in
  `db/migrate`, not separate databases. See *Deploying to Render + Neon*
  below.
- **Solid Queue** – background jobs (`ScoreFixtureJob`) without Redis; runs
  inside Puma via the `plugin :solid_queue` line in `config/puma.rb`.
- **Solid Cache** – database-backed Rails cache (`config/cache.yml`); the
  ranked leaderboard rows are served from it (`LeaderboardService.fetch_rows`)
  and expired eagerly whenever predictions, users, or results change.
- **Solid Cable** – database-backed Action Cable for the live leaderboard
  broadcasts (`config/cable.yml`).
- **Propshaft + importmap** – no Node build step; JavaScript ships as ES modules
  (`config/importmap.rb`).
- **Turbo 8 morphing** – `<meta name="turbo-refresh-method" content="morph">`
  in the layout; prediction cards are Turbo Frames, the leaderboard updates via
  Turbo Streams.
- **Stimulus** – `stepper_controller.js` powers the +/- score steppers on the
  predictions grid; `leaderboard_highlight_controller.js` re-applies your
  own-row highlight after each viewer-agnostic leaderboard broadcast.
- **tailwindcss-rails (Tailwind v4)** – design system in
  `app/assets/tailwind/application.css` using `@theme` tokens and shared
  component classes.
- **PWA** – installable manifest (`app/views/pwa/manifest.json.erb`), offline
  fallback (`public/offline.html`), and a caching service worker
  (`app/views/pwa/service-worker.js`).
- **Kamal 2 + Thruster** – container deployment config in `config/deploy.yml`
  with Thruster fronting Puma in the production Dockerfile.

## Demo-data caveats

The seeded tournament is **illustrative, not real**: the group draw, knockout
bracket, and all scores are invented, and the schedule is shifted roughly ten
days earlier than the actual World Cup 2026 calendar (group stage June 1–24,
final July 19 at MetLife Stadium) so that "today" falls mid-tournament. Every
fixture whose kickoff has passed is seeded as finished and scored; the rest are
open for predictions. Seeds are deterministic (`Random.new(2026)`), so a replant
rebuilds the exact same world.

## Deploying to Render + Neon

Production runs as a single Render free web service backed by a single Neon
Postgres database. Local development and test stay on SQLite.

### 1. Create the Neon database

1. Create a new project at [neon.tech](https://neon.tech).
2. On the project dashboard open **Connection Details** and copy the connection
   string. It looks like:

   ```
   postgresql://<user>:<password>@ep-<id>.<region>.aws.neon.tech/<dbname>?sslmode=require
   ```

   Either the direct or the **Pooled connection** (the host gains `-pooler`)
   works — the app sets `prepared_statements: false` and `advisory_locks: false`
   so it is safe on both. Keep the `?sslmode=require` Neon includes. This whole
   string is your `DATABASE_URL`.

### 2. Deploy to Render via the blueprint

1. In the Render dashboard choose **New + → Blueprint** and point it at this
   repository. Render reads [`render.yaml`](render.yaml) and provisions the
   `pitchpredict` web service (free plan, native Ruby runtime, `/up` health
   check, `bin/render-build.sh` as the build command).
2. When prompted, set the two secret environment variables (both are
   `sync: false` in the blueprint, so Render asks for them):
   - `RAILS_MASTER_KEY` — the contents of `config/master.key`.
   - `DATABASE_URL` — the Neon connection string from step 1.
3. Optionally set your admin login (recommended), also as Render env vars:
   - `ADMIN_EMAIL` — defaults to `admin@pitchpredict.app`.
   - `ADMIN_PASSWORD` — if omitted, a random password is generated and printed
     **once** in the deploy logs (Render → Logs). Set it to choose your own.
4. On the first deploy `bin/render-build.sh` runs `rails db:prepare`, which
   loads the schema and seeds **reference data only** in production: all 48
   teams, the host stadiums, and the full fixture list shifted into the future
   so every match is open. No demo players are created.

### 3. Free-tier behaviour to expect

- The Render free web service **spins down after ~15 minutes idle**; the next
  request triggers a cold start (a few seconds).
- A Neon free database **auto-suspends after ~5 minutes idle** and wakes
  automatically on the next query (sub-second), so no manual resume is needed.
- Solid Queue runs **inside Puma** (`SOLID_QUEUE_IN_PUMA=true`), so background
  jobs only process while the web service is awake. That is fine here: scores
  are entered live by an admin, so the scoring job runs in the same request
  window the admin is active.

### Seed profiles (demo vs production)

`db/seeds.rb` picks a profile automatically:

- **Demo** (development/test, or production with `SEED_DEMO=true`): the full
  showcase — ~14 players, a spread of predictions and champion picks, and
  roughly half the group stage already played and scored. The admin and a demo
  player use the well-known password `worldcup2026`. This is what runs locally.
- **Production** (default in production): **reference data only** — teams,
  stadiums, and an all-future fixture list, plus a single admin from
  `ADMIN_EMAIL` / `ADMIN_PASSWORD`. No demo accounts, no fake results.

So a normal Render deploy does **not** expose the `worldcup2026` accounts. If
you ever set `SEED_DEMO=true` in production (e.g. for a demo instance), rotate
the admin password and remove the demo users before sharing the URL — otherwise
anyone who knows the seed password can log in as admin and edit results.
