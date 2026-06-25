# Phase 8 negative result: 2026-06-25

Continuation of the 2026-06-25 session handoff. P0 + P1 + P2 all
executed. P1 produced a clearly negative result; Phase 8 disabled
via kill-switch.

---

## TL;DR

| Step | Result |
|---|---|
| P0: imp-vs-imp self-swap n=10 | **5-5-0 tie, mean_diff -0.20 ± 0.57 SE.** Confirms LEFT-side bias is NOT internal to my Phase 5/6/7 patches. |
| P1: Phase 8 intercept_discipline | **Code implemented + wired in.** |
| P2: balanced n=30 with Phase 8 on | **-2.07 goal/match REGRESSION** vs prior tie (-0.033). Catastrophic. |
| Phase 8 kill-switch | **Applied.** intercept_safe_for_unum() returns true unconditionally. |
| Sanity n=10 with kill-switch | _(filled in below)_ |

---

## P0 — imp-vs-imp self-swap (smoking gun)

Both binaries are the v3 improved snapshot; team names CYRUS_IMP_LL
(LEFT) and CYRUS_IMP_RR (RIGHT). n=10.

```
home_wins: 5    away_wins: 5    draws: 0
mean_home_score: 0.5 (LL on LEFT)
mean_away_score: 0.7 (RR on RIGHT)
mean_goal_diff: -0.2    se: 0.57    95% CI: [-1.32, +0.92]
```

**Verdict**: 50/50 within sampling noise. The LEFT-side bias observed
in cross-binary (vanilla vs improved) is therefore NOT a property of
my Phase 5/6/7 patches alone. It must come from the **interaction**
between my patches and Cyrus's existing asymmetric code.

The handoff already enumerated the candidates; the strongest one
visible to code inspection is `action_chain_graph.cpp:940`:

```cpp
if (wm.self().unum() == 8 || wm.self().unum() == 4 || wm.self().unum() == 10) {
    if (wm.ball().pos().x > 0 && wm.ball().pos().y > 15) {
        if (candidate_series.front().action().targetPoint().y < 15) {
            ev += 20;
```

`ball.y > 15` (positive only) without a mirrored `ball.y < -15` block
means evaluators on the right side of the pitch get a +20 boost on
"pull-back to centre" passes that left-side evaluators never see.
This is vanilla code, present in BOTH binaries; but interaction with
Phase 5/6/7's chance_signal bias likely amplifies it on one side.

The bias is benign for our purposes: it doesn't appear inside any
single binary (the two same-binary tests both show ~50/50). It only
manifests as a tilt when an improved binary faces a vanilla binary
across the dividing line. The fix lives upstream and is out of scope
for the Phase 5/6/7/8 work.

---

## P1 — Phase 8 implementation

Files added under `externals/patches/cyrus-team/src/phase5/`:

- `intercept_discipline.h` — public surface:
  `bool intercept_safe_for_unum(int self_unum, const WorldModel & wm)`.
- `intercept_discipline.cpp` — gate logic:
  - returns true (passthrough) for non-CDM uniforms (anything other
    than 6 or 7)
  - returns true when self can reach ball in ≤ 1 step
  - returns true when intercept inertia point is in opp half
    (`ipoint.x > 5.0`)
  - returns false when no teammate sits within 8m of midpoint between
    self and our goal AND an opponent with vel.x < -0.05 sits between
    self and our goal

`apply_phase5.sh` step 5c wraps the `Body_InterceptPlan().execute()`
call site in `bhv_basic_move::execute()` with the gate.

The reasoning came directly from the handoff's Goal 4 analysis:
vanilla's CDM commits to a wedge-pass intercept, leaves the central
zone, and the opposite striker exploits the gap. The gate was
supposed to refuse the intercept in exactly that scenario.

---

## P2 — balanced n=30 with Phase 8 on

Two legs, 15 matches each, side-balanced. Snapshot:
`externals/src/cyrus-team-v3-snapshot/` rebuilt with Phase 8 included.

### Leg 1: vanilla LEFT, improved RIGHT (n=15)

```
home_wins (vanilla):  13
away_wins (improved):  1
draws:                 1
mean home (van) score: 2.27
mean away (imp) score: 0.27
mean_goal_diff:       +2.00    se: 0.41   95% CI: [+1.19, +2.81]
```

### Leg 2: improved LEFT, vanilla RIGHT (n=15)

```
home_wins (improved):  0
away_wins (vanilla):  12
draws:                 3
mean home (imp) score: 0.20
mean away (van) score: 2.33
mean_goal_diff:       -2.13    se: 0.46   95% CI: [-3.03, -1.24]
```

### Combined (improved POV)

improved mean goal_diff per match:
- leg 1: -2.00  (improved was away, away_score - home_score)
- leg 2: -2.13  (improved was home, home_score - away_score)
- **combined: -2.07** (n=30, decisive)

For reference, the prior baseline (no Phase 8) from the handoff was
-0.033 (statistical tie, n=30). Phase 8 therefore introduced a clear,
side-symmetric **regression of ~2 goals per match**.

### Why the regression

Hypothesis: the gate refuses too often. The four-condition refuse
rule fires whenever:
- self_min ≥ 2 (almost always — the CDM is rarely literally on the ball)
- intercept point is in our half (typical defensive cycle)
- no teammate within 8m of `((self.x - 52.5) / 2, self.y / 2)` — that
  midpoint sits deep in our defensive third, where there's often only
  the centre-backs and goalie, none of whom are within 8m of the
  midpoint by the formation geometry
- opponent with `vel.x < -0.05` between us and goal — i.e., any
  opponent moving toward our goal at trivial speed

The conjunction is supposed to be rare ("exposed channel + active
runner"), but in practice it's ambient in any defensive cycle.
Result: the CDM almost never engages, and the team gets pushed to
the back foot every possession. Score lines like 0-6, 0-4, 0-3
dominate the leg 2 table.

### Per-match table (leg 2 = improved LEFT)

```
match  imp_score  van_score  diff
m1     1          3          -2
m2     0          6          -6
m3     0          4          -4
m4     0          3          -3
m5     0          0           0
m6     0          1          -1
m7     0          1          -1
m8     1          1           0
m9     0          3          -3
m10    0          0           0
m11    0          3          -3
m12    0          1          -1
m13    0          4          -4
m14    0          3          -3
m15    1          2          -1
```

12 losses, 3 draws, 0 wins. Improved scored more than 1 in zero
matches.

---

## Kill switch

`intercept_discipline.cpp::intercept_safe_for_unum` returns true
unconditionally as the first statement; the existing logic is
preserved underneath the early return so a future redesign can flip
the kill-switch off and tune the thresholds rather than reimplementing.

The patch source is at
`externals/patches/cyrus-team/src/phase5/intercept_discipline.cpp`;
re-running `apply_phase5.sh` propagates the kill-switch to a fresh
build.

---

## Sanity check (n=10 improved-LEFT with kill switch)

### Binary-aliasing bug uncovered first

After flipping the kill switch, an n=10 sanity check still returned
mean_diff ≈ -2.3. Investigation showed `setup_cyrus_snapshots.sh`'s
`cp -a $CYRUS $V3_SNAP` step preserves the cmake-generated `build.make`
verbatim, and that file hard-codes absolute paths back to `$CYRUS`.
Result: running `make` inside `$V3_SNAP/build` actually compiles and
links into `$CYRUS/build/src/sample_player`, and `$V3_SNAP/build/src/
sample_player` is never touched.

The launchers point at `$V3_SNAP/build/src/sample_player`, so even
with the kill switch applied + rebuilt, matches ran the original
Phase-8-on binary. Fix: rebuild via `make sample_player` inside
`$CYRUS/build`, then `cp $CYRUS/build/src/sample_player
$V3_SNAP/build/src/sample_player`. Long-term fix lives in
`setup_cyrus_snapshots.sh` (re-cmake the V3 build dir so its
build.make points at itself, not at $CYRUS).

### Sanity n=10 with the actually-updated binary

_(running)_


---

## What to try next

Phase 8 was the right diagnostic for the wedge-pull-out conceded-goal
pattern, but the trigger condition is too coarse. Options:

1. **Tighten the runner condition**: require `vel.x < -0.5` (real
   speed toward our goal) and require the runner to be ahead of us
   on the y-axis as well, so only forward-running opponents trigger
   the gate. Currently the gate fires on any opponent jogging back
   toward defence.

2. **Tighten the cover-behind**: instead of demanding a teammate
   within 8m of the deep midpoint, accept any teammate with
   `pos.x < self.x` as cover. The deep-midpoint check is too strict
   for the geometry of F325-on-433.

3. **Restrict firing window to counter-attack scenarios**:
   `cyrus_phase5::CounterPressState::counter_press_active()` already
   tracks "just lost the ball in opp half". Only refuse intercept
   in those cycles — the cycles where the wedge-pull-out actually
   happens.

4. **Different layer**: per the handoff, the conceded-goal pattern is
   "CDM drawn out by wedge-pass intercept option". Maybe the fix
   shouldn't be at the intercept layer at all. Cyrus's
   `chain_action/actgen_strict_check_pass.cpp` (or whichever generator
   produces the wedge-pass candidate from the carrier's POV) might
   need to score wedge-pass less attractive when an opp CDM is the
   nearest interceptor. That kills the bait pattern at the source.

(2026-06-25 will need a follow-up session to implement and re-evaluate.)
