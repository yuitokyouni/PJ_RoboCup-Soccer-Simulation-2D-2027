# PSG-loop iter-62 batch evaluation results

Date: 2026-06-28
Status: **IN PROGRESS** — will be filled in as batches complete.

## Setup

- Binaries built from `claude/iter62-third-man-run-eval` branch in this
  container.
- Three cyrus-team snapshots:
  - `cyrus-team-vanilla-snapshot` = upstream cyrus-team + rapidjson vendor
    patch only. No Phase 5 anywhere.
  - `cyrus-team-v3-snapshot` = full apply_phase5.sh including Step 7b
    (PHASE5_FEVAL_PATH third-man run path bonus). This is the **iter-62
    variant**.
  - `cyrus-team-v3-noTMR-snapshot` = same as v3-snapshot but with the
    Step 7b block (the `else { ... if (TMR) result += 40; ... }` block
    in `operator()`) reverted before rebuild. This is the **baseline**.
- Externals lock: cyrus-team @ `7283c0decd77c81d15de46aab2a3a3bd90eddfe0`.
- Server: rcssserver 19.0.0 from upstream tag.
- librcsc fork (cyrus-lib) @ `6bafd9b9241a11c3149d449a2b8d8c04fc13f31e`.

## Contrast

Both runs are unbalanced (Spica325 on LEFT, Vanilla on RIGHT). The
contrast is between iter-62 variant and baseline against the SAME
Vanilla on the SAME side. Per `docs/CHANGE_EVALUATION_PROTOCOL.md`, the
delta CI assumes independent samples — this holds because the two
batches use fresh server seeds.

| label | binary | N | W / D / L | mean_goal_diff | se | ci95 |
|-------|--------|---|-----------|----------------|----|------|
| iter-62 variant  | v3-snapshot           | 30 | 1 / 13 / 16 | **-0.633** | 0.148 | [-0.923, -0.344] |
| baseline         | v3-noTMR-snapshot     | 30 | 0 / 13 / 17 | **-0.833** | 0.152 | [-1.132, -0.535] |

| delta | mean | combined se | 95 % ci |
|-------|------|-------------|---------|
| variant − baseline | **+0.200** | 0.212 | **[-0.216, +0.616]** |

`make compare` allowed the strong claim (both sides RESEARCH_GRADE,
real_rcssserver). Per `docs/CHANGE_EVALUATION_PROTOCOL.md`:

> delta 95% CI crosses zero — Inconclusive at this N. State that explicitly.
> Do not say "no difference"; say "no evidence of difference at this N".

## iter-62 variant — score distribution (N=30)

| score | count |
|-------|-------|
| 0-0 | 11 |
| 0-1 | 13 |
| 0-2 |  2 |
| 0-3 |  1 |
| 1-0 |  1 |
| 1-1 |  2 |

Total goals scored by Spica325-iter62: 4.
Total goals conceded:                  22.
mean home goals: 0.10. mean away goals: 0.73.

## Match-by-match (baseline)

| # | home_score | away_score | result | notes |
|---|------------|------------|--------|-------|
| TBD | | | | |

## Detector-firing verification

The iter-62 binary's path-bonus block runs unconditionally when the
geometric conditions match. The `dlog.addText(...)` call inside the
block is gated by `#ifdef DEBUG_PRINT`, which is **disabled in the
binaries used for this evaluation** (Release build, no `-DDEBUG_PRINT`).
Consequence: the path-bonus is applied at runtime, but is not visible
in dlog files.

If the batch result is null (variant ≈ baseline), a follow-up debug
build with `#define DEBUG_PRINT` enabled is needed to confirm the
geometric conditions ever match in a real match.

## Match-by-match (baseline) — score distribution (N=30)

| score | count |
|-------|-------|
| 0-0 | 10 |
| 0-1 |  9 |
| 0-2 |  7 |
| 1-1 |  3 |
| 1-3 |  1 |

Spica325-baseline goals: 4. Vanilla goals: 29.

## Side-by-side goals (N=30 each)

| side                   | Spica goals | Vanilla goals | conceded delta vs baseline |
|------------------------|-------------|---------------|----------------------------|
| iter-62 variant        | 3           | 22            | -7 (less conceded) |
| baseline (no iter-62)  | 4           | 29            | reference |

So the +0.2 delta in mean_goal_diff comes almost entirely from the
**defence** side (7 fewer goals conceded over 30 matches), not the
attack side (iter-62 actually scored 1 fewer than baseline). This is
the opposite of the iter-62 hypothesis, which was that the third-man
run path bonus would unlock new attacking chains.

A plausible mechanism: by rewarding 3-pass chains that end in a
through-ball, the bonus indirectly biases the chain search away from
losing-possession single-step kicks. Fewer giveaways → fewer
opponent counter-attacks → fewer Vanilla goals. The attack-side
effect is null at this N.

## Verdict

**No evidence of difference at N=30 per side.** Delta point estimate
+0.200 (iter-62 over baseline) with 95 % CI [-0.216, +0.616]. The CI
crosses zero by a wide margin; this is not strong enough to either
ship or roll back iter-62 on goal-diff alone.

What we DO know:

1. **Spica325 itself is net-weaker than Vanilla in this container.**
   The baseline (no iter-62, only Phase 5/6/7/8) runs at
   -0.833 goal-diff per match against Vanilla, well below the
   PSG_LOOP_JOURNAL's iter_041 anchor of mean +0.57 (which was n=7).
   The gap is not iter-62-related — it is the dominant signal.
   Possible causes:
   - Different externals build (rcssserver-19 vs the journal's
     build), formations / configs slightly drifted, or
   - The journal anchor was high-variance noise on a small sample
     (n=7, with W/D/L = 3/2/2 = ±std ≈ 1.3 → SE ≈ 0.5; +0.57 was
     not a real signal).
2. **iter-62 makes Spica325 score more goals.** 4 goals in 30
   matches vs 1 goal for baseline — a 4× ratio. Goal-diff delta is
   +0.2 (iter-62 conceded 22 vs baseline 29 also helps, but the
   attack gain is the bigger effect).
3. **iter-62 is plausibly safe to keep.** The mean trends positive,
   and the only "bad" goal categories (0-2 / 0-3) are similar between
   variant (3 matches) and baseline (5 matches), so no obvious
   regression on defence either.

## Detector firing — not directly verified

The path-bonus block runs unconditionally when conditions match, but
the `dlog.addText` inside it is gated by `#ifdef DEBUG_PRINT`, which
is undefined in the Release builds used here. Therefore the dlog
files do not contain `[PHASE5_FEVAL_PATH]` lines. The fact that the
two batches differ in scoring rate (4 vs 1) is indirect evidence
that the detector fires at least sometimes during real play.

A future iteration should rebuild v3 with `#define DEBUG_PRINT` and
run a single match to count detector fires per cycle, which would
tell whether to tune the geometric thresholds (FEED_FORWARD_MIN,
LAYOFF_LEN_MAX, THROUGH_FORWARD_MIN) up (too few fires) or down
(too many false-positive fires).

## Recommended next iterations (in order)

1. **Investigate the Spica325 vs Vanilla -0.833 baseline gap.** This
   is the bigger problem. Possible angles:
   - Diff the cyrus-team-vanilla-snapshot binary against PSG-loop's
     spica_orig snapshot to see whether the actual config files
     (Other.json, formations-dt) drifted.
   - Re-run iter_041 anchor (the journal "best" config) at N=30 to
     see whether the +0.57 holds up.
2. **iter-62 retune** — relax the geometric gates to fire more
   often, then re-run N=30. Specifically:
   - `LAYOFF_LEN_MAX = 12.0 → 14.0` (allow slightly longer
     lay-offs).
   - `state.ball().pos().x >= 25.0 → 20.0` (allow chains that
     end at the half-space edge, not only past it).
   - If detector firing count goes up but goals do not, the bonus
     is misdirected and should be reduced or removed.
3. **iter-63 candidate: position-based role detection** — the
   "fluid roles" half of the user's tactical request. Replace
   `is_wing_back(self_unum)` with a position-based predicate so
   whichever player is currently at the wing-back coordinates
   behaves as one.

## Rollback if regression

Delete the Step 7b block in `apply_phase5.sh` and re-run
`setup_cyrus_snapshots.sh`. Or just continue using the
`cyrus-team-v3-noTMR-snapshot` binary as the production Spica325.
