# Activity Feed Emoji Tiers & Hype Copy — Design

**Date:** 2026-07-03
**Status:** Approved direction confirmed for threshold + two-ladder questions; hype-copy
placement (feed-wide, second-person for the viewer's own row) chosen as the recommended
default while the user was away — easy to flip to "own rows only" later.

## Goal

Make the dashboard "Recent activity" card more fun: streak milestones earn escalating
emojis, exact scores get a clearly flashier ladder, and each line carries a short
encouraging phrase ("You're on fire!", "Do you know the future??").

## Decisions

1. **Streak threshold drops from 3 to 2** (`ActivityFeedService::STREAK_MIN`), so the
   first emoji tier can appear and the feed feels livelier.
2. **Two parallel ladders** — outcome streaks use the user's requested ladder; exact-score
   streaks get a visibly better one. Tier = highest milestone ≤ streak count.

   | Streak | Outcome ladder | Exact ladder |
   |--------|----------------|--------------|
   | 2–3    | 🎯 "Right on target!" | 🎯🎯 "Back-to-back bullseyes!" |
   | 4–5    | 💯 "You're killing the prediction game!" / "Killing the prediction game!" | 🔮 "Do you know the future??" / "Do they know the future??" |
   | 6–7    | 🔥 "You're on fire!" / "On fire!" | 🧙 "Actual wizardry!" |
   | 8–9    | ⭐ "You're a star!" / "A star performance!" | 🌟 "Superstar! Nothing gets past you!" / "Superstar stuff!" |
   | 10+    | 👑 "You're a legend!" / "An absolute legend!" | 🐐 "You ARE the future." / "The GOAT. Simply the GOAT." |

   One-off exact hits (no streak): 👏 "What a call! 👏" (same phrase for everyone),
   badge `🎯 +<points>`.
3. **Hype copy appears on every feed line**, second person when the row is the viewer
   ("You're…") and third person otherwise.

## Architecture

- **`ActivityFeedService`** — data derivation only; the sole change is `STREAK_MIN = 2`.
  Emoji/copy are presentation and stay out of the service.
- **New `ActivityHelper`** (`app/helpers/activity_helper.rb`) — mirrors the
  `UserPredictionsHelper` pattern (frozen constant tables + small tested methods):
  - `Tier = Data.define(:emoji, :you, :other)`
  - `OUTCOME_STREAK_TIERS` / `EXACT_STREAK_TIERS`: descending-keyed hashes
    `{10 => Tier, 8 => Tier, …, 2 => Tier}`; lookup finds the first key ≤ count.
  - `EXACT_HIT_TIER`: single Tier for one-off exact hits.
  - `activity_emoji(item)` → tier emoji for the badge and line.
  - `activity_hype(item, you:)` → the phrase, person-correct.
  - `activity_badge(item)` → `"👑 12"`, `"🔮 4"`, or `"🎯 +4"`.
- **`_activity.html.erb`** — factual sentence stays; append `<hype> <emoji>`; badge uses
  `activity_badge(item)`. The 🔥 currently hard-coded on exact streak lines is replaced by
  the tier system.

## Error handling

Streak items always have `count >= 2` (service invariant), so tier lookup cannot miss.
`activity_badge`/`activity_emoji`/`activity_hype` raise on an unknown item type — new
types must be given a tier deliberately.

## Testing

- `test/helpers/activity_helper_test.rb` — tier boundaries (2, 3, 4, 6, 8, 10, 15) for
  both ladders, exact-hit tier, you/other phrase variants, badge formats.
- Service test: a streak of 2 now surfaces (and title of the "3+" test updated).
- Dashboard controller test: activity card shows a hype phrase + emoji.
