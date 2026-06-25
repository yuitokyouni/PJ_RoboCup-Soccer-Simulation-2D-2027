# Session handoff: 2026-06-25

Last session: Phase 5 → Phase 7 implementation + LEFT-side bias
investigation + match-by-match tactical analysis.

This file is the next session's STARTING POINT. Read this first.

---

## Where we are

### Code state (commit `1926cd1`)

- **Base**: cyrus-soccer-simulation-team @ 7283c0de + rapidjson vendor
  patch + my Phase 5/6/7 patches.
- **Binaries**:
  - `externals/src/cyrus-team-vanilla-snapshot/build/src/sample_player`
    — TRUE vanilla (rapidjson patch only; no Phase 5/6/7).
  - `externals/src/cyrus-team-v3-snapshot/build/src/sample_player` —
    improved (Phase 5/6/7 v2 SAME-SIDE pocket run for unum 11 Dembele).
- **Launchers**: `scripts/team_launchers/cyrus_{vanilla,improved}_{left,right}.sh`.
- **Experiments**: `experiments/vanilla_vs_improved_cyrus.yaml`
  (vanilla left, improved right). Two custom yamls for balanced eval
  live at `/tmp/balanced_van_left.yaml` and `/tmp/balanced_imp_left.yaml`
  (regenerate from `cyrus_vs_helios_smoke.yaml` pattern if missing).
- **Auto report**: `scripts/match_report.py` runs as a hook in
  `run_smoke_match.sh`; every match dir gets a `report.md`.

### Patch set (under `externals/patches/cyrus-team/src/phase5/`)

- `chance_signal.{h,cpp}` — opp-in-cone + teammate momentum + lane
  openness + counter-press recency. Continuous bias in
  `chain_action/action_chain_graph.cpp` per-candidate evaluator
  (`if cs > 0.7 forward_cat → +30 * (cs-0.7)/0.3`).
- `bhv_smart_clearance.{h,cpp}` + `territory_recovery_state.{h,cpp}` —
  prefer opp corner / past CB; reject opp-midfield band 10 < x < 25;
  push-up bias after kick.
- `counter_press_state.{h,cpp}` — possession transition tracker;
  aggression multiplier 1.5× for 50 cycles after losing in opp half.
  Mark-dash multiplier was wired and **reverted** (commit
  `6fdf442` reverts `a2d9d24`) — it was net-negative.
- `defense_block.{h,cpp}` — modulate_position called from
  bhv_basic_move::updateTarget. Attack phase: one-SB-push (LB unum 3
  for ball.y < -3, RB unum 4 for ball.y > 3, default LB at center).
  Same-side CDM drop (unum 6 for left attack, unum 7 for right).
  CF (unum 11) Dembele diagonal pocket run to **same-side** pocket
  (LB pushes → CF runs to LEFT pocket y=-12, x=ball.x+25 clamped 15-38).
  Defense phase: lateral shift toward ball, vertical compression for
  forwards, WB retreat (3-back when ball.x < -10).

### apply_phase5.sh (commit history)

- `e6d7976` — initial framework
- `041da9e` — one-SB-push + CDM CB-ization (improved beats vanilla n=3
  pre-balanced-eval)
- `a2d9d24` — mark dash multiplier (REVERTED in `6fdf442`)
- `1926cd1` — Phase 7 v2 SAME-SIDE pocket

## Evaluation summary

### What was claimed and what's true

| Eval setup | Result | Verdict |
|---|---|---|
| van_LEFT n=20 unbalanced | vanilla +0.50 p<0.05 | **CONFOUNDED**: improved on right |
| imp_LEFT n=10 sanity | improved +0.40 | small-n variance |
| **Balanced n=30 (15 van_L + 15 imp_L)** | **diff -0.033** | **statistical tie** — true effect ~0 |
| vanilla vs vanilla n=20 self-swap | LEFT 20%, RIGHT 30% | **no harness bias** |
| helios vs helios n=10 | LEFT 40% | **no harness bias** |
| **Cross-binary cyrus** | LEFT 50% wins in decisive | **bias real in cross-binary only** |

### The LEFT-side bias mystery — UNRESOLVED

The investigation workflow (`wjeqjvbbt`) ran 7 parallel probes. The
empirical findings are airtight:

- **Same-binary tests** (vv, helios) show **no side bias**.
- **Cross-binary** (vanilla vs improved) shows **~40 pp LEFT-side bias**.
- Therefore the asymmetry **must come from differences between vanilla
  and improved**, i.e., from my Phase 5/6/7 patches.

The agent's HIGH-severity claims about specific hard-coded unum/y
assumptions in defense_block.cpp were code-inspected and **rejected**:
those code paths use team-frame coordinates that librcsc auto-mirrors
via Vector2D::reverse() (both x and y negated for right-side teams).
By inspection the patches are side-symmetric.

So the asymmetry comes from **subtler interactions** I could not
pinpoint by code reading. Candidates remaining:

1. **counter_press_state singleton** — global state persists across
   cycles. Initialization order or cycle-zero state may differ by side.
2. **action_chain_graph wedge / side-switch bias interaction** — my
   `tp.y > 0`-style checks combined with Cyrus's existing
   `evaluate_state2` hard-coded points may bias asymmetrically.
3. **chance_signal.cpp computation** — uses `wm.opponents()` and
   `wm.teammates()`. If iteration order differs by side, accumulated
   floating-point sums could go non-deterministic.
4. **Cyrus's pass-prediction DNN** (`pass_prediction_yushan_w_*.txt`) —
   weights trained on left-attack data, may misfire when team is on
   right. Inherited from vanilla but interaction with chance_signal bias
   could amplify on one side.

### Smoking-gun test (NOT yet run)

**imp vs imp self-swap n=10**. If imp shows a side bias against
**itself**, the bug is internal to my patches (likely singleton state
or floating-point order). If imp shows no bias against itself, the
bias is **in the interaction** between my patches and Cyrus's
existing asymmetric code. This experiment is the cleanest next step.

Run with:
```
# Create /tmp/ii_left.yaml mirroring vv_LLleft.yaml but with both
# launchers pointing at cyrus-team-v3-snapshot.
# Need two distinct team names (<=15 char each):
#   CYRUS_IMP_LL, CYRUS_IMP_RR
```

---

## Tactical insights from match-by-match analysis (3-1 IMPROVED win)

Watched imp_LEFT m1 (CYRUS_IMPROVED 3-1 CYRUS_VANILLA) in rcssmonitor.

### Goal 1 (improved scored)

Pattern: improved #10 plays a **lateral pass then makes a forward run
to receive a return ball** (classic one-two / wall pass into the
half-space pocket).

**Source**: Cyrus's existing `chain_action/actgen_self_pass.cpp` —
generates "pass to teammate, run to receive return" as a chain
candidate. **Vanilla also has this.** The pattern is original Cyrus,
not from my patches.

**My patches' contribution**: the `chance_signal` continuous bias
amplifies forward-category chain options when signal > 0.7. This
**may** increase the rate at which actgen_self_pass candidates are
selected over safer options, but the tactical pattern itself is
vanilla Cyrus.

### Goal 4 (improved conceded)

Pattern: vanilla #11 (CF) drops toward midfield triggering a wedge-
pass option from vanilla carrier. Improved #6 (CDM) commits to
**intercept the wedge pass** (per Cyrus's `Body_InterceptPlan` firing
when `self_min <= 3`). This pulls #6 out of central midfield. Vanilla
#10 then **runs into the vacated zone**, receives a flick or short
pass, and shoots from a free position.

**Root cause**: Cyrus's `bhv_basic_move.cpp` lines 83-85 invoke
`Body_InterceptPlan` **with no position-awareness**. The intercept
fires whenever the player can reach the ball, regardless of whether
breaking shape leaves a critical zone exposed. This is a structural
weakness in vanilla Cyrus shared by improved.

**User's tactical clarification**: this is NOT the "CDM follows the
dropping CF" failure mode (zonal mark vs man mark). It is the
**"CDM is drawn out by the wedge pass intercept option"** failure
mode. The fix is at the intercept layer, not the mark layer.

---

## Next-session plan (priority order)

### P0 — Run imp-vs-imp self-swap smoking-gun test (1 hour)

Goal: identify whether the LEFT-side bias is **internal to my
patches** (singleton state, floating-point) or **interaction with
Cyrus's asymmetric code**.

- Write `/tmp/ii_LLleft.yaml` and `/tmp/ii_RRleft.yaml` (two distinct
  team names, both binaries pointing at cyrus-team-v3-snapshot).
- Run n=10 each.
- If imp_LL beats imp_RR (or vice versa) by > 20pp, asymmetry is
  internal. Bisect by disabling Phase 5/6/7 modules one at a time
  rebuilding between each.
- If close to 50/50, asymmetry is interaction. Look at Cyrus's
  existing `evaluate_state2` and `action_chain_graph.cpp:940-950`
  hard-coded `unum == 8 || == 4 || == 10` + `ball.y > 15` block.

### P1 — Phase 8: position-aware intercept (CDM hold-shape)

This is the **highest-impact tactical addition** identified this
session. The fix:

```cpp
// externals/patches/cyrus-team/src/phase5/intercept_discipline.{h,cpp}
namespace cyrus_phase5 {
    bool intercept_safe_for_unum( int self_unum,
                                  const rcsc::WorldModel & wm );
}
```

Logic:
1. Only apply to CDM (unum 6, 7). Other roles unchanged.
2. Compute the intercept point at `wm.ball().inertiaPoint(self_min)`.
3. Check if a teammate is positioned in the zone behind us
   (midpoint between self.pos and our_goal). If no teammate within
   8m, refuse intercept.
4. Check opponents: if any opponent is between us and our goal AND
   their velocity points toward our half, refuse intercept (someone
   is making a runner run).
5. If safe: allow Body_InterceptPlan. Else: skip and continue to
   formation-position logic.

Insert at top of `bhv_basic_move::execute` before the
`Body_InterceptPlan().execute(agent)` call:

```cpp
if ( cyrus_phase5::intercept_safe_for_unum( wm.self().unum(), wm ) ) {
    if ( Body_InterceptPlan().execute( agent ) ) {
        return true;
    }
}
```

Estimated impact: cuts conceded goals from wedge-pull-out scenarios
significantly. May be the lever that moves balanced n=30 from
-0.033 to a real improved win.

### P2 — Real verification (balanced n=30 after each change)

User's hard-won insight from this session: always use balanced
evaluation (15 with each team on LEFT) because cross-binary side
asymmetry exists. Never trust unbalanced n=20 again.

### P3 — Look at Cyrus's `actgen_self_pass` improvements

Section in last user message: 1点目 was a one-two with #10's forward
run. To make this MORE frequent (which the user explicitly wants:
"こう言う裏抜けを狙っていくのが勝利への道"):

- Read `chain_action/actgen_self_pass.cpp` to understand candidate
  generation criteria.
- Bias toward candidates where:
  - Receiver is in the half-space behind opp DF line
  - Sender's opp DF is facing away (back turned, or velocity
    pointing toward own goal)
- Use DF body angle as input — currently underutilized.

---

## Hard-won lessons (do not unlearn)

1. **rcssserver has NO physical side swap at half-time.** Only the
   kick-off taker flips. Teams stay on their physical halves both
   halves. The auto-mirror is at the librcsc client level.

2. **Vanilla Cyrus is HARD to beat** because draws dominate (60% draw
   rate in cyrus vs cyrus). 1 goal/match is the typical effect-size
   ceiling. Need effect size > 0.5 goals/match to detect at n=30.

3. **Always balance side assignment in evaluation.** Variance from a
   single direction is large enough to make a clearly-stronger team
   look weaker.

4. **goaliesleep=3 patch is mandatory.** Without it, unum=10 can
   become goalie due to connection race, producing instant 32-0
   losses. Both launchers already apply this sed patch.

5. **Cyrus loads `data/settings/*.json` and `data/deep/*.txt` via
   PWD-relative paths.** Launchers must `cd "$CYRUS_SRC"` before exec.
   Without this, Cyrus runs with no opponent profile and loses 0-31.

6. **The patches are reproducible via `apply_phase5.sh`.** If the
   cyrus-team source tree is wiped, fetch + apply.sh +
   apply_phase5.sh restores the improved state. Build with
   `cmake -DCMAKE_PREFIX_PATH="$CYRUS_PREFIX" -DCMAKE_INSTALL_PREFIX=...`.

7. **rcssmonitor visualizes rcg files locally**, but the rcg must be
   downloaded — the cloud environment can render mp4 but cannot stream
   rcssmonitor to the user's browser. Use `SendUserFile` to ship the
   .rcg to the user's machine.

---

## File pointers for fast orientation

- **Patches**: `externals/patches/cyrus-team/`
- **Apply scripts**: `apply.sh` (rapidjson vendor) +
  `apply_phase5.sh` (idempotent, Python heredocs)
- **Build**: `scripts/build_externals.sh --only cyrus-team` (does
  cmake + make + install to install-cyrus)
- **Vanilla snapshot**: built once, committed to disk at
  `cyrus-team-vanilla-snapshot/`. Do not rebuild unless rapidjson
  patch needs updating.
- **Improved snapshot**: at `cyrus-team-v3-snapshot/`. Rebuild with
  `cd externals/src/cyrus-team-v3-snapshot/build && make -j` after
  modifying `src/phase5/*.cpp`.
- **Smoke harness**: `scripts/run_smoke_match.sh` (single match) +
  `scripts/run_batch_matches.sh` (n matches).
- **Report**: `scripts/match_report.py` runs auto post-match.
- **Notes from prior sessions**: `notes/2026-06-24_*` and
  `notes/2026-06-25_*`.

---

## TL;DR for the next session

1. Read this file.
2. P0: imp-vs-imp self-swap n=10, smoke gun for the bias.
3. P1: implement intercept_discipline.{h,cpp} (Phase 8).
4. P2: balanced n=30 evaluation.
5. Goal: beat vanilla by > 0.3 goal/match with p < 0.05.

The framework is solid. The patches compile. The eval methodology
is robust. The remaining work is targeted tactical primitives.
