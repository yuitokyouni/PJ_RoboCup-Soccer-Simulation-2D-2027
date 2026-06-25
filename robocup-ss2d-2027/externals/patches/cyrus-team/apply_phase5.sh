#!/usr/bin/env bash
# apply_phase5.sh - install Phase 5a-5e patches into cyrus-soccer-
# simulation-team in place.
#
# Idempotent: re-running is safe (each step guards on a sentinel
# marker). Run AFTER the apply.sh that fixes vendor/rapidjson.cmake.
#
# Usage:
#   apply_phase5.sh <path-to-cyrus-team>
set -euo pipefail

PATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYRUS="${1:-}"

if [[ -z "$CYRUS" || ! -d "$CYRUS/src" ]]; then
  echo "apply_phase5.sh: usage: apply_phase5.sh <path-to-cyrus-team>" >&2
  exit 2
fi

SRC="$CYRUS/src"
echo "[phase5] target: $CYRUS"

# -------------------------------------------------------------------
# Step 1: copy new phase5 sources into <cyrus>/src/phase5/
# -------------------------------------------------------------------
echo "[phase5] copying phase5 modules"
mkdir -p "$SRC/phase5"
for f in chance_signal.h chance_signal.cpp \
         bhv_smart_clearance.h bhv_smart_clearance.cpp \
         territory_recovery_state.h territory_recovery_state.cpp \
         counter_press_state.h counter_press_state.cpp \
         defense_block.h defense_block.cpp; do
  if [[ -f "$PATCH_ROOT/src/phase5/$f" ]]; then
    cp -v "$PATCH_ROOT/src/phase5/$f" "$SRC/phase5/$f"
  else
    echo "[phase5] WARN: missing source $f -- skipping (build will fail if needed)" >&2
  fi
done

# -------------------------------------------------------------------
# Step 2: copy F325 formation files
# -------------------------------------------------------------------
echo "[phase5] copying F325 formation files"
mkdir -p "$SRC/formations-dt"
for f in "$PATCH_ROOT"/src/formations-dt/F325_*.conf; do
  cp -v "$f" "$SRC/formations-dt/"
done

# -------------------------------------------------------------------
# Step 3: patch strategy.h (add F325 enum + constants + members)
# -------------------------------------------------------------------
echo "[phase5] patching strategy.h"
python3 - "$SRC/strategy.h" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
if 'PHASE5_F325' in src:
    print('  strategy.h already patched; skipping')
    sys.exit(0)

# 3a: extend FormationType enum
anchor = '''enum class FormationType{
    F433,
    HeliosFra,
    F523
};'''
new = '''enum class FormationType{
    F433,
    HeliosFra,
    F523,
    // PHASE5_F325: 3-2-5 wing-back-fluid (rest shape 3-4-3).
    F325
};'''
if anchor not in src:
    sys.exit('  ERROR: FormationType enum anchor not found in strategy.h')
src = src.replace(anchor, new, 1)

# 3b: add 9 static const std::string members for F325 conf paths.
#     Insert right after the Fhel_SETPLAY_OUR_FORMATION_CONF line.
anchor = '    static const std::string Fhel_SETPLAY_OUR_FORMATION_CONF;'
add = anchor + '''

    // PHASE5_F325 conf path declarations.
    static const std::string F325_BEFORE_KICK_OFF_CONF;
    static const std::string F325_BEFORE_KICK_OFF_CONF_FOR_OUR_KICK;
    static const std::string F325_DEFENSE_FORMATION_CONF;
    static const std::string F325_OFFENSE_FORMATION_CONF;
    static const std::string F325_GOAL_KICK_OPP_FORMATION_CONF;
    static const std::string F325_GOAL_KICK_OUR_FORMATION_CONF;
    static const std::string F325_KICKIN_OUR_FORMATION_CONF;
    static const std::string F325_SETPLAY_OPP_FORMATION_CONF;
    static const std::string F325_SETPLAY_OUR_FORMATION_CONF;'''
if anchor not in src:
    sys.exit('  ERROR: Fhel_SETPLAY_OUR_FORMATION_CONF anchor not found')
src = src.replace(anchor, add, 1)

# 3c: add 9 Formation::Ptr members. Insert right after
#     M_Fhel_setplay_our_formation declaration.
anchor = '    rcsc::Formation::Ptr M_Fhel_setplay_our_formation;'
add = anchor + '''

    // PHASE5_F325 formation pointers.
    rcsc::Formation::Ptr M_F325_before_kick_off_formation;
    rcsc::Formation::Ptr M_F325_before_kick_off_formation_for_our_kick;
    rcsc::Formation::Ptr M_F325_defense_formation;
    rcsc::Formation::Ptr M_F325_offense_formation;
    rcsc::Formation::Ptr M_F325_goal_kick_opp_formation;
    rcsc::Formation::Ptr M_F325_goal_kick_our_formation;
    rcsc::Formation::Ptr M_F325_kickin_our_formation;
    rcsc::Formation::Ptr M_F325_setplay_opp_formation;
    rcsc::Formation::Ptr M_F325_setplay_our_formation;'''
if anchor not in src:
    sys.exit('  ERROR: M_Fhel_setplay_our_formation anchor not found')
src = src.replace(anchor, add, 1)

# 3d: add updateFormation325 declaration alongside updateFormation523
anchor = '    void updateFormation523( const rcsc::WorldModel & wm );'
add = anchor + '\n    // PHASE5_F325\n    void updateFormation325( const rcsc::WorldModel & wm );'
if anchor not in src:
    sys.exit('  ERROR: updateFormation523 declaration anchor not found')
src = src.replace(anchor, add, 1)

# 3e: extend stringToFormationType
anchor = '''        else if (formation == "523")
            return FormationType::F523;'''
add = anchor + '''
        else if (formation == "325")
            return FormationType::F325;  // PHASE5_F325'''
if anchor not in src:
    sys.exit('  ERROR: stringToFormationType "523" anchor not found')
src = src.replace(anchor, add, 1)

p.write_text(src)
print('  strategy.h patched')
PYEOF

# -------------------------------------------------------------------
# Step 4: patch strategy.cpp
# -------------------------------------------------------------------
echo "[phase5] patching strategy.cpp"

# Stamp the patched function body for inclusion.
F325_BODY="$(cat "$PATCH_ROOT/src/phase5/update_formation_325.cpp")"

python3 - "$SRC/strategy.cpp" "$PATCH_ROOT/src/phase5/update_formation_325.cpp" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
body_file = pathlib.Path(sys.argv[2])
src = p.read_text()
if 'PHASE5_F325' in src:
    print('  strategy.cpp already patched; skipping')
    sys.exit(0)

# 4a: add 9 const string definitions right after the Fhel block.
anchor = 'const std::string Strategy::Fhel_SETPLAY_OUR_FORMATION_CONF = "Fhel_setplay-our-formation.conf";'
add = anchor + '''

// PHASE5_F325 conf path definitions.
const std::string Strategy::F325_BEFORE_KICK_OFF_CONF = "F325_before-kick-off.conf";
const std::string Strategy::F325_BEFORE_KICK_OFF_CONF_FOR_OUR_KICK = "F325_before-kick-off_for_our_kick.conf";
const std::string Strategy::F325_DEFENSE_FORMATION_CONF = "F325_defense-formation.conf";
const std::string Strategy::F325_OFFENSE_FORMATION_CONF = "F325_offense-formation.conf";
const std::string Strategy::F325_GOAL_KICK_OPP_FORMATION_CONF = "F325_goal-kick-opp.conf";
const std::string Strategy::F325_GOAL_KICK_OUR_FORMATION_CONF = "F325_goal-kick-our.conf";
const std::string Strategy::F325_KICKIN_OUR_FORMATION_CONF = "F325_kickin-our-formation.conf";
const std::string Strategy::F325_SETPLAY_OPP_FORMATION_CONF = "F325_setplay-opp-formation.conf";
const std::string Strategy::F325_SETPLAY_OUR_FORMATION_CONF = "F325_setplay-our-formation.conf";'''
if anchor not in src:
    sys.exit('  ERROR: Fhel_SETPLAY_OUR_FORMATION_CONF definition anchor not found')
src = src.replace(anchor, add, 1)

# 4b: add F325 load block right before `s_initialized = true;`. Match
#     the LAST `s_initialized = true;` (there should be only one in
#     Strategy::read()).
anchor = '''    s_initialized = true;
    return true;
}'''
add = '''    // PHASE5_F325 formation loads.
    M_F325_before_kick_off_formation = readFormation( configpath + F325_BEFORE_KICK_OFF_CONF );
    if ( ! M_F325_before_kick_off_formation ) { std::cerr << "Failed to read F325 before_kick_off formation" << std::endl; return false; }
    M_F325_before_kick_off_formation_for_our_kick = readFormation( configpath + F325_BEFORE_KICK_OFF_CONF_FOR_OUR_KICK );
    if ( ! M_F325_before_kick_off_formation_for_our_kick ) { std::cerr << "Failed to read F325 before_kick_off_for_our_kick formation" << std::endl; return false; }
    M_F325_defense_formation = readFormation( configpath + F325_DEFENSE_FORMATION_CONF );
    if ( ! M_F325_defense_formation ) { std::cerr << "Failed to read F325 defense formation" << std::endl; return false; }
    M_F325_offense_formation = readFormation( configpath + F325_OFFENSE_FORMATION_CONF );
    if ( ! M_F325_offense_formation ) { std::cerr << "Failed to read F325 offense formation" << std::endl; return false; }
    M_F325_goal_kick_opp_formation = readFormation( configpath + F325_GOAL_KICK_OPP_FORMATION_CONF );
    if ( ! M_F325_goal_kick_opp_formation ) { std::cerr << "Failed to read F325 goal_kick_opp formation" << std::endl; return false; }
    M_F325_goal_kick_our_formation = readFormation( configpath + F325_GOAL_KICK_OUR_FORMATION_CONF );
    if ( ! M_F325_goal_kick_our_formation ) { std::cerr << "Failed to read F325 goal_kick_our formation" << std::endl; return false; }
    M_F325_kickin_our_formation = readFormation( configpath + F325_KICKIN_OUR_FORMATION_CONF );
    if ( ! M_F325_kickin_our_formation ) { std::cerr << "Failed to read F325 kickin_our formation" << std::endl; return false; }
    M_F325_setplay_opp_formation = readFormation( configpath + F325_SETPLAY_OPP_FORMATION_CONF );
    if ( ! M_F325_setplay_opp_formation ) { std::cerr << "Failed to read F325 setplay_opp formation" << std::endl; return false; }
    M_F325_setplay_our_formation = readFormation( configpath + F325_SETPLAY_OUR_FORMATION_CONF );
    if ( ! M_F325_setplay_our_formation ) { std::cerr << "Failed to read F325 setplay_our formation" << std::endl; return false; }

    s_initialized = true;
    return true;
}'''
if anchor not in src:
    sys.exit('  ERROR: s_initialized=true anchor not found')
src = src.replace(anchor, add, 1)

# 4c: add F325 case to updateFormation dispatcher.
anchor = '''    else if(M_formation_type == FormationType::F523)
        updateFormation523(wm);
}'''
add = '''    else if(M_formation_type == FormationType::F523)
        updateFormation523(wm);
    // PHASE5_F325
    else if(M_formation_type == FormationType::F325)
        updateFormation325(wm);
}'''
if anchor not in src:
    sys.exit('  ERROR: updateFormation F523 dispatch anchor not found')
src = src.replace(anchor, add, 1)

# 4d: append updateFormation325 function body at end of file.
body = body_file.read_text()
# Strip the leading comment + take only the function (everything from
# `void Strategy::updateFormation325(`).
idx = body.find('void Strategy::updateFormation325(')
if idx < 0:
    sys.exit('  ERROR: update_formation_325.cpp does not declare updateFormation325')
function_body = body[idx:]
src = src.rstrip() + '\n\n// PHASE5_F325 implementation\n' + function_body + '\n'
p.write_text(src)
print('  strategy.cpp patched')
PYEOF

# -------------------------------------------------------------------
# Step 5: patch bhv_basic_move.cpp (counter-press tick + defense_block
# modulator)
# -------------------------------------------------------------------
echo "[phase5] patching bhv_basic_move.cpp"
python3 - "$SRC/bhv_basic_move.cpp" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
if 'PHASE5_BBM' in src:
    print('  bhv_basic_move.cpp already patched; skipping')
    sys.exit(0)

# 5a: add includes after the `using namespace rcsc;` line.
anchor = 'using namespace rcsc;'
add = anchor + '''

// PHASE5_BBM: Phase 5 defensive/offensive modulation hooks.
#include "phase5/counter_press_state.h"
#include "phase5/defense_block.h"'''
if anchor not in src:
    sys.exit('  ERROR: using namespace rcsc anchor not found in bhv_basic_move.cpp')
src = src.replace(anchor, add, 1)

# 5b: tick counter-press state at top of execute().
anchor = 'const WorldModel &wm = agent->world();\n    //-----------------------------------------------\n    // tackle'
add = '''const WorldModel &wm = agent->world();
    // PHASE5_BBM: tick the counter-press transition tracker first so
    // any downstream behavior reads up-to-date state for this cycle.
    cyrus_phase5::CounterPressState::instance().update(wm);
    //-----------------------------------------------
    // tackle'''
if anchor not in src:
    sys.exit('  ERROR: tackle block anchor not found')
src = src.replace(anchor, add, 1)

# 5c: apply defense_block modulator at end of updateTarget(). Find the
#     closing brace of updateTarget by anchoring on the function
#     signature and replacing the final brace within it.
#     Easier: find the unique line "void Bhv_BasicMove::updateTarget(",
#     then find the matching closing brace by counting. But simplest:
#     anchor on the LAST few lines of updateTarget before the brace.
# The function ends with role-specific blocks; the LAST recognizable
# closing brace immediately follows them. We append the modulator
# call as the very last statement before the function-closing brace.
# Strategy: find the unique signature, then find the next "^}" line.
sig = 'void Bhv_BasicMove::updateTarget(const rcsc::WorldModel & wm, rcsc::Vector2D & target_point, bool & can_5_join_offense) {'
i = src.find(sig)
if i < 0:
    sys.exit('  ERROR: updateTarget signature not found in bhv_basic_move.cpp')
# walk braces
depth = 0
j = i + len(sig)
started = False
while j < len(src):
    c = src[j]
    if c == '{':
        depth += 1
        started = True
    elif c == '}':
        depth -= 1
        if started and depth == 0:
            break
    j += 1
if j >= len(src):
    sys.exit('  ERROR: could not find updateTarget closing brace')
# Insert modulator call before the closing brace.
inject = '''
    // PHASE5_BBM: apply defense block + WB retreat modulation as the
    // last step so it stacks on Cyrus's existing stamina overrides.
    target_point = cyrus_phase5::modulate_position(wm, wm.self().unum(), target_point);
'''
src = src[:j] + inject + src[j:]

p.write_text(src)
print('  bhv_basic_move.cpp patched')
PYEOF

# -------------------------------------------------------------------
# Step 6: patch bhv_chain_action.cpp (smart clearance fallback in
# hold_ball())
# -------------------------------------------------------------------
echo "[phase5] patching bhv_chain_action.cpp"
python3 - "$SRC/chain_action/bhv_chain_action.cpp" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
if 'PHASE5_CHAIN' in src:
    print('  bhv_chain_action.cpp already patched; skipping')
    sys.exit(0)

# 6a: add include. Place after the last existing #include line.
import re
m = list(re.finditer(r'^#include .+$', src, flags=re.M))
if not m:
    sys.exit('  ERROR: no #include lines in bhv_chain_action.cpp')
last_inc_end = m[-1].end()
inj = '\n\n// PHASE5_CHAIN: smart clearance fallback.\n#include "../phase5/bhv_smart_clearance.h"'
src = src[:last_inc_end] + inj + src[last_inc_end:]

# 6b: inject in hold_ball(). The survey points to L351-364. We can't
# easily target by line number after the include patch shifted things,
# so use a content anchor: the docstring or signature of hold_ball.
# Try a few likely shapes.
candidates = [
    'Bhv_ChainAction::hold_ball(',
    'hold_ball(',
]
sig = None
for c in candidates:
    if c in src:
        sig = c
        break
if sig is None:
    sys.exit('  ERROR: hold_ball not found in bhv_chain_action.cpp')

# Find body opening brace
i = src.find(sig)
# advance to the next '{' after the signature
brace = src.find('{', i)
if brace < 0:
    sys.exit('  ERROR: hold_ball body { not found')
# Insert smart-clearance probe right after the opening brace.
inject = '''
    // PHASE5_CHAIN: attempt smart clearance before falling back to
    // hold/dribble. Only kicks if a safe corner / past-CB target is
    // available; otherwise drops through to Cyrus's default hold.
    if ( cyrus_phase5::Bhv_SmartClearance().execute( agent ) ) {
        return true;
    }
'''
src = src[:brace+1] + inject + src[brace+1:]

p.write_text(src)
print('  bhv_chain_action.cpp patched')
PYEOF

# -------------------------------------------------------------------
# Step 7: patch action_chain_graph.cpp (chance-signal post-evaluation
# bias). The Field Evaluator's evaluate_state() does NOT have a
# WorldModel reference in scope, but action_chain_graph DOES at the
# per-candidate evaluation call. Inject the chance-signal bias there.
# -------------------------------------------------------------------
echo "[phase5] patching action_chain_graph.cpp"
python3 - "$SRC/chain_action/action_chain_graph.cpp" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
src = p.read_text()
if 'PHASE5_ACG' in src:
    print('  action_chain_graph.cpp already patched; skipping')
    sys.exit(0)

# Add include after sample_player.h.
anchor = '#include "sample_player.h"'
add = anchor + '''

// PHASE5_ACG: chance-signal multiplier on per-candidate evaluation.
#include "../phase5/chance_signal.h"'''
if anchor not in src:
    sys.exit('  ERROR: sample_player.h include anchor not found')
src = src.replace(anchor, add, 1)

# Inject bias right after the per-candidate evaluation call.
eval_anchor = 'double ev = (*M_evaluator)( (*it).state(),wm, candidate_series );'
bias_block = eval_anchor + '''
            // PHASE5_ACG: bias the per-candidate evaluation by the
            // chance signal. High chance + forward (Pass/Shoot) gets a
            // bonus, low chance + Hold/Move (settle the ball) gets a
            // bonus. Cap the swing so the underlying evaluator still
            // dominates.
            if ( !candidate_series.empty() ) {
                const double cs = cyrus_phase5::compute_chance_signal( wm );
                const auto cat = candidate_series[0].action().category();
                const bool forward_cat = ( cat == CooperativeAction::Pass
                                           || cat == CooperativeAction::Shoot
                                           || cat == CooperativeAction::Dribble );
                const bool hold_cat    = ( cat == CooperativeAction::Hold
                                           || cat == CooperativeAction::Move );
                double bias = 0.0;
                // Tuned 2026-06-25: keep the "decisive when chance is
                // high" property strong, but soften the penalty on
                // forward chains in chance-poor states so we still
                // pressure the defense via passing options.
                if ( cs > 0.7 && forward_cat ) bias = +30.0 * (cs - 0.7) / 0.3;
                else if ( cs < 0.3 && forward_cat ) bias = -8.0  * (0.3 - cs) / 0.3;
                else if ( cs < 0.3 && hold_cat )    bias = +6.0  * (0.3 - cs) / 0.3;
                ev += bias;
            }'''
if eval_anchor not in src:
    sys.exit('  ERROR: per-candidate evaluator call anchor not found')
src = src.replace(eval_anchor, bias_block, 1)

p.write_text(src)
print('  action_chain_graph.cpp patched')
PYEOF

# -------------------------------------------------------------------
# Step 8: patch CMakeLists.txt to compile phase5/*.cpp
# -------------------------------------------------------------------
echo "[phase5] patching src/CMakeLists.txt"
python3 - "$SRC/CMakeLists.txt" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
if 'PHASE5_CMAKE' in src:
    print('  CMakeLists.txt already patched; skipping')
    sys.exit(0)

# Find the sample_player target. We expect something like
# `add_executable(sample_player ...)`.
# We'll insert a glob + append BEFORE the call to add_executable, then
# append the glob result to the source list.
# Simpler: add a file(GLOB ...) block at the top and insert the
# variable into the existing sources.
inject = '''
# PHASE5_CMAKE: compile phase5 modules into sample_player.
file(GLOB PHASE5_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/phase5/*.cpp")
'''

# Insert near the top, just after cmake_minimum_required or project()
import re
m = re.search(r'^(cmake_minimum_required\(.*?\)|project\(.*?\))\s*$', src, flags=re.M)
if m:
    insert_at = m.end()
    src = src[:insert_at] + '\n' + inject + src[insert_at:]
else:
    # fallback: prepend
    src = inject + '\n' + src

# Append ${PHASE5_SOURCES} to add_executable(sample_player ...). The
# simplest mechanism: find "sample_player.cpp" inside an add_executable
# call and add ${PHASE5_SOURCES} on a new line below it.
target_anchor = 'sample_player.cpp'
if target_anchor in src:
    src = src.replace(target_anchor, target_anchor + '\n        ${PHASE5_SOURCES}', 1)
else:
    print('  WARN: could not find sample_player.cpp anchor in add_executable; phase5/*.cpp not auto-linked')
p.write_text(src)
print('  CMakeLists.txt patched')
PYEOF

# -------------------------------------------------------------------
# Step 9: switch the default "Other" tactics file to use Formation 325
# so when Cyrus plays an unknown opponent (HELIOS_R in our smokes),
# it picks our 3-2-5 instead of 4-3-3.
# -------------------------------------------------------------------
echo "[phase5] forcing Formation=\"325\" in Other.json"
python3 - "$CYRUS" <<'PYEOF'
import sys, pathlib, re
root = pathlib.Path(sys.argv[1])
# Find the data/settings dir relative to the build output (cmake copies
# it from src/, so we patch src/ which propagates to build/ on next
# cmake reconfigure).
candidates = [
    root / 'src' / 'data' / 'settings' / 'Other.json',
    root / 'build' / 'src' / 'data' / 'settings' / 'Other.json',
]
patched = 0
for path in candidates:
    if not path.exists():
        continue
    text = path.read_text()
    new = re.sub(r'"Formation"\s*:\s*"\d+"', '"Formation": "325"', text, count=1)
    if new != text:
        path.write_text(new)
        print(f'  patched {path}')
        patched += 1
if patched == 0:
    print('  WARN: Other.json not found in expected paths')
PYEOF

echo "[phase5] all steps complete."
echo "[phase5] next: cmake --build externals/src/cyrus-team/build"
