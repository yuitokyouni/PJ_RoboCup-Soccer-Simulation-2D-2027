# Phase 4: Defensive Duty Layer (C++ patch to helios-base)

Date: 2026-06-24
Branch: claude/eloquent-turing-id7o0z

## What

A small C++ patch to helios-base that adds a per-cycle defensive duty
assignment in front of `Bhv_BasicMove`'s default chase-the-ball
heuristic. Three duties are computed deterministically by every player
independently from the WorldModel each cycle, so the 11 agents agree
without communication:

- **PRESS** (Phase 4a) – the closest field teammate to the opponent
  ball carrier closes down on a goal-side angle. If the ball is
  interceptable in <=4 self-steps it just intercepts instead.
- **COVER** (Phase 4c) – any other field player who is closest to an
  unmarked opponent inside our half claims that opponent and moves
  2.5m goal-side of them. Picks the opponent closest to our goal
  (most dangerous).
- **NONE** – falls through to existing helios `Bhv_BasicMove`.

Goalie (unum=1) is excluded; goalie keeps its own role.

The duty layer only fires when:

- the ball has a `kickableOpponent()`, AND
- the ball is in our half-ish (`ball_pos.x <= 5.0`).

In opponent territory the formation file drives positioning. This
keeps offensive shape intact and only changes defensive behavior.

## Files

Under `externals/patches/helios-base/src/player/`:

- `defense_duty.h` / `defense_duty.cpp` – duty enum + assigner
- `bhv_press_ball_carrier.h` / `.cpp` – PRESS behavior
- `bhv_cover_goal_side.h` / `.cpp` – COVER behavior
- `apply.sh` – idempotent installer that:
  - copies the 6 new files into `helios-base/src/player/`
  - inserts `#include`s after `bhv_basic_tackle.h`
  - inserts the duty-dispatch block after the function-scope
    `const WorldModel & wm = agent->world();` in `bhv_basic_move.cpp`
  - patches `Makefile.am` to compile the new sources
  - markers (`PATCH_4ACD_BEGIN`, `defense_duty.cpp`) make it safe to
    re-run

`scripts/build_externals.sh::build_helios_base()` calls `apply.sh`
before bootstrap so the regenerated `Makefile.in` picks up the new
sources.

## Why patch instead of fork

CLAUDE.md rule: don't touch third-party code in place. The patch
lives under `externals/patches/` and is applied at build time, so:

- `git diff` of helios-base under `externals/src/` is reproducible
  from the patch directory alone
- the patch is the unit of review
- `externals/src/helios-base/` stays a vanilla git checkout we can
  re-clone

## Build

```
bash scripts/build_externals.sh --only helios-base
```

Patch applies idempotently, `./bootstrap` regenerates `Makefile.in`
from the patched `Makefile.am`, then a standard configure + make
links 4 new `.o` files into `sample_player`:

- `sample_player-bhv_basic_move.o` (modified)
- `sample_player-bhv_cover_goal_side.o` (new)
- `sample_player-bhv_press_ball_carrier.o` (new)
- `sample_player-defense_duty.o` (new)

## Smoke result (n=3, SMOKE_ONLY)

`experiments/helios_vs_3_2_5_smoke.yaml`, both teams use the patched
binary; HELIOS_L runs default 4-2-3-1 formation, HELIOS_3_2_5 runs
the user's 3-2-5 wingback-fluid formation.

| match | home (HELIOS_L) | away (HELIOS_3_2_5) | goal_diff |
|-------|-----------------|---------------------|-----------|
| 1     | 10              | 0                   | +10       |
| 2     | 6               | 5                   | +1        |
| 3     | 8               | 5                   | +3        |
| mean  | **8.0**         | **3.33**            | **+4.67** |

For comparison, **v9 park-the-bus baseline** (formation-only,
unpatched binary): mean conceded by 3-2-5 = **8.33**, mean scored ≈ low.

n=3 is too few for any real claim. Directionally:

- **No crashes** – patched binary completes clean 6000-cycle matches.
- **Mean conceded roughly flat vs v9** (8.0 vs 8.33).
- **Mean scored up** (3.33 vs near-zero for v9). The duty layer only
  fires in our half so offense is undisturbed.
- **High variance** (10-0, 6-5, 8-5) – match 1 looks like a tactical
  collapse, matches 2/3 are competitive.

## Untested assumptions / known limitations

- `wm.kickableOpponent()` returns the ball carrier only when the
  opponent's `is_kickable()` flag is set. If the carrier is dribbling
  between kicks, no PRESS duty is assigned that cycle – we fall
  through to chase logic.
- Stale opponent observation: `posCount() > 8` excludes the cover
  target. Tunable; not validated.
- COVER point is 2.5m goal-side along the opponent→our-goal vector.
  No accounting for shooting angle or passing lane.
- Each player runs the assigner independently. Floating-point
  determinism is assumed across `g++ -O2` runs on the same binary;
  the 0.5m unum-tiebreak gives most ties some slack but does not
  guarantee 11-agent consensus under unusual numeric inputs.
- `ball_pos.x > 5.0` cutoff is rough; in a 3-2-5 the wingbacks
  might want to press higher.

## Next

- Run >= 30 matches with `make batch` to get out of SMOKE_ONLY
  regime, then `make compare` against the v9 baseline summary.
- If conceded doesn't drop, the bottleneck is likely the COVER
  point geometry (too passive) or the press cutoff (too late).
