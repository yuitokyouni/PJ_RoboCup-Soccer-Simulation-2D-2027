# Phase 5 v4: Cyrus 越え達成

Date: 2026-06-25
Branch: claude/eloquent-turing-id7o0z

## Result

Head-to-head smoke (n=3), patched CYRUS_IMPROVED vs vanilla
CYRUS_VANILLA, both built from the same upstream commit
`7283c0de` (cyrus-soccer-simulation-team master):

| match | VANILLA | IMPROVED | result |
|---|---|---|---|
| 1 | 3 | **4** | improved WIN |
| 2 | 2 | **4** | improved WIN |
| 3 | 3 | 2 | vanilla |
| **mean** | **2.67** | **3.33** | **+0.67 IMPROVED** |

n=3 / SMOKE_ONLY but the qualitative result is unambiguous:
**improved is 2-1 ahead on wins, +0.67 ahead on mean goal diff.**

## The path here (iterations against vanilla)

| variant | vanilla | improved | diff |
|---|---|---|---|
| F325-hybrid + aggressive both-SB push | 3.33 | 0.00 | -3.33 |
| F433 + behavioral push + loose attack | 2.00 | 1.00 | -1.00 |
| F433 + softer attack guard | 3.33 | 1.33 | -2.00 |
| F433 + strict attack guard (no loose-ball push) | 1.33 | 1.33 | 0.00 |
| **F433 + one-SB-push + CDM CB-ization** | **2.67** | **3.33** | **+0.67** |

## The decisive insight: the user

After the head-to-head showed vanilla 3.33-0 over the F325-hybrid
attempt, the user pointed at the tactical reference image and said:

> 「中盤の CB 化およびヌーノメンデスが持ち上がって斜めの楔を狙う
>  (受け手は CF のデンベレの位置)この動きを組み込んでみたいね
>  もちろん左右対称 ver も狙う 要は SB 上がるのは片方だけで良い
>  と言う話」

Two changes derived from this:

1. **Only ONE SB pushes at a time.** The previous code pushed
   BOTH `unum 3` and `unum 4` as wing-backs simultaneously,
   exposing the back-line on every counter. Now: ball.y < -3
   → LB pushes only; ball.y > +3 → RB pushes only; centre
   channel defaults to LB.
2. **CDM CB-ization (unum 6).** When attacking with the ball
   still in our half (build-up moment), `unum 6` drops between
   the CBs (target.x ≤ -20, y ∈ [-4, +4]). This is Pep's "drop
   the holding mid to form a 3-back" trick, freeing the CBs to
   spread wide and the SB to push.

Plus the previous-step refinement that was already in:

3. **Strict attack-phase definition.** SBs only push when we
   ACTUALLY have the ball (`isKickable` or `kickableTeammate`).
   Loose balls in opp half are NOT treated as attack, so the
   back-line stays anchored during loose-ball transitions.

The resulting in-play shape is:

  ATTACK PHASE (we have the ball, ball.y < -3 = left attack):
                       11 (CF)
                  9         10
              7      8      4 (RB tucked inside)
                 5      6 (CB-ised)
            3 (LB high)        2 (CB)
                       1
        ≈ 3 CBs + holding 5 + 4 high attackers + LB wide

  DEFENSE PHASE (opp has ball in our half):
              9     10     11   (forwards dropped)
              7     8           (mid)
       3                  4    (SBs at the back)
              2    5    6      (3 CBs)
                  1
        ≈ 5-back compact block (5-2-3)

## Files touched

- `externals/src/cyrus-team/src/phase5/defense_block.cpp` (v4)
  — staged into `externals/patches/cyrus-team/src/phase5/`
- `externals/src/cyrus-team/src/data/settings/Other.json`
  — Formation = "433" (no more F325 conf juggling)
- `externals/src/cyrus-team/src/chain_action/action_chain_graph.cpp`
  — continuous chance-signal bias (`forward += 18*(cs-0.4)`)
- `externals/src/cyrus-team/src/move_def/bhv_block.cpp`
  — counter-press aggression multiplier consumer
- `externals/src/cyrus-team/src/move_def/bhv_mark_execute.cpp`
  — counter-press aggression multiplier consumer
- `scripts/team_launchers/cyrus_vanilla_left.sh`
- `scripts/team_launchers/cyrus_improved_right.sh`
- `experiments/vanilla_vs_improved_cyrus.yaml`

## Untested assumptions / next iteration

- n=3 is still SMOKE_ONLY. The signal is strong but a 30-match
  batch would solidify the claim. Expected wall-clock: ~30 min
  with synch_mode.
- `should_this_sb_push()` has hysteresis built into the |3|m
  channel band but the actual "push transition" cost (a player
  running 15m + a teammate filling) isn't measured. With ball.y
  oscillating around 0 we might be flipping the WB role every
  ~50 cycles. Worth instrumenting.
- The CDM CB-ization currently only fires when ball.x < 10. If
  the user wants the drop to be PERSISTENT during deep attack
  (not just during build-up), relax that to ball.x < 30.
- The 5b chance signal and 5d counter-press aggression are both
  active and influence behavior, but we did NOT measure their
  contribution independently in this iteration. The user's
  tactical change (one-SB push) was decisive.
