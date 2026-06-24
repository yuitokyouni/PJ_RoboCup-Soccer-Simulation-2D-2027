# Dependencies

Required for `make doctor` to pass.

| Component       | Purpose                                  | Source                                       | Required for `make smoke` |
|-----------------|------------------------------------------|----------------------------------------------|---------------------------|
| `rcssserver`    | Soccer Simulation 2D server              | https://github.com/rcsoccersim/rcssserver    | Yes                       |
| `rcssmonitor`   | GUI monitor / visual debugger            | https://github.com/rcsoccersim/rcssmonitor   | No                        |
| `librcsc`       | Client-side base library                 | https://github.com/helios-base/librcsc       | Yes (via helios-base)     |
| `helios-base`   | Baseline team (players, coach, trainer)  | https://github.com/helios-base/helios-base   | Yes                       |
| `python3`       | Result parser                            | system                                       | Yes                       |
| `jq`            | Quick inspection of `metrics.json`       | system                                       | No                        |

`scripts/doctor.sh` checks every binary listed as required above and prints a
clear actionable error if any are missing. It does not attempt installation.

## Environment variables

| Variable           | Used by                  | Meaning                                                |
|--------------------|--------------------------|--------------------------------------------------------|
| `HELIOS_BASE_DIR`  | `run_smoke_match.sh`     | Directory of a built helios-base checkout              |
| `HOME_TEAM_START`  | `run_smoke_match.sh`     | Script that launches the home team (default: `$HELIOS_BASE_DIR/src/start.sh`) |
| `AWAY_TEAM_START`  | `run_smoke_match.sh`     | Script that launches the away team (default: same as home)                    |
| `RCSS_PORT`        | `run_smoke_match.sh`     | rcssserver port (default: 6000)                        |

## Versions

The 2027 server version is not yet announced. The 2026 cycle ran on the
`rcssserver-18` line. We track upstream `master` and re-pin once 2027 CFP
publishes a target version.

This pinning policy is **unverified** against any official 2027 announcement
as of 2026-06-24.
