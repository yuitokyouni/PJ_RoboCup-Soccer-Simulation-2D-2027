# PSG-loop iter-62 candidate — third-man run pattern bonus (path-based)

Date: 2026-06-28
Status: **UNVERIFIED** — code change only; no batch evaluation yet.
File: `externals/patches/cyrus-team/apply_phase5.sh` (Step 7b)
Target file (patched in-place by the script):
`sample_field_evaluator.cpp::SampleFieldEvaluator::operator()`

Supersedes the (closed) iter-61 candidate A (pressure penalty). The
pressure penalty was rejected before evaluation because it would
suppress spica's observed scoring pattern: every recorded goal
through iter 47 lands at `x ∈ [+41, +48], |y| < 8`, with the scorer
heavily marked by both opp CBs and the GK. A penalty for being
marked would push chains away from the only positions where spica
actually scores.

This candidate A' goes the OPPOSITE direction: REWARD a specific
multi-step attacking PATH SHAPE that is known to break central
defences, rather than penalising the resulting marked position.

## Hypothesis

The baseline `operator()` of `SampleFieldEvaluator` receives three
arguments — `state`, `wm`, and `path` — but uses only `state` and
`wm`. The chain search's score is the final state value; how the
chain got there is ignored. Every spica multi-step attacking bias
through iter-60 (wedge ×2 +50, cross +35, through-ball +25,
side-switch ±15, mirror +20, chance-signal ±30) lives in
`action_chain_graph.cpp` and only fires for the FIRST step's
candidate — it cannot encode "this chain ENDS with a through-ball
after a lay-off".

Tactical claim (from user discussion): the way to break a central
block is the third-man combo —

```
MF1 -> false-9 (feet)   [step 0, forward feed]
       false-9 -> MF2   [step 1, lay-off; CB has stepped forward]
                MF2 -> RUNNER (behind CB)  [step 2, through-ball]
```

This is a four-actor pattern (MF1, false-9, MF2, RUNNER) that today
does not appear as a single high-value chain in the search, because:

1. step 1 (lay-off) has Δx < 0 — the per-candidate evaluator
   penalises it relative to a forward alternative.
2. the search never gets to score step 2 (the actual through-ball)
   as a CONTINUATION of the lay-off, because step 1's per-candidate
   score is too low to survive pruning.

A path-shape bonus says: "lay-off followed by through-ball, by a
different receiver" is a structural win — score the chain as a
whole, not as the sum of single-step scores.

## Detection

In `operator()`, on the non-penalty branch:

```cpp
if ( path.size() >= 3
     && state.ball().pos().x >= 25.0
     && path[0].action().category() == Pass
     && path[1].action().category() == Pass
     && path[2].action().category() == Pass )
{
    p0_from = wm.ball().pos();
    p0_to   = path[0].action().targetPoint();
    p1_to   = path[1].action().targetPoint();
    p2_to   = path[2].action().targetPoint();

    step0_forward = (p0_to.x - p0_from.x) > 5.0;
    step1_layoff  = (p1_to.x - p0_to.x) < -1.0
                    && (p1_to - p0_to).r() < 12.0;
    step2_through = (p2_to.x - p1_to.x) > 15.0;

    rcv0 = path[0].action().targetPlayerUnum();
    rcv2 = path[2].action().targetPlayerUnum();
    third_man = (rcv0 > 0 && rcv2 > 0 && rcv0 != rcv2);

    if (step0_forward && step1_layoff && step2_through && third_man) {
        result += 40.0;
    }
}
```

### Constants (tunable A/B handles)

All as `static const double` inside the inserted block:

| name | value | meaning |
|------|-------|---------|
| `FEED_FORWARD_MIN`    |  5.0 | path[0] must advance ball Δx > this |
| `LAYOFF_BACK_MAX`     | -1.0 | path[1] must retreat ball Δx < this |
| `LAYOFF_LEN_MAX`      | 12.0 | path[1] vector length < this (m) |
| `THROUGH_FORWARD_MIN` | 15.0 | path[2] must advance ball Δx > this |
| `TMR_BONUS`           | 40.0 | bonus magnitude |

Plus two hard gates:
- `state.ball().pos().x >= 25.0` — final state in attacking third.
- `rcv0 != rcv2` — the through-ball goes to a player other than the
  one who received the feed (this is the literal "third man").

## Why this is the right shape for spica

- Spica's existing wedge bonus (+50) already feeds WB → false-9 in
  the half-space. That bonus fires on step 0 of this exact pattern.
  Adding the path-shape bonus *composes* with the wedge bonus rather
  than competing with it — the chain wedge → lay-off → through can
  now collect +50 (wedge) + +25 (through-ball per-candidate bias)
  + +40 (TMR path shape) = +115 over a chain that just goes forward
  three times.
- The Y-symmetrised F433 has runners on both sides (u9 LF, u10 RF).
  The pattern is naturally Y-symmetric — no special-case for the
  observed -y scoring bias is needed; chains involving u10 on +y
  side now have a structural shot at scoring +40.
- A receiver chain that LOOKS like third-man but isn't (e.g.
  rcv0 == rcv2 because the lay-off bounces straight back) is
  explicitly rejected.

## Magnitude check

For a path ending at the PA edge:
- final state evaluation (evaluate_state) ≈ +67 at (45, 0).
- Without path bonus: chain candidates that get there via straight
  passes vs via third-man combo score identically.
- With +40 bonus on TMR-shaped chains: third-man chains score ~+107.
- Shoot spike +1e6 unchanged. TMR bonus does not override shot.

So a chain WITH a third-man shape outscores a chain that doesn't by
~ 60 % at the same final position. Should bias the search but not
overwhelm.

## What this is *not*

- Not a defensive change. Touches only the offensive chain
  evaluation in operator().
- Not a state-evaluator change. Adds NOTHING to evaluate_state /
  evaluate_state2 / evaluate_state_penalty (they remain as in the
  baseline cyrus tree).
- Not a per-candidate bias. Lives at the chain-final scoring level
  where it can see the path.
- Not coupled to the closed iter-61 pressure-penalty change. The
  two are orthogonal; if a later experiment wants to combine them,
  it can.

## Rollback

Delete the Step 7b block in `apply_phase5.sh` (between the markers
"Step 7b: patch sample_field_evaluator.cpp::operator()" and
"Step 8: patch CMakeLists.txt"). Then refresh the source tree:

```
make fetch-externals ONLY=cyrus-team FORCE=1
bash externals/patches/cyrus-team/apply_phase5.sh externals/src/cyrus-team
```

The python step uses the `PHASE5_FEVAL_PATH` sentinel and is
idempotent on re-apply — the sentinel is also the rollback marker
when grepping the source.

## Evaluation plan

Per `docs/CHANGE_EVALUATION_PROTOCOL.md`:

1. `make fetch-externals ONLY=cyrus-team FORCE=1` then
   `bash externals/patches/cyrus-team/apply_phase5.sh externals/src/cyrus-team`.
2. `grep -c PHASE5_FEVAL_PATH externals/src/cyrus-team/src/sample_field_evaluator.cpp`
   should print 1 (the single block in operator()).
3. `cmake --build externals/src/cyrus-team/build`. The patch uses
   only types already visible in this TU (rcsc::Vector2D,
   CooperativeAction::Pass enum; CooperativeAction full type is
   pulled in via sample_field_evaluator.h → field_evaluator.h →
   cooperative_action.h).
4. Variant batch vs Vanilla at iter_041 / iter_047 baseline N. Same
   `EXTERNALS.lock` as baseline.
5. `make compare BASELINE=<iter_041 summary> VARIANT=<iter-62 summary>`.
   Primary metric: `mean_goal_diff` delta with 95 % CI.
6. Secondary metric: `psg_ledger.py` — chain-quality breakdown.
   Expect:
   - increase in 3+ kick goals (through_ball flag set, kick_chain
     length 3+);
   - approximately unchanged 2-kick goals (TMR requires 3 steps);
   - +y side goals appear at all (the symmetric trigger should
     unblock the +y attack drought noted in iter 17/19/27/28
     diagnostics).

## Risk

Medium.

- The TMR detector requires the chain search to actually EXPLORE
  depth ≥ 3. If spica's effective search depth is shallower (because
  pruning kills lay-off candidates at step 1), the bonus never fires
  and the change is a no-op. In that case the right next step is to
  raise the chain search depth, not to tune the detector.
- Detector false positives: a chain that happens to satisfy the
  geometric thresholds without being a real third-man combo gets
  +40. The two hard gates (rcv0 ≠ rcv2 and final x ≥ 25) make this
  unlikely to dominate but they do not eliminate it.
- Bonus magnitude: 40 is conservative relative to the existing
  per-candidate bonuses (wedge +50, cross +35). If TMR chains
  systematically over-fire and over-score, drop to 25 and re-run.
  If they never appear despite the rule firing in dlog, raise to 60.
