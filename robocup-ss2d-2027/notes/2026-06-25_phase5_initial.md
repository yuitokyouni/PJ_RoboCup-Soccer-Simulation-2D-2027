# Phase 5a-e: 3-2-5 + possession behavior on Cyrus (initial pass)

Date: 2026-06-25
Branch: claude/eloquent-turing-id7o0z

## What landed

Full Phase 5 framework on top of `cyrus-soccer-simulation-team`:

| Module | Files |
|---|---|
| 5a F325 | `externals/patches/cyrus-team/src/formations-dt/F325_*.conf` (9 files) + Strategy enum/load/dispatch patches in `strategy.h` / `strategy.cpp` |
| 5b chance signal | `phase5/chance_signal.{h,cpp}` + inline patch to `chain_action/action_chain_graph.cpp` |
| 5c smart clearance | `phase5/bhv_smart_clearance.{h,cpp}` + `phase5/territory_recovery_state.{h,cpp}` + inline patch to `chain_action/bhv_chain_action.cpp` |
| 5d counter-press state | `phase5/counter_press_state.{h,cpp}` + tick hook in `bhv_basic_move.cpp` |
| 5e defense block + WB retreat | `phase5/defense_block.{h,cpp}` + position-modulation call in `bhv_basic_move.cpp::updateTarget()` |
| Glue | `apply_phase5.sh` (idempotent, Python heredocs), `CMakeLists.txt` glob-add for phase5/*.cpp, `Other.json` Formation set to "325" |

`externals/patches/cyrus-team/apply_phase5.sh <cyrus-tree>` re-applies the whole set from a vanilla Cyrus checkout.

## Build

```
make fetch-externals                           # picks up cyrus-lib (branch=cyrus), cppdnn, cyrus-team, rapidjson
bash scripts/build_externals.sh --only cyrus-lib
bash scripts/build_externals.sh --only cppdnn
bash scripts/build_externals.sh --only cyrus-team   # auto-runs apply.sh + apply_phase5.sh
```

Build clean after fixing six author-side issues:
- chance_signal.cpp / counter_press_state.cpp declared `dlog` without namespace; fixed to `rcsc::dlog`.
- bhv_smart_clearance.cpp used `<rcsc/action/...>` headers that don't exist in this librcsc fork (Cyrus's body actions live under `basic_actions/`, included via relative path).
- bhv_smart_clearance.cpp used non-existent `rcsc::PlayerPtrCont`; real type is `rcsc::PlayerObject::Cont`.
- Body_KickOneStep is unqualified (no `rcsc::` prefix) because Cyrus team files put `using namespace rcsc;` at TU scope.
- sample_field_evaluator.cpp has no `wm` in scope for `evaluate_state(const PredictState&)`; chance_signal hook moved from there to `action_chain_graph.cpp` where the per-candidate evaluation has wm.
- chance_signal.cpp's counter_press extern hooks (`counter_press_last_recovery_*`) get strong overrides from counter_press_state.cpp; required adding public `last_win_cycle()` / `last_win_in_opp_half()` accessors.

## Result (n=3, SMOKE_ONLY)

Patched CYRUS_L vs Phase-4-patched HELIOS_R:

| run | match scores | mean CYRUS | mean HELIOS |
|---|---|---|---|
| vanilla Cyrus baseline (F433, no Phase 5) | 16-0, 9-0, 13-0 | **12.67** | **0** |
| Phase 5 v1 (aggressive chance bias: +30/-20/+15) | 3-1, 9-0, 13-0 | 8.33 | 0.33 |
| Phase 5 v2 (softened: +30/-8/+6) | 6-0, 8-1, 4-0 | **6.0** | **0.33** |

**Net regression vs vanilla.** Phase 5 framework engages (cycle distributions changed, F325 conf files load, Other.json reports Formation="325"), but the initial tuning costs offensive output.

Likely root causes, in priority order:

1. **F325 formation itself is less offensively dense than F433** — the 3-2-5 has 5 forwards but no wide CDM to support them in chain action. Cyrus's pass-prediction DNN was trained on 4-3-3 patterns; pass success in 3-2-5 may be systematically lower.
2. **Defense block vertical compression too eager** — forwards capped at `ball.x - 2.0` whenever defending, which when ball is at x=-10 keeps the three SFs deep in midfield. When possession is won, they're not high enough to receive forward passes.
3. **Smart clearance possibly firing during legitimate possession** — `Bhv_ChainAction::hold_ball()` fallback was patched to attempt smart clearance first; if hold_ball() is invoked more than the survey suggested, this kicks the ball away unnecessarily.

## Untested assumptions

- F325 confs were mechanically converted from `experiments/helios_3_2_5_formations/*.conf` (role names → `Player`, types → `MF`). Delaunay sample points were NOT re-tuned for the Cyrus position resolver. They may not produce coherent positions.
- Phase 5 dlog tags are emitted (ChanceSignal=, [CounterPress] LOST/WON, [DefBlock] shift=) but were not inspected this session.
- Counter-press aggression multiplier `aggression_multiplier(cycle_now)` is computed but no consumer reads it yet — the booster hooks into mark/block decision wasn't wired in.
- Smart clearance never observed firing in the dlog; could be that hold_ball() isn't called in our typical match flow.

## Next iteration plan (NOT YET DONE)

In priority order:

1. **Isolate F325 vs hooks contribution** — run vanilla Cyrus with `Other.json` Formation="325" but Phase 5 hooks GUARDED off (compile-time flag). If F325-only is still ~6 goals/match, the 3-2-5 itself is the bottleneck and we need to rework the conf files.
2. **Soften Phase 5e vertical compression** — change `max_forward_x_when_defending` from `ball.x - 2.0` to `ball.x + 8.0` (forwards stay AHEAD of ball when possible, only drop when ball is very deep).
3. **Add a "we have the ball" guard to smart clearance** — `hold_ball()` is supposed to be a last-resort, but make sure we only clear when REALLY no chain available.
4. **Wire counter-press aggression into bhv_block / bhv_mark_execute** — currently CounterPressState updates correctly but no behavior consumes `aggression_multiplier()`. Multiply Cyrus's mark pursuit distance by it.
5. **Batch n=30 to exit SMOKE_ONLY** and get real statistical signal.
