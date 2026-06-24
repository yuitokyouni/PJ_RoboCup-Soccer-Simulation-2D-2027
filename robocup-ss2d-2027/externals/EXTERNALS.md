# Externals

External RCSS2D dependencies the harness pulls into `externals/src/`.

Source trees are **not** committed to this repository. The fetch script
clones them into `externals/src/<name>/` and the build script installs
artefacts under `externals/install/` (also not committed).

## Pin set

`requested_ref` is the human-edited target — a tag, a branch, or a
specific commit. `resolved_commit` is the SHA the fetch script
actually checked out and recorded into `externals/EXTERNALS.lock`.
Only `resolved_commit` is a pin in the reproducibility sense; a
branch name like `master` is a *moving* target until the lock fixes
it.

| Name          | Role                                             | Repo                                                   | Requested ref         | License | Notes |
|---------------|--------------------------------------------------|--------------------------------------------------------|-----------------------|---------|-------|
| `rcssserver`  | Soccer Simulation 2D server                      | https://github.com/rcsoccersim/rcssserver              | `rcssserver-19.0.0`   | LGPL-3.0 (UNVERIFIED) | A tag; `resolved_commit` should always equal this tag's commit. |
| `librcsc`     | Client-side base library                         | https://github.com/helios-base/librcsc                 | `master`              | LGPL-3.0 (UNVERIFIED) | Branch tip; reproducibility depends on the committed `EXTERNALS.lock`. |
| `helios-base` | Historical / minimal reference team              | https://github.com/helios-base/helios-base             | `master`              | LGPL-3.0 (UNVERIFIED) | Optional. README documents `rcssserver-16` support; treat as historical. |
| `cyrus2dbase` | First practical baseline (HELIOS + Gliders + Cyrus2021) | https://github.com/Cyrus2D/Cyrus2DBase            | `master`              | UNVERIFIED            | README documents `rcssserver-18` support; `rcssserver-19` compat is UNVERIFIED. |

## Pin policy

This file is the **intent** (which ref we want); `EXTERNALS.lock` is the
**reality** (which commit we got). One-line-per-external manifest:

    <name> <repo> <requested_ref> <resolved_commit>

**`EXTERNALS.lock` is checked in.** Once a fetch resolves a branch tip
to a real commit, that line is what guarantees a future
`make fetch-externals` reproduces the same tree. Treat the lock the
same way you would a `package-lock.json` or `Cargo.lock`: regenerate
deliberately, review the diff, commit it.

Pin upgrades go in one PR per external: bump `requested_ref` here,
re-run `make fetch-externals ONLY=<name> FORCE=1`, commit the new
lock line plus this table, attach the diff to a Phase notes file.

## How the fetch works

`scripts/fetch_externals.sh` resolves `requested_ref` to a 40-character
commit SHA via the GitHub REST API
(`https://api.github.com/repos/<owner>/<repo>/commits/<ref>`), then
downloads `https://github.com/<owner>/<repo>/archive/<SHA>.tar.gz`
and extracts it into `externals/src/<name>/` with
`tar --strip-components=1`. This path works in environments that
restrict outbound git protocol but allow GitHub's REST API + archive
endpoints. Once `EXTERNALS.lock` is committed, a re-fetch skips the
API call and uses the recorded SHA directly (unless `FORCE=1` is set),
so reproducibility does not depend on the upstream branch tip
staying still.

## License tracking

Licenses listed above are marked **UNVERIFIED** because we have not yet
opened `LICENSE` files in the cloned trees. The fetch script reports the
license file path it finds; the build script does not enforce anything.
Real audit happens before any release / submission.

## What lives under `externals/`

```
externals/
  EXTERNALS.md            this file (intent)
  EXTERNALS.lock          fetch_externals.sh output (reality); checked in
  src/                    cloned source trees (gitignored)
  install/                build artefacts (gitignored)
```
