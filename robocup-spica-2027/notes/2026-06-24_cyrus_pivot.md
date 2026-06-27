# Cyrus base code pivot (Phase 4 → Phase 5 prep)

Date: 2026-06-24/25
Branch: claude/eloquent-turing-id7o0z

## Why we pivoted

After Phase 4 (defensive duty layer for helios-base), the user
identified that helios's underlying behavior is "rushy counter-style"
across the board — pressing isn't enough; we need patient possession,
compact lines, coordinated press-back. A research pass over publicly-
available RCSS2D bases (deep-research subagent, see prior transcript)
concluded:

- **No public base implements Pep-style positional play.** The
  realistic path is to graft possession primitives onto a stronger
  substrate.
- The strongest substrate identified is **cyrus-soccer-simulation-team**
  (Cyrus2D org). 2021 RoboCup champion, 2022/2023/2024 runner-up,
  active development through April 2024, ML-based dribbling / passing /
  marking / observation denoising.

The older `Cyrus2D/Cyrus2DBase` repository we'd previously fetched
turned out to be a **stale helios-base mirror** (identical
`bhv_basic_move.cpp`; only `bhv_penalty_kick.cpp` differed due to an
older librcsc pointer→value API). It is no longer fetched.

## Build chain

```
externals/install-cyrus/              <-- separate install prefix
  lib/librcsc.so.18                   from cyrus-soccer-simulation-lib (cyrus branch)
  include/rcsc/                       cyrus-flavored headers (incl intercept_table_cyrus.h)

/usr/local/include/CppDNN/            <-- system-wide (upstream hard-codes path)
  Layer.h, Function.h, DeepNueralNetwork.h

externals/src/rapidjson/include/      <-- pre-fetched at f54b0e47
  rapidjson/document.h, etc.

externals/src/cyrus-team/build/src/
  sample_player, sample_coach        <-- the actual Cyrus binaries
```

Build sequence (handled by `scripts/build_externals.sh --only NAME`):

1. `cyrus-lib` — CMake. Branch `cyrus` (not `master` — master lacks
   `intercept_table_cyrus.h`). Installs to `externals/install-cyrus/`.
2. `cppdnn` — CMake. Installs to `/usr/local/include/CppDNN/`
   (upstream `install(FILES ... DESTINATION /usr/local/include/CppDNN)`
   ignores `CMAKE_INSTALL_PREFIX`). Header-only.
3. `rapidjson` — Plain tarball fetch (Tencent/rapidjson@f54b0e47).
   Used header-only.
4. `cyrus-team` — CMake. Depends on cyrus-lib + CppDNN + rapidjson.
   Before build, `externals/patches/cyrus-team/apply.sh` overwrites
   `vendor/rapidjson.cmake` to point at the pre-fetched rapidjson
   instead of `ExternalProject_Add`-ing a fresh git clone
   (which silently produces an empty directory in sandboxed builds).

System pre-reqs added to preflight: `cmake`, `libeigen3-dev`.

## Launchers

`scripts/team_launchers/cyrus_left.sh`, `cyrus_right.sh`. Same
`goaliesleep=1 -> 3` patch as helios launchers (Cyrus's `start.sh`
is forked from helios's).

**Critical detail**: launchers `cd` to `externals/src/cyrus-team/build/src/`
before `exec`'ing `start.sh`. Cyrus loads `data/settings/teams.conf`
and the deep-learning weights under `data/deep/` via **PWD-relative
paths**. Without the cd, the team plays without its data files and
loses 0-31 to helios (we observed this; recovered with the cd).

## Baseline strength check

`experiments/cyrus_vs_helios_smoke.yaml`, n=3, default Cyrus_L vs
Phase-4-patched HELIOS_R:

| match | CYRUS_L | HELIOS_R | goal_diff |
|-------|---------|----------|-----------|
| 1     | 16      | 0        | +16       |
| 2     | 9       | 0        | +9        |
| 3     | 13      | 0        | +13       |
| mean  | **12.67** | **0**  | **+12.67** |

n=3 / SMOKE_ONLY but the signal is unambiguous: **Cyrus utterly
dominates helios, even our Phase-4-patched helios**. The strength
gap is large enough that a 30-match batch isn't needed to make
the qualitative call.

## What we kept from the helios work

- The Phase 4 defensive duty patch (`externals/patches/helios-base/`)
  stays in tree as reference — it's still useful when running
  helios as an opponent for ablation studies.
- The 3-2-5 formation files (`experiments/helios_3_2_5_formations/`)
  are in helios `.conf` Delaunay format. Cyrus formations live under
  `externals/src/cyrus-team/build/src/formations-dt/` with the
  `F433_*.conf` / `F523_*.conf` naming convention — distinct prefix
  per template. Porting work goes into Phase 5.

## Next

- **Phase 5a (next session)**: port the 3-2-5 formation set into
  Cyrus's `formations-dt/` layout (likely as `F325_*.conf`) and run
  the 3-2-5 vs default Cyrus contrast.
- **Phase 5b**: build possession-style behaviors (compact block,
  patient buildup, side-to-side circulation) on top of Cyrus's
  ActionChainGraph / play planner. The user's research target.
