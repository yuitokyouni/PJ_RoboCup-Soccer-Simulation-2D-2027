# PSG-loop decision journal

Target: 5 consecutive Spica wins vs Vanilla.

This file MUST be read at the start of every iteration to avoid repeating
failed approaches. Update at the END of each iteration with the new data.

## Current best known config

State at iter_019 (1-0 WIN, best so far):
- F433 conf: **Y-symmetric** (scripts/symmetrize_f433.py applied)
- defense_block.cpp Phase 5e: dynamic 3-2-5 / 5-2-3 transition (vanilla Phase 5e)
- defense_block.cpp **iter 1 SB tuck-in**: in DEFENSE PHASE, if ball.x<-30, cap |y| of u3/u4 to 12
- action_chain_graph.cpp **iter 4 wedge x2**: ev += 50 (was 25) for SB→CF half-space pass
- action_chain_graph.cpp **iter 17 cross bonus**: ev += 35 for SB (u3/u4) wide (sp.x≥20, |sp.y|≥18) → PA central (tp.x≥30, |tp.y|≤15)
- action_chain_graph.cpp **iter 19 through-ball bonus**: ev += 25 for CDM (u6/u7) sp.x>-5 → forward (u9/u10/u11) tp.x>+25
- action_chain_graph.cpp side-switch: +15 (NOT doubled — iter 5 failed)
- kickoff: defensive (NOT merged)

## Match-by-match log

| iter | config delta | score | conceded@cycle / origin | scored / preamble | opp_half | spica_half | notes |
|------|--------------|-------|---|---|---|---|---|
| 000 | clean REV baseline | 0-1 L | cyc 5618 (-45.7,-2.3) FK+kick_in cascade | — | 671 | 1024 | u4 stranded y=+22.9; defense leaked late |
| 002 | +SB tuck-in (deep |y|≤12) | 0-0 D | clean sheet | — | **814** | 742 | possession flipped; defense fixed |
| 003 | +CF u11 push (ball.x≥0 → x=ball+10, |y|≤8) | 0-0 D | clean | — | 373 | 1229 | REGRESS: CF isolated outside chain context |
| 004 | revert CF, +wedge×2 (25→50) | **1-0 W** ✓ | clean | cyc 4855 (+46.6,-5.8) kick_in→play→GOAL | **962** | 827 | first WIN. Wedge made SB→CF pass attractive |
| 005 | +side-switch×2 (15→30) | 0-1 L | (TBD) | — | 532 | 981 | REGRESS: long lateral passes turnover, opp counter |
| 006 | revert side-switch | 1-1 D | cyc 2975 (-47.1,+6.6) FK cascade | cyc 292 early goal | 894 | 732 | u8 stamina=0! CB+y stack |
| 007 | +CB u5 Y-mirror (ball.x<-30 \|y\|>5) | 0-1 L | cyc 2379 (-45.2,+2.3) | — | 600 | 1005 | CB Y-mirror rule didn't fire (\|y\|=2.3<5) |
| 008 | +u8 cap (ball.x<0 \|y\|≤10) | 0-1 L | cyc 1878 (-41.2,-0.6) | — | 535 | 933 | u8 still at +19 (cap is slow target steer) |
| 009 | +shot promo PA (+40 if Shoot in PA) | 0-1 L | cyc 5091 (-43,+3.3) | — | **330** | 1254 | WORST: low-quality shots in PA, GK kicks back |
| 010 | revert CB, u8, shot | 0-0 D | clean | — | 915 | 473 | Defense excellent. Chains don't end in shots |
| 011 | +u9 LF push (ball.x>15 → x=ball-5) | 0-1 L | cyc 2258 (-44.3,-3.1) | — | **1019** | 795 | Best possession yet; still no goals |
| 012 | revert u9, revert Y-sym (vanilla F433) | 0-1 L | cyc 2881 (-44,-4.6) | — | 639 | 1050 | Y-sym revert hurt possession too |
| 013 | restore Y-sym, iter_004 base | 0-3 L | (3 goals) | — | (TBD) | (TBD) | catastrophic; high variance |
| 014 | iter_004 base (resume) | 0-2 L | cyc 833 + 2555 both DEF-C +y stack | — | 559 | 1303 | u4+14.6, u8+17, u8+16; recurring +y stack |
| 015 | CB Y-mirror \|y\|>1 | 0-2 L | cyc 2394 (-40.9,+5.0) FK cascade + cyc 5131 (-46.5,+4.8) | — | 478 | 1111 | Rule fired but target-steering lag: u5 still +6.2 at goal |
| 016 | u5 anticipation -y when ball.x<-10 | 0-2 L | cyc 992 ball=(-50.7,+15.9), cyc 4151 ball=(-46.0,+2.3) | — | 787 | 955 | u5 at +14.9 and +5.3 -- rule did NOT apply. mark/intercept overrides modulate_position |
| 017 | revert u5; +cross bonus +35 (SB wide x>=20 |y|>=18 to PA central) | **1-1 D** | cyc 3240 (-43.6,+7.3) FK cascade | cyc 5434 (+47.9,-7.9) goal_kick→FK→GOAL | 609 | 809 | **First SCORE in 7 iter**. Cross pattern visible (PA central -y goal). |
| 018 | iter_017 reverify (cross bonus) | 0-1 L | cyc 3356 (-43.0,+3.0) corner→FK→GOAL | — | 787 | 754 | No score; cross bonus alone insufficient. HRs reach +46/+50 |
| 019 | +through-ball bonus (CDM sp.x>-5 → forward tp.x>+25, +25) | **1-0 W** ✓ | clean sheet | cyc 4049 (+45.6,-0.2) FK cascade→GOAL PA central | **1073** | 567 | 2nd WIN. cross+through+wedge stack. Best possession ever |
| 020 | iter_019 reverify (streak attempt 1) | 0-1 L | cyc 5947 (-41.4,-0.5) FK→GOAL late | — | 526 | 1146 | Streak broken (0/5). Variance dominant. |
| 021 | iter_019 config (continue) | 0-1 L | — | — | — | — | 2nd consecutive L; iter 19 win may be lucky |
| 022 | iter_019 config (continue) | 0-0 D | clean | — | 407 | 1202 | Defense holds; offense dead. opp dominates possession. |
| 023 | iter_019 config (continue) | (TBD) | | | | | best stack 4 samples: 1W 1D 2L → P(W)=25% |


## Failed approaches (DO NOT REPEAT)

1. **CF u11 push to (ball.x+10, |y|≤8)** (iter 3) → CF outside chain context; pass candidates can't reach him.
2. **Side-switch ×2 (+30)** (iter 5) → long lateral passes are low-success in Cyrus; turnovers feed counters.
3. **CB Y-mirror with |y|>5 trigger** (iter 7) → rarely fires; ball.y is usually 0-5 even on conceded.
4. **u8 RMF |y| cap to 10** (iter 8) → cap is on target only; physical position takes 50+ cycles to reach.
5. **Shoot bonus +40 in opp PA** (iter 9) → encourages low-quality long shots; opp gets ball back as goal-kick.
6. **u9 LF push (ball.x>15 → x=ball-5)** (iter 11) → defense leaked, no goals from u9 either.
7. **Drop Y-symmetric F433 → vanilla** (iter 12) → possession crashed too. Y-sym helps possession even if not win rate.
8. **Phase 9d.1 SP override (CB-split + WB-drop + DL cap)** (pre-loop, n=8 smoke) → defensive patches conflict with existing setplay-opp-formation.conf.
9. **Phase 9d.1 GK back-pass guard** (pre-loop) → eliminated panic-clear outlet, caused 0-5 disasters.
10. **Phase 9c kickoff merge** (for_our_kick → before-kick-off) → defense too high at kickoff, leaked goals.
11. **CB Y-mirror with |y|>1 threshold** (iter 15) → rule fires but target-steering lag means u5 still at +y when goal hit. Defense_block modulate_position is too late in the action pipeline.
12. **u5 anticipation always at -y when ball.x<-10** (iter 16) → rule fires but mark/intercept behaviors override formation target. defense_block patches can't reliably move CBs in critical moments.

## Working approaches (KEEP)

1. **F433 Y-symmetrize** — possession boost (~+100 opp_half cycles vs vanilla F433). Kept.
2. **SB tuck-in (u3/u4 |y|≤12 when ball.x<-30)** — fixed iter_000 u4-stranded-wide pattern. Kept.
3. **Wedge bonus ×2 (50)** — first WIN came via this (iter_004 kick_in→GOAL). Kept.

## Recurring patterns observed (open improvement targets)

1. **u4 RB at y≥+14 in conceded shapes** — even WITH SB tuck-in (which caps at 12), u4 sometimes exceeds. Maybe because tuck-in only fires in pure DEFENSE PHASE; transitions allow drift.
2. **u8 RMF stamina depletion + +y position** — repeatedly at +16..+22 with stamina near 0. The cap fix (iter 8) didn't work. Maybe the issue is u8's behavior in CYRUS code OUTSIDE defense_block (sample_communication / bhv_basic_offensive_kick path).
3. **CB pair stacked on +y** — both u2 and u5 at +y when ball is near center. Y-mirror trigger needs lower threshold (e.g. \|y\|>2 instead of >5).
4. **Zero goals scored** — even with possession dominance (1000+ cycles opp_half), chains don't produce shots. ChainAction conservative.
5. **Conceded goals come from set-piece cascades** (FK → play → FK → play → goal patterns dominate).
6. **defense_block modulate_position is bypassed in critical defense** — players switch to mark / intercept behaviors which have their OWN target logic. So patches to modulate_position only affect formation positioning, not when defenders are actively marking opp runners. Source of iter_7/8/15/16 ineffectiveness.

## Untried high-leverage ideas

- Lower CB Y-mirror threshold from \|y\|>5 to \|y\|>2 (more frequent firing).
- Investigate u8 behavior in source code (not defense_block).
- ChainAction: Cross bonus for SB at x≥+20 to receiver in box at \|y\|<15.
- ChainAction: Through-ball bonus from CDM to forward at x>+25.
- F433 conf edit: bring forwards' formation x +5m forward for offense states.
- TerritoryRecoveryState boost: after high recovery, apply +5 forward bias for 20 cycles.

## Statistical position

| samples | mean | min | max |
|---|---|---|---|
| iter_004 base 4 (#004/006/010/013) | -0.50 | -3 | +1 |
| iter_004 base 5 (#004/006/010/013/014) | -0.80 | -3 | +1 |
| All 14 iterations | -0.79 | -3 | +1 |

P(W) at iter_004 base = 1/5 = 20%. P(5W in a row) = 0.032% ≈ 1 in 3100.
At ~3min/match, expected ~155 hours of single-match runs to see one 5W streak.

User accepts ~50h budget. Math says we won't hit 5W reliably; have to focus on raising P(W) along the way.
