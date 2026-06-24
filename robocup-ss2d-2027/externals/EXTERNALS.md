# Externals

External RCSS2D dependencies the harness pulls into `externals/src/`.

Source trees are **not** committed to this repository. The fetch script
clones them into `externals/src/<name>/` and the build script installs
artefacts under `externals/install/` (also not committed).

## Pinned set

| Name          | Role                                             | Repo                                                   | Pinned ref           | License | Notes |
|---------------|--------------------------------------------------|--------------------------------------------------------|----------------------|---------|-------|
| `rcssserver`  | Soccer Simulation 2D server                      | https://github.com/rcsoccersim/rcssserver              | `rcssserver-19.0.0`  | LGPL-3.0 (UNVERIFIED) | Latest release as of 2026-06-24. Compat with Cyrus2DBase (documented for rcssserver-18) is UNVERIFIED on `-19`. |
| `librcsc`     | Client-side base library                         | https://github.com/helios-base/librcsc                 | `master`             | LGPL-3.0 (UNVERIFIED) | Pinned commit hash recorded into `externals/EXTERNALS.lock` by the fetch script. |
| `helios-base` | Historical / minimal reference team              | https://github.com/helios-base/helios-base             | `master`             | LGPL-3.0 (UNVERIFIED) | Optional. README documents `rcssserver-16` support; treat as historical and use Cyrus2DBase as the first practical baseline. |
| `cyrus2dbase` | First practical baseline (HELIOS + Gliders + Cyrus2021) | https://github.com/Cyrus2D/Cyrus2DBase            | `master`             | UNVERIFIED            | README documents `rcssserver-18` support; `rcssserver-19` compat is UNVERIFIED. |

## Pin policy

This file is the **intent**. The fetch script captures the **reality**
into `externals/EXTERNALS.lock` — a one-line-per-external manifest of
`<name> <repo> <ref> <commit>` after each clone / checkout. That lock
file is what downstream scripts (and `metadata.json::server_version`)
report; this file is what humans edit.

Pin upgrades go in one PR per external. Bump the ref here, re-run
`make fetch-externals`, commit the new lock line, attach the diff to a
Phase notes file.

## License tracking

Licenses listed above are marked **UNVERIFIED** because we have not yet
opened `LICENSE` files in the cloned trees. The fetch script reports the
license file path it finds; the build script does not enforce anything.
Real audit happens before any release / submission.

## What lives under `externals/`

```
externals/
  EXTERNALS.md            this file
  EXTERNALS.lock          written by fetch_externals.sh (UNVERIFIED in repo until first fetch)
  src/                    cloned source trees (gitignored)
  install/                build artefacts (gitignored)
```
