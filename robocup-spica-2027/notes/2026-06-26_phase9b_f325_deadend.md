# Phase 9b: F325 re-author dead-end + Task (a) seed-pinning attempt

Date: 2026-06-26
Status: Task (b) closed as dead-end. Task (a) in progress.

## Context

Phase 9 left -0.767 ± 0.30 as the floor for Spica325 vs Vanilla.
User directive (post-summary): explore TWO orthogonal axes in parallel:

- **(a)** Eigen/Boost pinning to undo env drift (cf. literal-vanilla
  self-swap was -0.65 ± 0.23 in Phase 9 → drift is real).
- **(b)** Re-author F325 conf via FormationEditor (or equivalent) so
  Cyrus's pass predictor sees positions it was trained on.

## Task (b): F325 re-author — DEAD-END

### Approach

`scripts/generate_f325_v2.py` rebuilds the nine `F325_*.conf` files by:

1. Borrowing F433's 48 ball-sample positions verbatim → Delaunay
   triangulation has the same density Cyrus's pass predictor was
   trained on.
2. Computing per-ball-position 3-2-5 player coordinates from rule
   functions so positions DO move with the ball (v1 generator was
   static and failed for that reason).

### v2 → v3: unum mapping fix

Phase 5 patches hardcode unum:

- `is_wing_back(unum)`        → unum 3, 4  → pushed to width ±22
- `is_build_up_drop_cdm(unum)`→ unum 6, 7
- `is_false_nine(unum)`       → unum 11

v2 mapped unum 2/3/4 as the 3 CBs, so the WB patch ripped CBs to ±22 →
catastrophic CB-line collapse (0-4, 1-5). v3 fixed the mapping:

- unum 2, 5, 8 = 3 CBs (LCB / MCB / RCB)
- unum 3, 4   = LWB, RWB
- unum 6, 7   = LDM, RDM
- unum 9, 10  = LIF, RIF
- unum 11     = CF

### v3 result — also dead

n=4 smoke vs Vanilla under the v3 conf: 0-5, 0-7, 0-4, 0-4 (mean -5).
F325 conf is fundamentally incompatible with Cyrus's tactical
decision-making — likely because:

- Cyrus's pass-prediction DNN was trained on F433-shape position
  distributions; the 3-2-5 distribution puts attackers / defenders
  outside the input manifold.
- Setplay / kickin / goal-kick variants under F325 also need
  retraining of the chain-action chooser, which is not patchable
  from the conf files alone.

**Conclusion: do not pursue further F325 conf work without retraining
the chain-action / pass-predictor models.** The v3 generator and the
nine modified F325 conf files are committed as evidence so a future
session can resume from the same starting point, but `Other.json`
is reverted to `"Formation": "433"` so the live binary stays on the
F433 path.

## Task (a): env-drift pinning — current angle

### Direct apt pin: blocked

`apt-cache madison libeigen3-dev libboost-system-dev` shows only one
version each (Eigen 3.4.0-4, Boost 1.83.0). No source-package back-port
available without compiling from source.

### Alternative: rcssserver `player::random_seed`

Found `player::random_seed=<INTEGER>` exposed via rcssserver's player
namespace (serverparam's `random_seed` is commented out in 19.0.0;
the active seed lives in playerparam).

Hypothesis: if the seed propagates fully, two runs of the same
binaries with the same seed should produce bit-identical match traces.
That gives us a deterministic control axis: any divergence in
Spica325-vs-Vanilla can be attributed to the patch under test rather
than scheduler / RNG noise.

### Harness fix (committed alongside this note)

`scripts/run_batch_matches.sh` had a `SHAPE` regex that only accepted
`server::...` options. `player::random_seed=42` was being silently
stripped. Regex updated to allow `(server|player|CSVSaver)::...`.

### Experiment

`experiments/seeded_vanilla_repro.yaml`: vanilla self-swap n=4 with
`player::random_seed=42`. Acceptance criterion: all 4 matches identical
(same scoreline AND same metrics.json::goals timing). Result will be
appended below.

### Reproducibility result — seed insufficient

n=4 with `player::random_seed=42`, both binaries from the vanilla
snapshot (named `CYRUS_VAN_LL` LEFT, `CYRUS_VAN_RR` RIGHT):

| Match | LL | RR | Result    |
|-------|----|----|-----------|
| 1     | 0  | 1  | away_win  |
| 2     | 2  | 1  | home_win  |
| 3     | 0  | 1  | away_win  |
| 4     | 0  | 2  | away_win  |

Mean LL goal_diff = -0.75 → matches the previous "literal vanilla
self-swap = -0.65 ± 0.23" floor finding.

Critically: server log confirms `Using given Hetero Player Seed: 42`
applied (so the seed reached the server), but matches are NOT
identical. The server seed only controls hetero-player generation;
the client AI's stochastic decisions come from a separate engine.

### Root cause (located in librcsc)

`externals/src/librcsc/rcsc/random.h:62`:

```cpp
RandomEngine()
    : M_engine( std::random_device()() )
  { }
```

The player-side `std::mt19937` is seeded from `std::random_device`
(OS entropy / `/dev/urandom`). Per-match this gives a fresh seed,
which dominates the variance even with the server seed pinned. Same
pattern in `librcsc/rcsc/common/player_type.cpp:74-75` and several
`librcsc/rcsc/ann/*.cpp` engines.

### Strategic implication

Server-layer seed pinning is necessary but not sufficient. To get
deterministic matches we'd need to patch librcsc to seed from an env
var (e.g. `RCSC_RANDOM_SEED`) and rebuild librcsc + both Cyrus
snapshots. That's a tractable 30-minute change but it only buys us
TIGHTER CIs at the same MEAN — it does not change Spica325's
-0.77 vs Vanilla expected value. Reducing variance moves us closer
to the floor, not above it.

So seed pinning **alone is not a path to >0**. Two follow-ups remain
on the (a) axis:

1. **Compiler swap (gcc-13 → gcc-12)**: a different toolchain may
   produce different vectorization and call-order patterns, which
   could shift the EXPECTED value (not just the variance).
2. **Client-side RNG patch + per-seed n=30**: if we can sweep many
   seeds and find any seeds where Spica wins, we have evidence that
   the floor IS env-dependent rather than intrinsic; useful even if
   the mean stays negative.

Task #39 stays open with a re-scoped target: try (1) gcc-12 rebuild
as the next iteration. If that also lands at -0.77, accept the floor
and pivot the project narrative to "Spica325 vs helios-base" where
the +5.1 / 10-0-0 result IS positive (already committed).

## Files touched

- `scripts/generate_f325_v2.py` (new)
- `externals/patches/cyrus-team/src/formations-dt/F325_*.conf` (9 files)
- `scripts/run_batch_matches.sh` (SHAPE regex)
- `experiments/seeded_vanilla_repro.yaml` (new)
- `notes/2026-06-26_phase9b_f325_deadend.md` (this file)
