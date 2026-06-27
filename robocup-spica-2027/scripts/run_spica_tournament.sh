#!/usr/bin/env bash
# Round-robin Spica edition tournament.
#
# Editions (all share the same v3 binary; only their formation conf dir differs,
# selected at launch via start.sh -f <dir>):
#   REV   -- Y-symmetric F433 + defensive kickoff (the "守備重視" current state)
#   MERGE -- Y-symmetric F433 + merged kickoff (for_our_kick cloned into both;
#            "攻撃重視" — more goals but leakier defense)
#   ORIG  -- vanilla asymmetric F433 (Phase 9 baseline; no Y-sym, defensive kickoff)
#   V     -- Cyrus vanilla binary (reference, not a Spica edition; included so we
#            can see each edition's gap vs the no-patches baseline)
#
# For each of the 6 unordered pairs we run n=4 matches: 2 with team A on LEFT and
# 2 with team A on RIGHT.  Total: 24 matches.
#
# Usage from the project root:
#   PATH="$PWD/externals/install/bin:$PATH" bash scripts/run_spica_tournament.sh
#
# Writes per-pair experiments to logs/experiments/tourney_<A>_vs_<B>_<side>/
# and a final ranking to logs/experiments/tourney_summary.json.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if ! command -v rcssserver >/dev/null 2>&1; then
  echo "ERROR: rcssserver not in PATH. Export externals/install/bin." >&2
  exit 2
fi

# (label, left_launcher, right_launcher)
declare -A LEFT RIGHT
LEFT[REV]=scripts/team_launchers/spica_rev_left.sh
RIGHT[REV]=scripts/team_launchers/spica_rev_right.sh
LEFT[MERGE]=scripts/team_launchers/spica_merge_left.sh
RIGHT[MERGE]=scripts/team_launchers/spica_merge_right.sh
LEFT[ORIG]=scripts/team_launchers/spica_orig_left.sh
RIGHT[ORIG]=scripts/team_launchers/spica_orig_right.sh
LEFT[V]=scripts/team_launchers/cyrus_vanilla_left.sh
RIGHT[V]=scripts/team_launchers/cyrus_vanilla_right.sh

# Unordered pairs (6 total)
PAIRS=(
  "REV MERGE"
  "REV ORIG"
  "REV V"
  "MERGE ORIG"
  "MERGE V"
  "ORIG V"
)

N=2  # matches per side per pair (n=4 per pair)

mk_yaml() {
  local name=$1 home=$2 away=$3 hcmd=$4 acmd=$5 n=$6
  cat > "experiments/${name}.yaml" <<EOF
schema_version: "0.1.0"
experiment_id: "${name}"
description: "Round-robin tournament leg: ${home} vs ${away}."
home_team: "${home}"
away_team: "${away}"
home_start_command: "${hcmd}"
away_start_command: "${acmd}"
num_matches: ${n}
timeout_secs: 600
declared_reality_assertion: "real_rcssserver"
server_options:
  - "server::synch_mode=true"
  - "server::penalty_shoot_outs=false"
  - "server::nr_extra_halfs=0"
EOF
}

for pair in "${PAIRS[@]}"; do
  read -r A B <<<"$pair"
  for direction in AB BA; do
    if [[ "$direction" == "AB" ]]; then
      H=$A; AW=$B
    else
      H=$B; AW=$A
    fi
    name="tourney_${H}_vs_${AW}_${direction,,}"
    rm -rf "logs/experiments/${name}"
    mk_yaml "$name" "$H" "$AW" "${LEFT[$H]}" "${RIGHT[$AW]}" "$N"
    echo "=== ${name} ==="
    bash scripts/run_batch_matches.sh --experiment "experiments/${name}.yaml" 2>&1 | tail -4
  done
done

# Aggregate.
python3 - <<'PYEOF'
import csv, glob, json, pathlib, collections
ROOT = pathlib.Path("logs/experiments")
LABELS = ["REV", "MERGE", "ORIG", "V"]
gd = collections.Counter()
games = collections.Counter()
for s in sorted(ROOT.glob("tourney_*/summary.csv")):
    with open(s) as f:
        for row in csv.DictReader(f):
            h, a = row["home_team"], row["away_team"]
            try:
                d = int(row["goal_diff"])
            except (TypeError, ValueError):
                continue
            if h in LABELS: gd[h] += d; games[h] += 1
            if a in LABELS: gd[a] -= d; games[a] += 1
out = {
    lbl: {
        "games": games[lbl],
        "total_goal_diff": gd[lbl],
        "mean_goal_diff": (gd[lbl] / games[lbl]) if games[lbl] else None,
    }
    for lbl in LABELS
}
print(json.dumps(out, indent=2))
pathlib.Path("logs/experiments/tourney_summary.json").write_text(json.dumps(out, indent=2) + "\n")
PYEOF

echo "tourney summary -> logs/experiments/tourney_summary.json"
