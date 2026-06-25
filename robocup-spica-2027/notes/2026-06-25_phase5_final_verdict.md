# Phase 5 final verdict: n=30 RESEARCH_GRADE batch

Date: 2026-06-25
Branch: claude/eloquent-turing-id7o0z

## Setup

- **VANILLA** (home/left): cyrus-team master @ 7283c0d, **only** the
  rapidjson vendor patch applied, no Phase 5. Built into
  `externals/src/cyrus-team-vanilla-snapshot/build/src/`. `nm` confirms
  no `phase5/*` symbols in the binary.
- **IMPROVED** (away/right): same source + the full `apply_phase5.sh`
  patch set (5a F325, 5b chance_signal, 5c smart_clearance + territory
  recovery, 5d counter_press_state + mark-dash multiplier, 5e
  defense_block with WB retreat), F325-hybrid (F325 conf for defense
  + setplay + kickin, F433 conf for offense). Built into
  `externals/src/cyrus-team-v3-snapshot/build/src/`. `nm` confirms
  phase5 symbols present.

n=30, synch_mode=true, real rcssserver-19, all 30 matches completed.
`summary.json` reports `sample_regime: RESEARCH_GRADE` so the result
is gated out of SMOKE_ONLY for the first time in this project.

## Result

| metric | value |
|---|---|
| home_wins (vanilla) | **21 / 30** |
| away_wins (improved) | **9 / 30** |
| draws | 0 |
| mean home score (vanilla) | 1.37 |
| mean away score (improved) | 0.77 |
| **mean goal_diff (home − away)** | **+0.60** |
| std goal_diff | 1.25 |
| SE goal_diff | 0.23 |
| **95% CI for mean goal_diff** | **[+0.15, +1.05]** |

The 95% CI for the goal_diff mean is entirely positive — vanilla is
significantly stronger than the improved variant, p<0.05.

## Verdict

The session's goal "今までのcyrusよりも強くしていこう" was **not
achieved**. Phase 5 a–e, as implemented in this session, makes Cyrus
**measurably weaker by 0.60 goals per match (95% CI [0.15, 1.05])**.

## Root cause analysis (untested at this commit but consistent with prior ablation)

1. **F325 conf files are still in use** for defense + setplay + kickin
   (only offense was swapped to F433). The 3-2-5 sample-point geometry
   (mechanically converted from helios's 3-2-5) does not match
   Cyrus's pass-success and position-evaluator priors. The "hybrid"
   keeps the bad-fitting F325 confs in the modes where Cyrus spends
   most of its possession.
2. **Role assignment clash**: `updateFormation325()` maps unum 5 → pp_lb
   (left WB) and unum 8 → pp_rb (right WB). The F433 offense conf
   expects unum 3/4 as fullbacks. When attacking, role lookups
   (`Strategy::tmPost`) return positions that don't align with the
   conf's actual coordinates → players run to the wrong place.
3. **chance_signal forward-boost threshold** (0.7) is rarely crossed
   in Cyrus-vs-Cyrus matches (defenses are tight; opp-in-cone counts
   are usually > 1). Net effect: the boost almost never fires; only
   the chance-poor penalty fires, slightly suppressing forward chains.
4. **Counter-press dash multiplier** raises mark dash_power by 1.5×
   for 50 cycles after losing in opp half. This drains stamina; if the
   recovery doesn't actually work the team is left tired for the next
   transition.

## What would actually beat vanilla (NOT done in this session)

In rough order of expected payoff per hour of effort:

- **A. Run a clean F433-only Improved** — drop every F325 conf, keep
  Phase 5 hooks. Likely net-neutral vs vanilla; isolates whether the
  hooks themselves are negative. If positive: keep iterating on hook
  thresholds. If negative: see (B).
- **B. Disable hooks one by one** — bisect which Phase 5 module is
  the actual regressor at n=30.
- **C. Author F325 confs with FormationEditor** — interactive
  formation building so the Delaunay sample points match Cyrus's
  evaluator priors. Tactically faithful to the 3-2-5 vision.
- **D. Wire counter-press multiplier into bhv_block too** (it's
  currently only in bhv_mark_execute) — the counter-press window
  affects mark behavior but not block behavior, so the dual mechanism
  isn't fully active.
- **E. Switch chance_signal forward-boost threshold from 0.7 → 0.5
  AND increase magnitude** — the user's stated direction "チャンス
  時は迷わず縦" is implementable but the current threshold is too
  high.

## Status

- Framework is durable, reproducible via `apply_phase5.sh`, and
  documented. Future iterations on top of it will not have to redo
  the 5a–5e scaffolding.
- The Phase 5 hooks are tactically *plausible* but the cumulative
  effect at the current tuning is **regressive**. Beating vanilla
  Cyrus is unfinished work.
- This is the first **RESEARCH_GRADE** comparison in the project
  (n>=30, real rcssserver, all matches verified). The harness is
  working as designed; the result is honest and not a smoke artifact.

Commit: pinned to `f42b9cb` for the snapshot setup +
`a2d9d24` for the mark wiring.
