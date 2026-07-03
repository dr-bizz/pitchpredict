# Homepage activity section (issue #15)

## Goal

A "Recent activity" section on the dashboard celebrating recent hits and hot streaks,
e.g.:

- "**Bizz** predicted 5 matches in a row with the correct outcome"
- "**John Doe** is on a streak of 3 exact scores! 🔥"
- "**Ana** nailed Portugal 2–1 Croatia exactly (+4)"

## Approach

Pure read-time derivation — **no schema change, no new tables**. All the data needed
already lives in `predictions.points_awarded` + `fixtures` (status, kickoff order).
A new `ActivityFeedService` computes items; result cached in Solid Cache like
`LeaderboardService` (short TTL + expiry piggybacks on the existing
`LeaderboardService.expire_rows` moments — see Caching).

Alternatives considered and rejected:

- **Persisted activity/events table** written at scoring time — more moving parts,
  needs backfill, duplicates derivable state. YAGNI at this player count.
- **Compute inline in the controller** — dashboard renders on every Turbo refresh
  broadcast; a service with caching matches the existing LeaderboardService pattern.

## Definitions

- **Scored prediction**: prediction on a `finished` fixture with `points_awarded`
  present.
- **User timeline**: a user's scored predictions ordered by fixture `kickoff_at`
  ascending.
- **Current outcome streak**: consecutive run of `points_awarded > 0` counting
  backwards from the end of the user's timeline. Broken by any 0.
- **Current exact streak**: same, but `points_awarded == 4` (`ScoringService::EXACT_POINTS`).
- **Recent**: the fixture anchoring the item kicked off within the last **72 hours**.
  Keeps the feed "recently" as the issue asks, without a config knob.

## Feed content

Item types, in priority order (exact beats outcome, streaks beat one-offs):

1. **Exact streak** (≥ 3): "*Name* is on a streak of N exact scores! 🔥"
2. **Outcome streak** (≥ 3): "*Name* predicted N matches in a row with the correct
   outcome"
3. **Exact hit**: "*Name* called *Home X–Y Away* exactly (+4)" — for fixtures finished
   in the recent window.

Rules:

- A user appears **at most once** in the feed (their best item: exact streak >
  outcome streak > exact hit). Keeps one hot player from flooding the feed.
- A streak item is only shown while it is *alive*: the user's most recent scored
  prediction is part of it, and that fixture is within the recent window.
- Cap the feed at **6 items**; order by type priority, then streak length desc, then
  fixture recency.
- Empty state: render the section with a friendly line ("No hot streaks yet — the next
  round could be yours"), so the layout is stable.

## UI

New card section on `dashboard/show.html.erb` titled **"Recent activity"**, placed
directly below the stat-tile row (above Champion Pick / Top Players). Simple list:
avatar initial (reuse `avatar-initial` classes), message with bolded name, right-aligned
badge (🔥 / +4 / streak count). Matches existing card / typography patterns. Live
updates come free: the page already subscribes to `turbo_stream_from "results"` and
re-renders after every scoring run.

Names link via the existing `player_predictions_link` helper where it applies.

## Service shape

```ruby
ActivityFeedService.fetch_items  # -> [Item], cached
Item = Data.define(:type, :user, :count, :fixture, :points)  # shape indicative
```

One query pulls scored predictions joined to finished fixtures (id, user_id,
points_awarded, kickoff_at, teams/scores for exact hits); streaks computed in Ruby.
Player counts are small (friends-and-family scale); this is well within budget, and
it's cached.

## Caching

`Rails.cache.fetch("activity/items", expires_in: 1.minute)` — same safety-net TTL
pattern as the leaderboard. Eager expiry: call `ActivityFeedService.expire_items` from
`LeaderboardService.expire_rows` is wrong-layered; instead expire from the same hooks
that already exist — `Prediction` `after_commit` and `ScoreFixtureJob` — mirroring
`LeaderboardService.expire_rows` call sites exactly.

## Tests

- Service: streak computation (outcome + exact), streak broken by a 0, streak below
  threshold hidden, one-item-per-user rule, 72h recency cutoff, cap at 6, cache expiry
  hook.
- Controller/view: dashboard renders the section; shows empty state; shows a streak
  line when data warrants.

## Open questions posted to the issue (proceeding with these defaults)

- Streak threshold 3+, feed cap 6, recency window 72h, one item per user.
