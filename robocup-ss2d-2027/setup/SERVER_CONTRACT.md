# Server Contract

This document is the harness's working contract with `rcssserver`. It
records, in one place, every assumption the smoke runner makes about how
the server is launched, where it reads config from, and what it writes
back. Until each assumption is exercised against the actual binary, it is
marked **UNVERIFIED**.

Owner: `scripts/run_smoke_match.sh` and `scripts/probe_rcssserver.sh`.
Audience: anyone debugging "the smoke match started but produced no log".

---

## 1. Required binary

- **`rcssserver`** on `PATH`.
- Version reported by `rcssserver --version` is captured into
  `metadata.json::server_version`. If the binary does not respond to
  `--version`, the captured value is `"unknown"` — this is acceptable.

The 2027 target version is **UNVERIFIED**. The 2026 cycle used the
`rcssserver-18` line; we currently track upstream `master`.

## 2. Config-file resolution (UNVERIFIED across versions)

`rcssserver` documents the following lookup order:

1. `~/.rcssserver-server.conf`
2. `~/.rcssserver-player.conf`
3. `~/.rcssserver-CSVSaver.conf`
4. Command-line `--include=<path>` and `--server::*` overrides.

`scripts/probe_rcssserver.sh` lists which of these exist on the current
machine. The harness assumes command-line `server::*=value` overrides win
over the config files; this is the documented behavior but has **not**
been verified for the version of `rcssserver` on the developer's machine.

## 3. Launch options the harness passes

These flags are sent on the `rcssserver` command line by
`scripts/run_smoke_match.sh`. Verification status applies to behavior on
the latest `rcssserver` we plan to support (currently `master`, target
`rcssserver-18`):

| Flag                                    | Purpose                                      | Verified? |
|-----------------------------------------|----------------------------------------------|-----------|
| `server::game_log_dir=<run_dir>`        | Where to write the `.rcg` binary log         | UNVERIFIED |
| `server::text_log_dir=<run_dir>`        | Where to write the `.rcl` text log           | UNVERIFIED |
| `server::game_log_compression=0`        | Disable gzip so `.rcg` is openable as-is     | UNVERIFIED |
| `server::auto_mode=true`                | Run unattended; server kicks off the match   | UNVERIFIED |
| `server::port=<RCSS_PORT>`              | UDP port for player connections              | Stable across versions |
| `server::team_l_start=<home_start>`     | Command to spawn the home team               | UNVERIFIED |
| `server::team_r_start=<away_start>`     | Command to spawn the away team               | UNVERIFIED |

If any UNVERIFIED flag changes meaning or disappears upstream, the smoke
runner should **fail loudly** with the server's own message rather than
silently produce an empty log.

## 4. Expected outputs

After a successful match the run directory contains:

```
logs/runs/<UTC-timestamp>/
  server.out          rcssserver stdout/stderr (always)
  metadata.json       runtime metadata written by the harness (always)
  *.rcg               game log (only if the match progressed)
  *.rcl               text log (only if the match progressed)
  metrics.json        parser output, populated even if some fields are unknown
```

The default `.rcg` filename written by `rcssserver` is approximately
`YYYYMMDDhhmm-<left_team>_<score>-<right_team>_<score>.rcg`. The parser
extracts team names and scores from this filename when `server.out` does
not contain a "Result:" line. The exact filename format is **UNVERIFIED**
against `rcssserver-18`; the parser tolerates a mismatch by emitting
`null` scores and recording the reason in `metrics.json::parser_notes`.

## 5. Match termination

`server::auto_mode=true` is documented to let `rcssserver` exit on its own
when the match clock reaches `server::game_over_wait`. The harness
nonetheless wraps the server in a hard timeout (default 120 s) so a hung
server or a stuck team can never wedge the run. The timeout is **UNVERIFIED**
as sufficient — a real full match runs ~10 minutes of wall clock. Phase 2
will raise the default and make it per-experiment.

## 6. Process tree assumptions

- The harness launches `rcssserver` inside a new session via `setsid` so
  that all descendants — team `start.sh`, `helios_player` processes, the
  coach, the trainer — share one process group.
- On EXIT/INT/TERM the harness sends `SIGTERM` to the process group and,
  after a short delay, `SIGKILL`. This is the contract that backs the
  hardening rule "never leave rcssserver/player processes running".

This relies on `setsid` (util-linux) being present, which `doctor` checks.

## 7. What the contract intentionally does **not** cover

- Tournament-style multi-match orchestration (Phase 2).
- Network configuration when teams run on remote hosts.
- Trainer-driven scenario reset (Phase 3+).
- Stamina/positioning/tactical settings.

If you need any of the above, this document is the wrong file.
