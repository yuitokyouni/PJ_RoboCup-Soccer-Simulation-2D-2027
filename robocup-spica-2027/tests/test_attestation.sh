#!/usr/bin/env bash
# test_attestation.sh - assert that scripts/attest_runtime.py never
# promotes a stub or evidence-missing case to real_rcssserver.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ATTEST="$ROOT/scripts/attest_runtime.py"
FAILED=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1: $2" >&2; FAILED=$((FAILED+1)); }

# Build a minimal metadata.json describing the inputs we want
# attestation to see. Real-attestation field references are made by
# scripts/run_smoke_match.sh; we mimic the relevant shape here.
write_metadata() {
  local dir="$1" binary="$2" version="$3" home="$4" away="$5"
  cat > "$dir/metadata.json" <<EOF
{
  "schema_version": "1.3",
  "run_id": "$(basename "$dir")",
  "server_binary": "$binary",
  "server_version": "$version",
  "applied_server_options": [],
  "declared_reality_assertion": "real_rcssserver",
  "home_start_command": "$home",
  "away_start_command": "$away",
  "timeout_secs": 120,
  "match_status": "match_completed"
}
EOF
}

extract() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['observed_reality_status'])" "$1"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Empty externals dir for the "no lock" cases.
EMPTY_EXTERNALS="$WORK/externals_empty"
mkdir -p "$EMPTY_EXTERNALS/install/bin"

# Externals dir with a lock file, used by the real-style case.
FULL_EXTERNALS="$WORK/externals_full"
mkdir -p "$FULL_EXTERNALS/install/bin"
cat > "$FULL_EXTERNALS/EXTERNALS.lock" <<'EOF'
rcssserver https://example/rcssserver rcssserver-19.0.0 0123456789abcdef0123456789abcdef01234567
EOF

# Plausible team start scripts (existing files; the attest check only
# requires existence).
START="$WORK/start.sh"
echo '#!/usr/bin/env bash' > "$START"
chmod +x "$START"

# ----- Case 1: bash-script stub binary -----
RUN1="$WORK/case1_stub"
mkdir -p "$RUN1"
STUB_BIN="$WORK/rcssserver_stub"
cat > "$STUB_BIN" <<'EOF'
#!/usr/bin/env bash
echo "fake-rcssserver 18"
EOF
chmod +x "$STUB_BIN"
write_metadata "$RUN1" "$STUB_BIN" "fake-rcssserver 18" "$START" "$START"
python3 "$ATTEST" --run-dir "$RUN1" --externals-root "$EMPTY_EXTERNALS" >/dev/null
got=$(extract "$RUN1/metadata.json")
[[ "$got" == "synthetic_or_stubbed" ]] \
  && pass "bash-script stub -> synthetic_or_stubbed" \
  || fail "bash-script stub" "expected synthetic_or_stubbed, got $got"

# ----- Case 2: ELF binary outside externals/install -----
RUN2="$WORK/case2_elf_offsite"
mkdir -p "$RUN2"
ELF_BIN="$WORK/rcssserver_elf_offsite"
python3 -c "import sys; open(sys.argv[1],'wb').write(b'\x7fELF' + b'\\x00' * 20000)" "$ELF_BIN"
chmod +x "$ELF_BIN"
# Non-empty rcg/rcl so log-emptiness isn't the blocker.
printf 'x' > "$RUN2/dummy.rcg"
printf 'y' > "$RUN2/dummy.rcl"
write_metadata "$RUN2" "$ELF_BIN" "rcssserver-19.0.0" "$START" "$START"
python3 "$ATTEST" --run-dir "$RUN2" --externals-root "$FULL_EXTERNALS" >/dev/null
got=$(extract "$RUN2/metadata.json")
[[ "$got" == "unknown_or_unverified" ]] \
  && pass "ELF binary outside externals/install -> unknown_or_unverified" \
  || fail "ELF outside install" "expected unknown_or_unverified, got $got"

# ----- Case 3: ELF binary inside externals/install, but version says stub -----
RUN3="$WORK/case3_elf_stubversion"
mkdir -p "$RUN3"
ELF_IN="$FULL_EXTERNALS/install/bin/rcssserver_stubver"
python3 -c "import sys; open(sys.argv[1],'wb').write(b'\x7fELF' + b'\\x00' * 20000)" "$ELF_IN"
chmod +x "$ELF_IN"
printf 'x' > "$RUN3/dummy.rcg"
printf 'y' > "$RUN3/dummy.rcl"
write_metadata "$RUN3" "$ELF_IN" "mock-rcssserver 1" "$START" "$START"
python3 "$ATTEST" --run-dir "$RUN3" --externals-root "$FULL_EXTERNALS" >/dev/null
got=$(extract "$RUN3/metadata.json")
[[ "$got" == "synthetic_or_stubbed" ]] \
  && pass "ELF inside install but stub keyword in version -> synthetic_or_stubbed" \
  || fail "ELF inside install + stub keyword" "expected synthetic_or_stubbed, got $got"

# ----- Case 4: ELF binary inside externals/install with real version -----
# This SHOULD promote to real_rcssserver because every check is satisfied.
RUN4="$WORK/case4_real_like"
mkdir -p "$RUN4"
ELF_REAL="$FULL_EXTERNALS/install/bin/rcssserver_real"
python3 -c "import sys; open(sys.argv[1],'wb').write(b'\x7fELF' + b'\\x00' * 20000)" "$ELF_REAL"
chmod +x "$ELF_REAL"
printf 'x' > "$RUN4/dummy.rcg"
printf 'y' > "$RUN4/dummy.rcl"
write_metadata "$RUN4" "$ELF_REAL" "rcssserver-19.0.0" "$START" "$START"
python3 "$ATTEST" --run-dir "$RUN4" --externals-root "$FULL_EXTERNALS" >/dev/null
got=$(extract "$RUN4/metadata.json")
[[ "$got" == "real_rcssserver" ]] \
  && pass "ELF inside install + clean version + lock + logs -> real_rcssserver" \
  || fail "ELF real-like" "expected real_rcssserver, got $got"

if (( FAILED > 0 )); then
  echo
  echo "$FAILED attestation check(s) failed." >&2
  exit 1
fi
echo
echo "all attestation checks passed."
