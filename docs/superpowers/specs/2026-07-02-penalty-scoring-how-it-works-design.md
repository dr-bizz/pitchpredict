# Penalty-shootout scoring in "How it works" (issue #16)

## Goal

The home-page "How it works" section (dashboard) explains 4/3/2/0 and the champion
bonus, but says nothing about knockout matches and penalty shootouts (added in PR #12).
Players need to see, on the home page, how penalties affect scoring.

## Actual scoring rules to document (from `ScoringService`)

- For knockout matches the **outcome you must get right is who advances** — the winner,
  or on a level score the penalty-shootout winner. Picking the wrong advancer scores 0
  regardless of scoreline.
- If you predict a draw on a knockout match you also pick who wins the shootout.
- Exact score = 4 and goal difference = 3 still apply to the recorded score; correct
  advancer alone = 2.

## Design

Extend the existing "How it works" card in `app/views/dashboard/show.html.erb` — same
card, directly under the four score tiles, before the champion-bonus alert. Add a
compact "Knockout matches" note styled like the existing champion alert (`alert` with
brand tint) or a small bordered block, containing 2–3 short lines:

1. **Pick who advances.** In the knockout rounds your points count only if you pick the
   right team to go through — wrong advancer = 0, even with the right goal difference.
2. **Predicting a draw? Pick the shootout winner too.** Your pick decides who you think
   advances.
3. Exact score (+4) and goal difference (+3) are judged on the final recorded score.

Copy should reference `ScoringService` constants (`EXACT_POINTS`, etc.) rather than
hard-coded numbers, matching the section's existing style. Football-flavoured, short,
no new components; reuse existing utility classes (`score-tile` not needed — this is a
note, not a tile). An inline SVG icon (⚽/🥅-style, consistent with existing inline
icons) is fine but optional.

Also update the section only — no changes to scoring logic, no other pages. (The
predictions page already has its own inline penalty UI from PR #12.)

## Tests

- Controller/view test: dashboard show renders the knockout note (assert on stable copy
  like "penalty shootout" / "advances").
- No service changes, so no service tests.
