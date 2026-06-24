# Change Evaluation Protocol

How to evaluate a tactic / configuration change against an existing
baseline without lying to yourself.

## TL;DR

1. Produce a baseline per `docs/BASELINE_EVALUATION.md`.
2. Produce a *variant* batch the same way — same N, same externals,
   only the contrast you want to measure changes.
3. `make compare BASELINE=.../baseline/summary.json VARIANT=.../variant/summary.json`.
4. If either side is `SMOKE_ONLY` or not `real_rcssserver`, fix the
   gap. The comparison script refuses to print a claim until both
   sides clear.

## Rules

- **No mid-evaluation toolchain changes.** Baseline and variant must
  share the same four entries in `externals/EXTERNALS.lock`.
- **Same N or larger.** If the variant has fewer matches than the
  baseline, the comparison still runs but the wider CI tells the
  story. Don't shrink N to get a tighter mean.
- **No agent code change outside the contrast.** If you swap the
  start command, that *is* the contrast and must be stated as such in
  the variant's `experiments/<id>.yaml::description`.
- **No re-roll on bad luck.** A losing batch is data. Re-running until
  the variant looks good is p-hacking by another name.

## What the script reports

`scripts/compare_summaries.py` prints a side-by-side table of:

- `completed_matches`
- `sample_regime`
- `run_reality_status`
- `declared_reality_assertion`
- `mean_goal_diff`
- `se_goal_diff`
- `ci95_goal_diff_low`, `ci95_goal_diff_high`

And a single delta line:

    delta mean_goal_diff (variant - baseline)
    combined SE                  = sqrt(SE_b^2 + SE_v^2)
    delta 95% CI                 = delta ± 1.96 * combined_SE

Combined SE assumes the two batches are independent samples. That
holds for independent batches with fresh seeds; it does **not** hold
for paired designs (which this protocol does not yet support — see
Phase 3+).

## When the script refuses

Exit code 1 from `compare_summaries.py` is the deliberate refusal
state. Common reasons:

- Either side has `sample_regime != RESEARCH_GRADE`. Investigate
  `match_status_counts`, fix the cause, re-run.
- Either side has `run_reality_status != real_rcssserver`. Read the
  side's `run_reality_block_reasons` field and fix the attestation
  gap.

Do not patch the comparison script to bypass the gate. Patch the
inputs.

## Interpreting the delta CI

`delta 95% CI does NOT cross zero`
- Variant's mean goal_diff differs from baseline's beyond chance at
  the ~5% level (under independent-samples assumption).
- This is the weakest "stronger / weaker" claim the protocol permits.

`delta 95% CI crosses zero`
- Inconclusive at this N. State that explicitly. Do not say "no
  difference"; say "no evidence of difference at this N".

`delta CI extreme width`
- Likely one side has high variance or low N. Compare
  `se_goal_diff` per side before drawing conclusions.

## Out of scope for this protocol

- Per-opponent breakdowns.
- Paired / common-seed designs.
- Bootstrap CIs.
- Tournament-style multi-team evaluation.

All of those land in Phase 3+ and will get their own protocol doc
once a baseline + at least one contrast have been produced.
