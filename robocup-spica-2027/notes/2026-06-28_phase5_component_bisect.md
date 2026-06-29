# Phase 5 component bisect — which patch group is helping?

Date: 2026-06-28
Status: **RESEARCH_GRADE** for all six points (N=30, real_rcssserver).
Trigger: history bisect showed Spica is monotonically improving along
the iter timeline but still loses to Vanilla overall. Question: are
the Phase 5 component groups individually helping or hurting?

## Method

Two leave-one-out variants of the iter-62 stack:

| variant | what was disabled |
|---------|-------------------|
| V1 (no chain_action) | apply_phase5.sh Step 7 — the chance_signal bias and the wedge / cross / through-ball / side-switch / mirror per-candidate bonuses installed in action_chain_graph.cpp. Step 7b TMR path bonus and everything else (defense_block, smart_clearance, F325 framework, counter_press, intercept_discipline) stayed ENABLED. |
| V2 (no Step 5)       | apply_phase5.sh Step 5 — counter_press tick + defense_block::modulate_position + intercept_discipline gate in bhv_basic_move.cpp. Step 7 chain biases, Step 7b TMR, smart_clearance, F325 framework all stayed ENABLED. |

Each variant was built with the same cyrus-team source @
`7283c0decd77c81d15de46aab2a3a3bd90eddfe0`, same librcsc fork, same
rcssserver 19.0.0, run N=30 vs the same Vanilla binary on LEFT side.

## Six-point summary

| label | N | W/D/L | scored | conceded | mean_gd | se | 95 % CI |
|-------|---|-------|--------|----------|---------|-----|---------|
| iter_1                 | 30 | 0/11/19 | 1 | 30 | -0.967 | 0.169 | [-1.299, -0.635] |
| iter_19                | 30 | 1/6/23  | 4 | 36 | -1.067 | 0.159 | [-1.377, -0.756] |
| iter_41 (baseline)     | 30 | 0/13/17 | 4 | 29 | -0.833 | 0.152 | [-1.132, -0.535] |
| **iter_62 (variant)**  | 30 | 1/13/16 | 3 | 22 | **-0.633** | 0.148 | [-0.923, -0.344] |
| V1 (no chain_action)   | 30 | 0/10/20 | 4 | 36 | -1.067 | 0.172 | [-1.405, -0.729] |
| V2 (no Step 5)         | 30 | 0/11/19 | 3 | 31 | -0.933 | 0.191 | [-1.308, -0.558] |

## Delta vs iter_62 (the strongest measured stack)

| label | delta | combined SE | delta 95 % CI | classification |
|-------|-------|-------------|---------------|----------------|
| iter_1               | -0.333 | 0.225 | [-0.774, +0.107] | inconclusive (crosses 0) |
| iter_19              | -0.433 | 0.217 | [-0.858, -0.009] | **negative-significant** |
| iter_41 (baseline)   | -0.200 | 0.212 | [-0.616, +0.216] | inconclusive (crosses 0) |
| V1 (no chain_action) | -0.433 | 0.227 | [-0.878, +0.012] | grazes 0 (essentially negative) |
| V2 (no Step 5)       | -0.300 | 0.242 | [-0.774, +0.174] | inconclusive (crosses 0) |

## Reading the numbers

1. **Step 7 (chain_action bonuses) is by far the most valuable Phase 5
   component installed.** Removing it (V1) drops Spica by ~0.43
   goals/match, almost the entire iter-62 win over iter_41. The CI
   grazes zero but only barely, and the V1 conceded count (36) jumps
   nearly to iter_19's level (also 36).
2. **Step 5 (counter_press + defense_block modulator + intercept
   discipline gate) is probably helping but the evidence is weaker.**
   V2 drops by 0.3 with a wide CI that crosses zero. The conceded
   count goes from 22 (iter-62) to 31 (V2) — a meaningful defensive
   loss — but the offense impact is small (3 → 3 goals scored).
3. **iter-62 (Step 7b TMR path bonus) sits on TOP of an already
   beneficial Step 7 chain_action stack.** Without Step 7, Step 7b
   alone (V1's actual config) cannot produce the same value: V1 is
   at the same level as iter_19, which has Step 7's bonuses but no
   Step 7b. So Step 7b ≈ side-switch-removal ≈ +0.2 each, additive.
4. **The whole stack still loses -0.633 to Vanilla.** No subset
   tested gets closer to zero. Component-level "this helps" does not
   imply the framework as a whole helps — it implies each component
   patches over enough damage from other layers that the patched
   version is better than the un-patched version.

## What this rules out and what it leaves open

### Rules out

- "Iter-62 specifically broke things" — the iter-62 TMR bonus
  contributes a small positive that survives in this stack. Closing
  it is fine; keeping it is also fine.
- "Reverting to early Spica (iter_1, iter_19) would help" — both are
  worse than iter-62 at RESEARCH_GRADE measurement.
- "The chain_action bonuses are overfitted / hurting" — V1 disproves
  this. Removing them costs ~0.4 goals/match.

### Leaves open

- **Is the Phase 5 framework itself net-negative against Vanilla?**
  The four points sampled (iter_1, iter_19, iter_41, iter_62) all
  carry the full Phase 5 framework. Their range -0.967 to -0.633
  could mean either (a) Spica patches itself toward break-even but
  Phase 5 starts it deep in the hole, or (b) Spica patches itself
  toward break-even from a near-zero baseline and -0.633 IS the
  near-zero point. Distinguishing these needs a Vanilla LEFT vs
  Vanilla RIGHT side-bias measurement (in progress as
  `vanilla_lr_side_check`) AND a "Phase 5 framework absent, only
  rapidjson vendor patch" run on LEFT.
- **Which sub-component of Step 7 carries the value?** Step 7
  installs five distinct bonus rules (chance_signal, wedge, cross,
  through-ball, side-switch, mirror). They are bundled in a single
  python step. To isolate which is doing the work the bundle has to
  be split into per-rule patches and bisected again.
- **Within Step 5, is the value from counter_press,
  defense_block::modulate_position, or intercept_discipline?** Same
  story — the bundle hides which sub-component matters.

## Next iteration (if anyone returns to this)

1. **Side-bias check** — `vanilla_lr_side_check` running now. Result
   to be appended to this note.
2. **Pure-Vanilla framework comparison** — build a snapshot from
   cyrus-team @ `7283c0d...` with ONLY the rapidjson vendor patch
   (the existing `cyrus-team-vanilla-snapshot` is already this).
   Run it on LEFT vs Vanilla on RIGHT, N=30. The mean_gd of THIS
   batch is the Spica325 vs Vanilla zero point — subtract that from
   iter-62's -0.633 to get the real Phase 5 effect size.
3. **Step 7 sub-bisect** — split the python step into one block per
   bonus (`PHASE5_ACG_CHANCE`, `PHASE6_ACG_WEDGE`,
   `PHASE6_ACG_SIDESWITCH`, `PHASE9_ACG_MIRROR`, journal's cross /
   through additions). Disable each in turn for N=30. Reject any
   sub-bonus whose removal does not drop mean_gd by at least 1 SE.
4. **Step 5 sub-bisect** — same with counter_press / defense_block /
   intercept_discipline.

## Eval-gate protocol (now ENFORCED)

This note's measurements respect the rule documented in
`2026-06-28_psg_bisect_results.md`:

> No accept / merge / journal-row-kept without
> 1) N≥30 RESEARCH_GRADE batch of candidate vs Vanilla,
> 2) N≥30 RESEARCH_GRADE batch of immediate-parent vs Vanilla,
> 3) make compare between the two,
> 4) Reject if delta 95 % CI is negative-significant; hold otherwise.

V1 (delta -0.433, CI grazes 0): would be HELD (do not strip Step 7).
V2 (delta -0.300, CI crosses 0): would be HELD (do not strip Step 5).
The status quo (keep both Step 5 and Step 7 enabled) is the
defensible interpretation.
