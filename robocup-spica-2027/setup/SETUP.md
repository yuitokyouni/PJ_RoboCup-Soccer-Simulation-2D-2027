# Setup

This document is the canonical entry point for getting a workstation to the
point where `make doctor` passes and `make smoke` produces a `metrics.json`.

The end state we are setting up:

```
rcssserver  ──┐
              ├── runs one match ──> logs/runs/<UTC-timestamp>/
helios-base ──┘                       ├── server.out
                                      ├── *.rcg
                                      ├── *.rcl
                                      └── metrics.json   (via evaluation/parse_match_result.py)
```

Anything in this file that has not been executed end-to-end on a real machine
is marked **UNVERIFIED**. Treat unverified steps as a starting point, not a
guarantee.

---

## 1. System packages (Ubuntu 22.04 / 24.04) — UNVERIFIED

```sh
sudo apt update
sudo apt install -y \
    build-essential autoconf automake libtool pkg-config \
    flex bison \
    libboost-all-dev \
    libfontconfig1-dev libfreetype6-dev libx11-dev libxext-dev libxrender-dev \
    qt5-default qtbase5-dev qt5-qmake \
    python3 python3-pip jq
```

Notes:
- `qt5-default` may not exist on 24.04; `qtbase5-dev qt5-qmake` are the
  packages that actually matter for the monitor.
- macOS / non-Debian: see `DEPENDENCIES.md` for the per-component list and
  install equivalents yourself.

## 2. rcssserver — UNVERIFIED

Build the server. The 2027 qualifying servers are not yet announced; the
2026 cycle used the `rcssserver-18` line. We track the upstream `master`.

```sh
git clone https://github.com/rcsoccersim/rcssserver.git
cd rcssserver
./bootstrap
./configure
make -j"$(nproc)"
sudo make install
sudo ldconfig
which rcssserver   # should print a path
```

## 3. rcssmonitor (optional, for visual debugging) — UNVERIFIED

```sh
git clone https://github.com/rcsoccersim/rcssmonitor.git
cd rcssmonitor
./bootstrap
./configure
make -j"$(nproc)"
sudo make install
```

Headless smoke matches do not require the monitor.

## 4. librcsc — UNVERIFIED

`librcsc` is the player-side library that helios-base links against.

```sh
git clone https://github.com/helios-base/librcsc.git
cd librcsc
./bootstrap
./configure --prefix="$HOME/.local"
make -j"$(nproc)"
make install
```

Record the install prefix; helios-base needs to find these headers and
libraries when it configures.

## 5. helios-base — UNVERIFIED

```sh
git clone https://github.com/helios-base/helios-base.git
cd helios-base
./bootstrap
./configure --with-librcsc="$HOME/.local"
make -j"$(nproc)"
```

The build produces a `src/start.sh` and the player/coach/trainer binaries.
Export the directory so the smoke harness can find it:

```sh
export HELIOS_BASE_DIR="$(pwd)"
echo "export HELIOS_BASE_DIR=\"$HELIOS_BASE_DIR\"" >> ~/.bashrc
```

## 6. Verify with the harness

From the repository root:

```sh
make doctor
```

If `doctor` is green:

```sh
make smoke
```

A successful smoke match leaves `metrics.json` under
`logs/runs/<UTC-timestamp>/`.

## 7. Phase 2.5 automated path (Cyrus2DBase + friends)

Sections 2-5 build everything by hand. Once the system packages from
section 1 are installed, the Phase 2.5 scripts wrap the same steps and
land binaries under `externals/install/bin/`:

```sh
make fetch-externals          # clones rcssserver, librcsc, helios-base, cyrus2dbase
make build-externals          # autotools build into externals/install/
export PATH="$PWD/externals/install/bin:$PATH"
make doctor                   # should now go green
```

See `externals/EXTERNALS.md` for the pin policy and
`docs/REAL_INTEGRATION.md` for the declared-vs-applied options contract
and the tightened `RESEARCH_GRADE` rule.

## 8. What remains manual

These steps are *not* automated by this repo:

- Installing system packages (section 1).
- Choosing a long-term base code (HELIOS vs Cyrus2D vs Gliders2D vs
  Pyrus). Phase 2.5 picks Cyrus2DBase as the first practical baseline
  but keeps HELIOS Base around as a minimal reference.
- Network / firewall configuration if running matches across hosts.

Everything else above is in scope for the harness to call.
