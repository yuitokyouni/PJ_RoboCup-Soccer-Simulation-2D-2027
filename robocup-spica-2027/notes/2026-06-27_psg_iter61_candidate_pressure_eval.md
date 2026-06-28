# PSG-loop iter-61 candidate — sample_field_evaluator pressure + space

Date: 2026-06-27
Status: **UNVERIFIED** — code change only; no batch evaluation yet.
File: `externals/patches/cyrus-team/apply_phase5.sh` (Step 7b)
Target file (patched in-place by the script): `sample_field_evaluator.cpp`

## Hypothesis

The baseline `evaluate_state` (and `evaluate_state2`, used in the wide
opp attacking corner) scores chain-final states with three signals:

1. `ball.x` (linear in x)
2. `max(0, 40 - dist_to_opp_goal)` (goal-distance bonus, capped at 40)
3. `+1.0e+6` binary spike if `FieldAnalyzer::can_shoot_from` returns true

That is, a high-x receiver **in space** and a high-x receiver
**surrounded by two markers** get identical state value. The only
defensive context is the binary shoot check.

All spica chain biases up to iter-60 (wedge ×2, cross +35, through
+25, side-switch ±15, chance-signal ±30) live at the per-candidate
evaluator hook in `action_chain_graph.cpp`. The underlying STATE
value function has never been touched. Consequence: those biases
compete against an undifferentiated x-coordinate ramp, and the chain
search still has no continuous signal for "is the holder marked or
free?"

## Change

Patch `sample_field_evaluator.cpp::evaluate_state` and
`evaluate_state2` to add a bounded pressure / space term, inserted
AFTER the basic-evaluation block and BEFORE the shoot bonus:

```cpp
const Cont opps = state.getPlayers(new OpponentOrUnknownPlayerPredicate(state.ourSide()));
const Vector2D hp = holder->pos();
int n_press = 0;
double min_dist = 1.0e+6;
for ( const auto * opp : opps ) {
    const double d = opp->pos().dist( hp );
    if ( d < PRESS_RADIUS ) ++n_press;
    if ( d < min_dist )      min_dist = d;
}
point -= PRESS_PENALTY * n_press;        // -8 per opp within 3.0 m
point += std::min(min_dist, SPACE_CAP);  // up to +8 for nearest-opp distance
```

Constants (tunable A/B handles):
- `PRESS_RADIUS = 3.0` m
- `PRESS_PENALTY = 8.0` per close opponent
- `SPACE_CAP = 8.0` m

`evaluate_state_penalty` (penalty-kick mode only) is **not** patched
— penalty-kick state space already centres on the GK on its
own-goal-mouth axis, and a generic pressure penalty there is
ill-defined.

## Why this matters more than per-candidate bonuses

A per-candidate bonus on a Pass action only fires for that one
candidate's first step. The chain search then evaluates the resulting
FINAL state with a function that ignores defensive context. So a
chain like `WB → F9 (+50 wedge) → CF marked-by-3` can score higher
than `WB → free F9` if the marked-CF ends up at higher x. The state
evaluator is the eventual judge.

Moving the pressure signal into the evaluator means EVERY chain end
state gets the same comparison, regardless of which candidate hook
triggered along the way.

## Magnitude sanity check

For a holder at x=+40 (opp PA edge):
- ball.x = 40
- goal-distance bonus ≈ 27 (12.5 m from goal)
- Pre-pressure point ≈ 67

Worst-case marked (2 opp inside 3 m, nearest 1 m away):
- press_pen = -16
- space_bonus = +1
- Adjusted = 52

Free (nearest opp 8 m away):
- press_pen = 0
- space_bonus = +8
- Adjusted = 75

Differential ≈ 23 between marked and free at the same position. The
chain search will prefer free finishes by a meaningful margin without
overpowering the position signal. The shoot spike (+1e6) is
unaffected.

## What this is *not*

- Not proposal B (continuous shot angle) — that comes next if A holds up.
- Not proposal C (chain-shape penalty using `path`) — even later.
- Not a defensive change — the evaluator is read by ChainAction
  (offensive search), not by defensive behaviors.

## Rollback

Two-step:
1. Delete the Step 7b block in `apply_phase5.sh` (the block between
   the markers "Step 7b: patch sample_field_evaluator.cpp" and
   "Step 8: patch CMakeLists.txt").
2. Force-refetch + reapply other patches:
   `make fetch-externals ONLY=cyrus-team FORCE=1 &&`
   `bash externals/patches/cyrus-team/apply_phase5.sh externals/src/cyrus-team`.

Anchors used:
- `evaluate_state`: the `double point = state.ball().pos().x; …
  ServerParam::i().theirTeamGoalPos().dist(…)` initialization block.
- `evaluate_state2`: the aggregated `point += point_x; … point +=
  point_line;` block PLUS the trailing `dlog.addText(... "eval: …")`
  line. The dlog line is what disambiguates evaluate_state2 from
  evaluate_state_penalty, which uses the same aggregation pattern
  but does not log.

## Evaluation plan

Per `docs/CHANGE_EVALUATION_PROTOCOL.md`:

1. Apply the patched `apply_phase5.sh` against a fresh fetch of
   cyrus-team. Confirm `grep PHASE5_FEVAL` returns 4 matches and
   that they sit in `evaluate_state` / `evaluate_state2` only.
2. Build: `cmake --build externals/src/cyrus-team/build`. The patch
   uses `<algorithm>` (`std::min`) which is already included by
   `<cmath>` chains in this TU; if the build fails on `std::min`,
   add `#include <algorithm>` near the top.
3. Variant batch vs Vanilla at iter_041 / iter_047 baseline N. Same
   externals lock as the baseline (already pinned).
4. `make compare BASELINE=<iter_041 summary> VARIANT=<iter-61 summary>`.
   Primary metric: `mean_goal_diff` delta with 95% CI.
5. Secondary metric: `psg_ledger.py` chain-quality breakdown — count
   of through-ball goals (expect unchanged or up), count of conceded
   counter-attacks following lost-possession (expect down if chain
   search now ends chains in safer places).

## Risk

Medium.

- The +1e6 shoot spike is unchanged, but the state2 wide-corner
  bonuses (`point_line` × 2.5 near the goal-mouth points) interact
  with a heavily-marked goal-mouth receiver. The pressure penalty
  may slightly discourage cross-to-goal-mouth chains; the cross
  bonus (+35 from spica's chain_action patch) should still dominate
  but the delta needs measurement.
- `state.getPlayers` allocates a new `OpponentOrUnknownPlayerPredicate`
  on every eval. The base code already does this once per call (line
  202); we now call it twice in `evaluate_state` (once for the
  pressure check, once for the shoot check). Per-cycle cost is bounded
  but non-zero. If profiling shows it matters, hoist the call.
- All constants are tunable in one block. If `PRESS_PENALTY = 8`
  over-suppresses high-x chains, drop to 4 and rerun. If `SPACE_CAP`
  causes drift toward x≈-5 holders (clean space, low x), drop it.
