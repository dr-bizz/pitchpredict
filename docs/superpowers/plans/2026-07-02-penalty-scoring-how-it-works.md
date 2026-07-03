# Penalty Scoring in "How it works" (issue #16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The home-page "How it works" card explains how knockout/penalty-shootout scoring works.

**Architecture:** View-only change to `app/views/dashboard/show.html.erb` plus a controller test. No logic changes.

**Tech Stack:** Rails 8.1 ERB, Tailwind/daisyUI utility classes already used on the page.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-02-penalty-scoring-how-it-works-design.md` (committed in this worktree).
- Point values in copy must come from `ScoringService` constants, never hard-coded (matches the section's existing style).
- Run tests with `bin/rails test` (system tests known-broken locally). Rubocop clean: `bin/rubocop`.
- Baseline: 185 runs, 0 failures.

---

### Task 1: Knockout note in the How-it-works card

**Files:**
- Modify: `app/views/dashboard/show.html.erb` (the `<%# 4. HOW IT WORKS %>` section — insert between the score-tile grid's closing `</div>` and the champion-bonus `alert` div)
- Test: `test/controllers/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `ScoringService::EXACT_POINTS`, `ScoringService::DIFFERENCE_POINTS`, `ScoringService::TENDENCY_POINTS` (already referenced in this view).

- [ ] **Step 1: Write the failing test**

Append to `test/controllers/dashboard_controller_test.rb`:

```ruby
test "how it works explains knockout and penalty-shootout scoring" do
  sign_in_as(@user)

  get root_path

  assert_response :success
  assert_select "section", text: /Knockout matches/ do
    assert_select "li", text: /pick the right team to advance/i
    assert_select "li", text: /penalty shootout/i
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`
Expected: FAIL — no "Knockout matches" content.

- [ ] **Step 3: Implement**

In `app/views/dashboard/show.html.erb`, inside the How-it-works `card-body`, after the score-tile grid `</div>` and before the existing champion-bonus `<div role="alert" ...>`, insert:

```erb
<%# Knockout rounds change what "correct result" means: the advancer, not the
    90-minute tendency — see ScoringService#outcome. %>
<div class="mt-4 rounded-xl border border-pitch/20 bg-pitch-light/60 px-4 py-3">
  <p class="text-sm font-bold text-charcoal">⚽ Knockout matches &amp; penalty shootouts</p>
  <ul class="mt-2 list-disc space-y-1 pl-5 text-sm text-gray-600">
    <li>
      Points only count if you pick the right team to advance — the wrong advancer scores
      +0, even with the right goal difference.
    </li>
    <li>
      Predict a draw and you also pick who wins the penalty shootout — that's your advancer.
      Nail the drawn score and the shootout for +<%= ScoringService::EXACT_POINTS %>.
    </li>
    <li>
      Exact score (+<%= ScoringService::EXACT_POINTS %>) and goal difference
      (+<%= ScoringService::DIFFERENCE_POINTS %>) are judged on the final recorded score;
      the right advancer alone is +<%= ScoringService::TENDENCY_POINTS %>.
    </li>
  </ul>
</div>
```

(`bg-pitch-light` is an existing app color used for own-row highlights; the `/60` opacity + `border-pitch/20` keep it subordinate to the gold champion alert below. If either utility doesn't compile in this Tailwind setup, fall back to `bg-pitch-light` and `border-base-200`.)

- [ ] **Step 4: Run the full suite + rubocop**

Run: `bin/rails test && bin/rubocop`
Expected: all green (186 runs), no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/views/dashboard/show.html.erb test/controllers/dashboard_controller_test.rb
git commit -m "feat: explain knockout & penalty-shootout scoring on the home page"
```
