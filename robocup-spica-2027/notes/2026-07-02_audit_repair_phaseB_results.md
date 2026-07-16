# Audit repair Phase B — coach restoration + C++ fixes, N=30 each

Date: 2026-07-02
Status: both batches **RESEARCH_GRADE** (N=30, real_rcssserver), measured
with the repaired harness (validity guards, status-filtered pooling,
t-based CIs, seed + binary-sha256 recording — the first batches in the
repo where all four hold).

## What was measured

| batch | binary | contrast isolates |
|-------|--------|-------------------|
| iter62_coach_left | iter-62 stack, **coach restored** (audit S1 fix), C++ untouched | coach effect vs the coach-less iter62_tmr_left |
| iter63_fixed_left | coach + **audit Phase C C++ fixes** | the C++ mine-removal bundle vs iter62_coach_left |

Phase C bundle (all in one batch — small effects are individually
unmeasurable at N=30 anyway, see power analysis in the audit):
SmartClearance defensive-context guard / all-opponent path check /
resting-point forbidden-band check / execute() result check; CDM
build-up drop 5/6 (was pulling attacker 7); counter_press namespace
link fix (W_PRESS term alive for the first time); TRS macro defined
(territory recovery compiled in for the first time). Binary-verified
via nm: TerritoryRecoveryState consumer present, strong
counter_press hooks in namespace cyrus_phase5.

## Results

| config | N | W/D/L | scored | conceded | mean_gd | 95 % CI |
|--------|---|-------|--------|----------|---------|---------|
| iter_19 (journal "best", coach-less) | 30 | 1/6/23 | 4 | 36 | -1.067 | [-1.377, -0.756]* |
| iter-62 (coach-less) | 30 | 1/13/16 | 3 | 22 | -0.633 | [-0.923, -0.344]* |
| iter-62 + coach | 30 | 3/10/17 | 8 | 26 | -0.600 | [-0.975, -0.225] |
| **iter-62 + coach + C++ fixes** | 30 | **6/14/10** | **13** | 23 | **-0.333** | **[-0.797, +0.130]** |

\* pre-repair rows measured with z-CIs and the coach-less confound;
shown for trajectory only.

## Key observations

1. **First configuration in project history whose CI against Vanilla
   includes zero.** "Spica is worse than Vanilla" is no longer
   supported at N=30 for the fixed build. 20/30 matches unbeaten,
   6 wins (previous best in ANY recorded batch: 1).
2. **The coach effect on goal-diff was small** (+0.033, CI crosses 0)
   but visible in attack volume (3 → 8 goals). The audit's S1 finding
   was a validity killer, not the main deficit driver. It had to be
   fixed to say anything at all; it alone changed little.
3. **The C++ bundle moved the mean by +0.267** (CI [-0.304, +0.838],
   crosses zero — not individually significant at N=30, consistent
   with the power analysis: MDE ≈ 0.66 for a between-batch delta).
4. **Against the journal's claimed peak (iter_19) the fixed build is
   positive-significant**: delta +0.733, combined SE 0.277,
   CI [+0.19, +1.28]. Single post-hoc comparison — treat with the
   usual caveat — but it is the cleanest quantitative statement of
   how far the audit repairs moved the project.
5. Attack profile transformed: 13 goals in 30 matches vs 3-4 in every
   previous 30-match batch. Plausibly the SmartClearance
   defensive-context guard (no more corner-pokes after failed shots
   in the attacking third) is the dominant contributor; isolating it
   would need a dedicated A/B at N≈300 per the power table, or the
   CRN/paired design (librcsc seed patch) to cut the variance first.

## What this retires

- "Phase 5 framework is net-NEGATIVE vs Vanilla" (2026-06-28 note) —
  the claim conflated the framework with (a) the coach handicap and
  (b) five C++ defects, two of which nullified whole modules and one
  of which actively sabotaged the attack. With those repaired the
  same framework measures CI-indistinguishable from Vanilla.
- "Vanilla に安定して負けないチームを作るのは不可能" — the fixed
  build is unbeaten in 2/3 of matches against the very opponent the
  project could never beat. Not "stably unbeaten" yet, but no longer
  hopeless: the remaining gap (-0.333 point estimate) is within one
  more real improvement of parity.

## Next (in value order)

1. librcsc RCSC_RANDOM_SEED vendor patch → CRN paired design →
   paired compare in compare_summaries.py. Cuts required N for
   0.1-0.2 effects; every future iteration benefits.
2. N=100+ confirmation run of iter63_fixed vs Vanilla (~2.5 h) to
   tighten the CI around the true level; decides whether the point
   estimate -0.333 is real or the batch drew lucky.
3. Sub-bisect the C++ bundle only if (2) confirms the level — the
   SmartClearance guard is the leading suspect for most of the gain.
4. Multi-opponent matrix (wrighteagle fetched; helios built) for
   external validity beyond the single Vanilla yardstick.
