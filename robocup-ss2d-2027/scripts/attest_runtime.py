#!/usr/bin/env python3
"""attest_runtime.py - record observable evidence about a match run.

Reads <run_dir>/metadata.json, gathers facts about the rcssserver
binary, the EXTERNALS.lock state, the team start commands, and the
log files, then merges the facts back into metadata.json:

    observed_reality_status     real_rcssserver | synthetic_or_stubbed
                                | unknown_or_unverified
    reality_evidence            dict of observed facts
    reality_evidence_missing    reasons real_rcssserver was not asserted

Promotion rule (see docs/REALITY_ATTESTATION.md):

    observed_reality_status = real_rcssserver
      IFF all of the following hold:
        - the server binary resolves under <externals_install_prefix>/bin
        - the server binary is an ELF executable
        - the server binary is larger than 10 KiB
        - server_version contains none of {fake, stub, mock, dummy}
        - <externals_root>/EXTERNALS.lock exists and lists rcssserver
        - at least one .rcg in run_dir is non-empty
        - at least one .rcl in run_dir is non-empty
        - both home_start_command and away_start_command resolve to
          existing files (no UNVERIFIED: prefix)

    Otherwise:
        - if any stub indicator triggers -> synthetic_or_stubbed
        - else                            -> unknown_or_unverified

The script never raises on missing or partial data; missing inputs
become entries in reality_evidence_missing and the observed status
drops to unknown_or_unverified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

STUB_KEYWORDS = ("fake", "stub", "mock", "dummy")
MIN_BINARY_SIZE = 10 * 1024  # bytes
ELF_MAGIC = b"\x7fELF"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_lock(lock_path: Path) -> dict:
    """Return {name: resolved_commit} for each line in EXTERNALS.lock.

    Lines look like:  <name> <repo> <requested_ref> <resolved_commit>
    """
    out: dict[str, str] = {}
    if not lock_path.is_file():
        return out
    for raw in lock_path.read_text().splitlines():
        parts = raw.split()
        if len(parts) >= 4:
            out[parts[0]] = parts[3]
    return out


def gather(
    run_dir: Path, externals_root: Path, install_prefix: Path
) -> tuple[dict, list[str], str]:
    metadata = json.loads((run_dir / "metadata.json").read_text())
    evidence: dict = {}
    missing: list[str] = []
    stub_reasons: list[str] = []

    # --- 1. Server binary identity --------------------------------------
    server_binary = metadata.get("server_binary")
    binary_realpath: Path | None = None
    if server_binary and Path(server_binary).exists():
        binary_realpath = Path(server_binary).resolve()
        evidence["server_binary_realpath"] = str(binary_realpath)
        evidence["server_binary_size"] = binary_realpath.stat().st_size
        evidence["server_binary_sha256"] = sha256_file(binary_realpath)
        with binary_realpath.open("rb") as f:
            evidence["server_binary_is_elf"] = f.read(4) == ELF_MAGIC

        if not evidence["server_binary_is_elf"]:
            stub_reasons.append("server binary is not an ELF executable")
        if evidence["server_binary_size"] < MIN_BINARY_SIZE:
            stub_reasons.append(
                f"server binary size {evidence['server_binary_size']} B is below {MIN_BINARY_SIZE} B"
            )
        try:
            binary_realpath.relative_to(install_prefix.resolve())
            evidence["server_binary_under_externals_install"] = True
        except ValueError:
            evidence["server_binary_under_externals_install"] = False
            missing.append(
                f"server binary {binary_realpath} is not under externals install prefix {install_prefix}"
            )
    else:
        evidence["server_binary_realpath"] = None
        evidence["server_binary_size"] = None
        evidence["server_binary_sha256"] = None
        evidence["server_binary_is_elf"] = None
        evidence["server_binary_under_externals_install"] = False
        missing.append("server_binary not found at recorded path")

    # --- 2. Stub keywords in version string -----------------------------
    raw_version = metadata.get("server_version") or ""
    version = raw_version.lower()
    for kw in STUB_KEYWORDS:
        if kw in version:
            stub_reasons.append(
                f"server_version contains stub keyword '{kw}': {raw_version!r}"
            )
            break

    # --- 3. EXTERNALS.lock ----------------------------------------------
    lock_path = externals_root / "EXTERNALS.lock"
    evidence["externals_lock_path"] = str(lock_path)
    evidence["externals_lock_present"] = lock_path.is_file()
    commits = parse_lock(lock_path)
    evidence["externals_commits"] = commits
    if not evidence["externals_lock_present"]:
        missing.append(f"EXTERNALS.lock not present at {lock_path}")
    elif "rcssserver" not in commits:
        missing.append("EXTERNALS.lock has no rcssserver commit line")

    # --- 4. Game / text log non-emptiness -------------------------------
    rcgs = list(run_dir.glob("*.rcg")) + list(run_dir.glob("*.rcg.gz"))
    rcls = list(run_dir.glob("*.rcl"))
    rcg_nonempty = any(p.stat().st_size > 0 for p in rcgs)
    rcl_nonempty = any(p.stat().st_size > 0 for p in rcls)
    evidence["rcg_nonempty"] = rcg_nonempty
    evidence["rcl_nonempty"] = rcl_nonempty
    if not rcg_nonempty:
        missing.append("no non-empty .rcg game log under run_dir")
    if not rcl_nonempty:
        missing.append("no non-empty .rcl text log under run_dir")

    # --- 5. Team start commands resolved --------------------------------
    for side in ("home", "away"):
        cmd = metadata.get(f"{side}_start_command") or ""
        realpath: str | None = None
        if cmd and not cmd.startswith("UNVERIFIED:"):
            p = Path(cmd)
            if p.exists():
                realpath = str(p.resolve())
        evidence[f"{side}_start_command_realpath"] = realpath
        if realpath is None:
            missing.append(
                f"{side}_start_command not resolvable to a file: {cmd!r}"
            )

    # --- Determine observed_reality_status ------------------------------
    if stub_reasons:
        observed = "synthetic_or_stubbed"
        all_missing = stub_reasons + missing
    elif missing:
        observed = "unknown_or_unverified"
        all_missing = missing
    else:
        observed = "real_rcssserver"
        all_missing = []

    return evidence, all_missing, observed


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="attest_runtime.py",
        description="Record runtime evidence and set observed_reality_status.",
    )
    p.add_argument("--run-dir", type=Path, required=True,
                   help="Match run directory; metadata.json must exist there.")
    p.add_argument("--externals-root", type=Path, default=None,
                   help="externals/ root. Default: <repo>/externals/.")
    p.add_argument("--externals-install-prefix", type=Path, default=None,
                   help="Install prefix to use for the 'binary under externals install' check. "
                        "Default: <externals-root>/install/.")
    return p


def _default_externals_root() -> Path:
    return Path(__file__).resolve().parent.parent / "externals"


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    externals_root = args.externals_root or _default_externals_root()
    install_prefix = args.externals_install_prefix or (externals_root / "install")

    metadata_path = args.run_dir / "metadata.json"
    if not metadata_path.is_file():
        print(f"attest_runtime.py: no metadata.json under {args.run_dir}", file=sys.stderr)
        return 2

    evidence, missing, observed = gather(args.run_dir, externals_root, install_prefix)

    # Merge: read existing metadata, augment with attestation fields,
    # write back. Other fields (including any future ones) survive.
    metadata = json.loads(metadata_path.read_text())
    metadata["observed_reality_status"] = observed
    metadata["reality_evidence"] = evidence
    metadata["reality_evidence_missing"] = missing
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")

    print(json.dumps({
        "observed_reality_status": observed,
        "reality_evidence_missing": missing,
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
