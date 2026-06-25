# Phase 5 ablation: locating the offensive regression

Date: 2026-06-25
Branch: claude/eloquent-turing-id7o0z

## Summary

After landing the Phase 5a-e framework (commit `e6d7976`), initial
smoke showed a net regression: full Phase 5 was 6.0-0.33 vs vanilla
Cyrus's 12.67-0. Four ablation runs against HELIOS_R (n=3 each)
isolate the source:

| variant | mean offense | mean defense | goal_diff |
|---|---|---|---|
| vanilla Cyrus (F433, no Phase 5) | **12.67** | **0.00** | +12.67 |
| F433 + Phase 5 hooks (all on) | 12.67 | 0.33 | +12.33 |
| F325 (full) + Phase 5 hooks | 6.00 | 0.33 | +5.67 |
| F325 (full) + Phase 5 hooks − 5e | 3.67 | 0.67 | +3.00 |
| F325-hybrid (F325 def, F433 off) | 8.67 | 1.33 | +7.33 |

## What this tells us

1. **F325 conf files are the cause of the offensive regression.** The
   Phase 5 C++ hooks (chance_signal, smart_clearance, counter_press,
   defense_block) are nearly neutral on offense — F433 + all hooks
   matches vanilla's 12.67 goals.

2. **Defense block (5e) IS doing useful work.** Disabling 5e drops
   defense (conceded 0.33 → 0.67) and also drops offense (6.0 → 3.67).
   The compactness it provides has flow-through value: blocking
   opponent attacks shorter recovery for our team is shorter, more
   transitions.

3. **The F325 conf files were mechanically converted** from
   `experiments/helios_3_2_5_formations/*.conf` (helios-style
   role naming → Cyrus's flat `Player/MF`). The Delaunay
   sample points were NOT re-tuned for Cyrus's chain action
   evaluator. Cyrus uses formation positions to predict where
   teammates will be after passes; if the sample-point geometry
   doesn't match how Cyrus's pass success predictor was trained
   (on 4-3-3 + 5-2-3 patterns), pass success collapses.

4. **F325-hybrid** (3-2-5 defense + 4-3-3 offense) is the best
   immediate compromise: 8.67-1.33. Tactically it's a fudge though —
   we're not actually defending compact while attacking wide; the
   role assignments (unum 5/8 → pp_lb/pp_rb wing-backs) clash with
   F433 offense conf which expects unum 3/4 as fullbacks. That
   mismatch is why conceded jumped to 1.33.

## The honest call

**We did not achieve the goal of "stronger than vanilla Cyrus" in
this session.** At best (F433 + Phase 5 hooks) we match vanilla
within noise; with F325 we regress 4+ goals on offense.

The realistic path to actually beating vanilla Cyrus from this
state needs ONE of:

A. **Re-author F325 conf files using Cyrus's FormationEditor tool**
   (interactive ~2-4 hours), so the sample-point geometry suits
   Cyrus's pass model. Lets us keep the 3-2-5 vision.

B. **Stay on F433** and add bigger tactical innovations on top
   (e.g. wire CounterPressState::aggression_multiplier into
   bhv_block, add a "high press / mid block / low block"
   3-state defense system, replace the chain-action evaluator).
   This is competition-level engineering, ~weeks not hours.

C. **Run n=30 batches** of F433 + Phase 5 hooks vs vanilla. With
   the per-match variance we see (16/9/13), even a 1-goal-per-match
   true effect needs n=15-30 to detect. The 12.67 vs 12.67 split at
   n=3 might be hiding a real signed effect either way.

D. **Drop the formation pivot entirely** and accept Cyrus as the
   competition baseline. Build the project around custom defensive
   primitives (move scheme, marking decisions, set play routines)
   rather than formation+offense restructuring.

## What stays in tree from this session

- The full Phase 5 framework (committed `e6d7976`). Reproducible
  via `apply_phase5.sh`. Phase 5 hooks are net-neutral on offense
  in F433 mode, so they don't have to come out.
- The F325 conf files (in `externals/patches/cyrus-team/src/formations-dt/`)
  as a starting point for path (A).
- F325-hybrid setup (this commit): F325_offense-formation.conf
  replaced with a copy of F433_offense-formation.conf. Best
  immediate score (8.67-1.33). Activated by Other.json
  Formation="325".
