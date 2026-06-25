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

## Build-time tools (Phase 2.5)

Required by `scripts/build_externals.sh` to compile `rcssserver`,
`librcsc`, `helios-base`, and `cyrus2dbase` under `externals/install/`.
Not needed if you only intend to use binaries already on `PATH`.

| Group              | Packages (Debian/Ubuntu)                                                                |
|--------------------|-----------------------------------------------------------------------------------------|
| Autotools toolchain| `autoconf automake libtool pkg-config flex bison build-essential libfl-dev`             |
| Boost              | `libboost-all-dev`                                                                      |
| Qt5 (helios/cyrus) | `qtbase5-dev qt5-qmake`                                                                 |

`libfl-dev` ships `/usr/include/FlexLexer.h`, which `rcssserver`'s
clang parser includes; `flex` alone is not enough. On Ubuntu 24.04
the `libtool` package installs `libtoolize` (the autotools front-end)
rather than a `libtool` shell driver on `PATH`; the build pre-flight
looks for `libtoolize` accordingly.

`build_externals.sh` pre-flights every required tool above and refuses
to proceed with a one-line `sudo apt install ...` hint if anything is
missing. It does **not** install system packages on its own.

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
