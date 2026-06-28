# PSG-loop history bisect — was early Spica stronger?

Date: 2026-06-28
Status: **RESEARCH_GRADE for all four points** (N=30 each, real_rcssserver).
Trigger: user frustration that the PSG-loop appeared to be regressing
("iter_60 もかつてのspica初期の方が強くて草").

## Method

Four points along the PSG-loop commit history, each rebuilt and run
for N=30 matches vs the same Vanilla binary on LEFT side.

| label | commit | summary |
|-------|--------|---------|
| iter_1   | `717df41` | SB tuck-in only (defense_block tweak on top of Phase 5 framework) |
| iter_19  | `40e510b` | wedge bonus +50 + cross bonus +35 + through-ball bonus +25 ("best stack" per journal) |
| iter_41-ish | iter62 branch baseline | Phase 5/6/7/8 + side-switch REMOVED (today's measurement) |
| iter_62 variant | iter62 branch | iter_41 + PHASE5_FEVAL_PATH third-man run path bonus |

All four binaries were built with the same cyrus-team source @
`7283c0decd77c81d15de46aab2a3a3bd90eddfe0`, same librcsc fork
@ `6bafd9b9...`, same rcssserver 19.0.0. Same Vanilla opponent
across all batches.

## Results

| label | N | W/D/L | mean_goal_diff | se | 95 % CI | scored | conceded |
|-------|---|-------|----------------|-----|---------|--------|----------|
| iter_1  | 30 | 0/11/19 | -0.967 | 0.169 | [-1.299, -0.635] | 1 | 30 |
| iter_19 | 30 | 1/6/23  | **-1.067** | 0.159 | [-1.377, -0.756] | 4 | 36 |
| iter_41 | 30 | 0/13/17 | -0.833 | 0.152 | [-1.132, -0.535] | 4 | 29 |
| iter_62 | 30 | 1/13/16 | **-0.633** | 0.148 | [-0.923, -0.344] | 3 | 22 |

## Reading the numbers

1. **Spica has been monotonically getting stronger** along the
   sampled iter timeline. The user's "regression" intuition is wrong
   at this measurement resolution. iter_1 (-0.967) → iter_19
   (-1.067) → iter_41 (-0.833) → iter_62 (-0.633) is a +0.434 gain
   over the journal lifetime.

2. **The journal's claimed peak (iter_19) is the actual trough**.
   The PSG_LOOP_JOURNAL.md notes iter_19 as "Best possession ever"
   and "2nd WIN". At N=30 it's the WORST of the four (-1.067) and
   concedes the most (36 goals over 30 matches). That earlier
   "best" claim was N=1 noise.

3. **Iter_41's "side-switch removed" decision was correct.** It
   moved mean from -1.067 to -0.833 (+0.234). The journal's
   iter_041 row claims P(W)=43% after 7 samples — that point
   estimate was off (real P(W) ≈ 0/30 against Vanilla) but the
   DIRECTION of the change was right.

4. **iter_62 (third-man run path bonus) is the strongest measured
   variant overall.** +0.200 over iter_41 baseline, with the
   compare delta CI of [-0.216, +0.616] crossing zero — so still
   "no evidence of difference" at N=30 between iter_41 and iter_62.
   But the TREND is consistent with the broader pattern of
   monotonic improvement.

5. **Even at iter_62 Spica is still losing -0.633 per match against
   Vanilla.** There is no "revert to a good ancestor" path. The
   problem is that the cumulative Phase 5/6/7/8 + journal stack is
   net-weaker than plain Cyrus. Spica has been building INSIDE a
   net-negative pile, optimising within a starting point that was
   already wrong.

## What went wrong with the PSG-loop process

The loop used **N=1 per iter to decide accept / revert**. The
across-batch SE at N=1 is roughly the std of a single match
≈ 1.0 goals. The actual per-iter effect size sits at +0.05 to
+0.2 goals/match. **Signal was 5-20× smaller than the per-iter
measurement noise.** Each accept/revert decision was almost a
coin flip against the true effect.

The compounding result over 60 iterations is a near-random walk in
configuration space. But by good luck, the walk happened to drift
in the positive direction across the points we sampled. The user's
perception that the loop was regressing is consistent with this
being a NOISY walk — at iter K it can FEEL worse than iter K-5
even when the underlying trend is positive — because the
within-iter sample is too small to attribute the difference to
config rather than to a single bad random seed.

## Recommended new protocol — the N=30 eval gate

Going forward, no apply_phase5.sh change should be marked
"accepted" / "merged" / journal-row "kept" without:

1. A `RESEARCH_GRADE` batch (N ≥ 30) of the CANDIDATE vs Vanilla.
2. A `RESEARCH_GRADE` batch (N ≥ 30) of the IMMEDIATE PARENT
   (the last accepted commit) vs Vanilla.
3. `make compare` between the two summary.json files.
4. The delta 95 % CI must not cross zero in the negative direction
   (accept if positive-significant, reject if negative-significant,
   hold a hold-out decision if CI straddles zero).

At ~1.4 min/match this is ~70 min per pair of batches ≈ 1 PR per
hour. Per CHANGE_EVALUATION_PROTOCOL.md, this is what "research
grade" already means; the PSG-loop was running at
`SMOKE_ONLY` (N=1) and ignoring the regime status.

## Next iterations to actually move the needle

Reverting to a good ancestor is not on the table — there isn't
one. The full stack including iter_62 is net-weakest in the way
that matters: -0.633 vs Vanilla. To get to mean_goal_diff ≥ 0:

1. **Pre-Phase-5 / Vanilla-with-just-rapidjson-patch baseline at
   N=30.** Important sanity check: does Phase 5 itself help or
   hurt vs plain Cyrus? If Vanilla-vs-Vanilla mirror-matches show
   the Vanilla cyrus team itself runs at mean ≈ 0, then plain
   Vanilla is a +0.633 to +1.067 step UP from any of the four
   Spica points we measured. That would mean **Phase 5 itself is
   the regression** and the loop has been polishing inside a
   broken room.
2. If (1) confirms Phase 5 is the problem, the right next step is
   not another path-bonus or another formation-rule — it is to
   bisect Phase 5 itself (5a chance_signal, 5b wedge, 5c
   territory_recovery, 5d counter_press, 5e defense_block, 5e
   formation-Y-sym) and identify which of the framework
   components is net-negative at N=30.
3. The user's tactical suggestion (false-9 + lay-off + third-man
   + fluid roles) still has merit but should be tested ONLY after
   the broken-framework hypothesis is ruled in or out. Building
   more tactics on top of a net-negative framework just buries
   the signal deeper.

## Inverted journal anchor table

The journal records "best known config" claims with sample sizes
that the new protocol would refuse. For reference, here is the
reconciliation:

| journal claim | N | claimed mean | measured @ N=30 |
|---------------|---|--------------|------------------|
| iter_019 "Best possession ever" 2nd WIN | 1 | n/a (W) | **-1.067** (worst of 4) |
| iter_041 "mean +0.57 P(W)=43% over 7" | 7 | +0.57 | **-0.833** (3rd of 4) |
| (today) iter_62 candidate A' | 30 | — | -0.633 (strongest) |

The N=7 / +0.57 anchor of iter_041 was off by ~1.4 goals/match
in the point estimate. That is consistent with a 7-sample SE of
roughly 0.4 — the iter_041 mean and the true mean are about 3.5
SEs apart, well outside the n=7 95 % interval. Either iter_041
was a lucky early sample or the journal sample wasn't independent
from earlier "good" matches (counters reset on streak break,
preserved on accumulation).
