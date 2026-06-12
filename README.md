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
- **SQLite everywhere** – SQLite is the database in development, test, *and*
  production (`config/database.yml`), with separate databases for the app,
  cache, queue, and cable.
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
