# Phase 9 status — goal: Spica325 goal/match ≥ 0

## Progress made

| step                                          | result (n=20 balanced, SE) |
|-----------------------------------------------|----------------------------|
| baseline (F325 + Phase 5 + Phase 8 ON)        | **-2.07** ± 0.41           |
| F325 + Phase 5 + Phase 8 OFF (kill switch)    | -2.27                      |
| **F433 + Phase 5 (original tuning)**          | -0.69 ± 0.45 (n=16)        |
| F433 + Phase 5 + Phase 9 ACG-mirror           | -1.20                      |
| F433 + Phase 5 + chance 0.3/45                | -0.80                      |
| F433 + Phase 5 + chance 0.3/45 no branches    | -1.35                      |
| F433 + Phase 5 + phase-adaptive bias          | -0.95                      |
| **F433 + Phase 5 + Phase 7 OFF**              | **-0.75** ± 0.24 (STABLE)  |
| ... + smart_clearance OFF                     | -0.90                      |
| ... + tighter lateral shift                   | -1.15                      |
| ... + SHOOT+box bonus                         | -1.00 (leg asymmetric)     |
| ... + Shoot-only bonus                        | -1.35                      |

**Cumulative: -2.07 → -0.75 = +1.32 goal/match improvement (-65%).**

## The remaining gap

Best stable n=20: -0.75 ± 0.24 SE.

**Final n=30 (15+15) at the stable best**: **-0.767 ± 0.20 SE**.
95% CI: [-1.16, -0.37]. **Does NOT include 0.**

n=30 breakdown (Spica POV):
- 2 wins (m3 leg1 0-1, m5 leg2 1-0)
- 10 draws
- 18 losses
- Spica goals total: 7 / 30 = 0.23 / match
- Vanilla goals total: 23 / 30 = 0.77 / match

Spica's offense is **30% of Vanilla's** in this build env. Every
intervention that raised Spica's scoring also raised Vanilla's
counter-scoring; the net stayed in [-0.77, -1.35].

## Why this happened (honest read)

Prior session measured the same F325-loading code at a *balanced
n=30 -0.033 tie*. I'm getting -2.07. Same source, same upstream
commits, same patches — only the build environment (Eigen3, Boost,
GCC, glibc) differs. Switching to F433 closed 65% of the gap. The
remaining 0.75 appears to be env-level drift I cannot patch around
with phase5 module tweaks (every one I tried was either neutral, made
defense worse, or made shooting reckless).

## Strategic options to reach ≥0

1. **Accept -0.75 as best achievable here, document, claim goal at
   "within 1 SD of 0"** — needs goal redefinition / extension.
2. **Re-author F325 conf files with Cyrus's FormationEditor** —
   the prior session's ablation explicitly identified F325 conf files
   as the offensive regression source; interactive tool, ~2-4 hours.
3. **Investigate the build env drift** — pin specific Eigen/Boost
   versions, try GCC variants. Out of session scope but reproducible.
4. **Drop most of the Phase 5 hooks (keep only defense_block one-SB-
   push + CDM CB-ization)** — these tested as the only consistently
   net-positive modules. Minimal Spica might converge on vanilla
   (~0) but loses the "research model" identity.

