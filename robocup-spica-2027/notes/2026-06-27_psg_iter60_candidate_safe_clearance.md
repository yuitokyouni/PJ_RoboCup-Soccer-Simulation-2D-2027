# PSG-loop iter-60 candidate — Bhv_SmartClearance safe touchline fallback

Date: 2026-06-27
Status: **UNVERIFIED** — code change only; no batch evaluation yet.
File: `externals/patches/cyrus-team/src/phase5/bhv_smart_clearance.cpp`

## Hypothesis

Iter 49 logged a u2 (CB) clearance that went **backward**, leading
directly to an opponent shot at cyc 2456 (-44.5, -1.0):

> "**through** chain: opp wing → u2 CB clearance BACKWARD → opp shot."
> — `notes/PSG_LOOP_JOURNAL.md` iter 49 row

Today `Bhv_SmartClearance` returns three forward targets in priority
order — (45, sy·30), (28, sy·14), (45, -sy·30) — and returns `false`
if all three are path-blocked or land in the forbidden midfield band.
The caller then invokes `Body_AdvanceBall`, whose direction in tight
situations is not guaranteed to be forward of the kicker.

Conjecture: in the iter-49 scenario all three priority targets failed
the path check (opp pressers near the ball), and the AdvanceBall
fallback produced the backward kick.

## Change (single contrast)

Add one extra fallback before the final `return false`:

- Target: `(min(40, max(26, ball.x + 8.0)), sy * 32.0)` — same-side
  touchline, capped between x=26 (past the forbidden midfield band)
  and x=40 (so the standard 2.7 kick speed actually lands near it).
- Hard guard: target.x must be > ball.x + 3.0. Never a backward kick.
- Path-block check **intentionally skipped** for this fallback — the
  whole point is that the three priority targets already failed it.
  A touchline lob over midfield pressers is acceptable; the worst
  outcome is an opponent throw-in at our touchline, dominated by the
  conceded-shot failure mode this guards against.

No other behavior changes. `TerritoryRecoveryState` still triggers
on a successful safe clearance.

## What this is *not*

- Not a fix for the back-pass / indirect-FK pattern (G2 in
  `2026-06-27_rev_improvement_points.md`) — that's a different code
  path (`Bhv_PassKickFindReceiver`).
- Not a fix for the CB Y-stack pattern (G1/G3) — that's
  `defense_block.cpp::modulate_position`, where iters 7/15/16
  already showed mark/intercept overrides defeat the modulator.
- Not a defensive-line height cap (P1 #5) — separate change.

## Rollback

Delete the lines between the `for` loop and the final
`return false;` (the `// PSG-loop iter-49 candidate` comment through
the closing `}` of the new block). Behavior reverts to fall-through.

## Evaluation plan

Per `docs/CHANGE_EVALUATION_PROTOCOL.md`:

1. Run the variant batch against the iter_041 / iter_047 configuration
   used by the PSG-loop. Same N as the baseline.
2. `make compare BASELINE=<iter_041 summary> VARIANT=<this iter summary>`
3. Primary metric: `mean_goal_diff` delta with 95% CI.
4. Secondary check: count of conceded-after-clearance events in
   `psg_ledger.py` output. Expect this candidate to **reduce** that
   count if the hypothesis is right; expect no change if the
   backward clearance came from a different call site (e.g. a
   mark/intercept reactive kick) — in which case ROLL BACK and look
   at `Bhv_BasicMove` / mark behaviors instead.

## Risk

Low-medium.

- If iter-49's backward kick came from a different path, this change
  is a no-op in that scenario but still adds an extra clearance
  outlet elsewhere. That could either help (more decisive
  clearances) or regress (forces a clearance when retaining
  possession was better). Batch evaluation needed.
- The touchline kick can occasionally go out of play. Throw-in to
  opponent at our wing is the floor case; still better than the
  observed conceded shot.
