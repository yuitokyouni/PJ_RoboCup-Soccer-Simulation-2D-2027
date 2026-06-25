// -*-c++-*-
#include "chance_signal.h"

#include <rcsc/player/world_model.h>
#include <rcsc/player/player_object.h>
#include <rcsc/common/server_param.h>
#include <rcsc/common/logger.h>
#include <rcsc/geom/vector_2d.h>
#include <rcsc/geom/segment_2d.h>
#include <rcsc/types.h>

#include <algorithm>
#include <cmath>
#include <vector>

// Phase 5d counter-press state: the file may not yet exist at build time, so
// we declare the symbols extern here. If counter_press_state.h is added later
// it must use C++ linkage with this same signature.
namespace cyrus_phase5 {
extern long counter_press_last_recovery_cycle();   // cycle number we last won the ball, -1 if never
extern bool counter_press_last_recovery_in_opp_half();
} // namespace cyrus_phase5

namespace {

inline double clamp01( double v ) {
    if ( v < 0.0 ) return 0.0;
    if ( v > 1.0 ) return 1.0;
    return v;
}

// Tunable weights. Kept here (not in header) to avoid ABI churn.
const double W_CONE  = 0.40;
const double W_MOM   = 0.30;
const double W_LANE  = 0.20;
const double W_PRESS = 0.10;

const double CONE_HALF_ANGLE_DEG = 15.0;   // 30 deg cone => 15 deg half
const double CONE_OPP_NORMALIZER = 4.0;    // saturate at 4 opps in cone
const int    MOMENTUM_K          = 5;
const double MOMENTUM_OFFSET     = 5.0;
const double MOMENTUM_SCALE      = 20.0;
const double LANE_RANGE_M        = 25.0;
const double LANE_BLOCK_RADIUS_M = 2.0;
const int    PRESS_RECENCY_CYC   = 20;
const double PRESS_BONUS         = 0.2;

} // anonymous namespace

namespace cyrus_phase5 {

double compute_chance_signal( const rcsc::WorldModel & wm )
{
    const rcsc::Vector2D ball_pos = wm.ball().pos();
    const rcsc::Vector2D opp_goal( rcsc::ServerParam::i().pitchHalfLength(), 0.0 );

    // ---- (1) opponents inside a 30-degree cone from ball toward opp goal ----
    const rcsc::AngleDeg cone_axis = ( opp_goal - ball_pos ).th();
    int num_opp_in_cone = 0;
    const double dist_to_goal = ball_pos.dist( opp_goal );

    const rcsc::PlayerObject::Cont & opps = wm.opponents();
    for ( const rcsc::PlayerObject * p : opps ) {
        if ( ! p ) continue;
        if ( p->isGhost() ) continue;
        if ( p->unum() < 1 ) continue;
        const rcsc::Vector2D rel = p->pos() - ball_pos;
        // only count opponents that are between ball and goal, not behind ball
        if ( rel.r() > dist_to_goal + 2.0 ) continue;
        const double diff = ( rel.th() - cone_axis ).abs();
        if ( diff <= CONE_HALF_ANGLE_DEG ) {
            ++num_opp_in_cone;
        }
    }
    const double cone_term = 1.0 - ( static_cast<double>(num_opp_in_cone) / CONE_OPP_NORMALIZER );

    // ---- (2) momentum: mean x of 5 most-forward teammates minus ball.x ----
    std::vector<double> fwd_x;
    fwd_x.reserve( 11 );
    const rcsc::PlayerObject::Cont & mates = wm.teammates();
    for ( const rcsc::PlayerObject * p : mates ) {
        if ( ! p ) continue;
        if ( p->isGhost() ) continue;
        if ( p->unum() < 1 ) continue;
        fwd_x.push_back( p->pos().x );
    }
    // descending x; take top K
    std::sort( fwd_x.begin(), fwd_x.end(), std::greater<double>() );
    double mean_fwd_x = ball_pos.x;
    if ( ! fwd_x.empty() ) {
        const int k = std::min( MOMENTUM_K, static_cast<int>( fwd_x.size() ) );
        double sum = 0.0;
        for ( int i = 0; i < k; ++i ) sum += fwd_x[i];
        mean_fwd_x = sum / k;
    }
    const double mom_term = ( mean_fwd_x - ball_pos.x + MOMENTUM_OFFSET ) / MOMENTUM_SCALE;

    // ---- (3) pass-lane openness: blocked lanes / total forward lanes ----
    int num_lanes    = 0;
    int blocked_lanes = 0;
    for ( const rcsc::PlayerObject * t : mates ) {
        if ( ! t ) continue;
        if ( t->isGhost() ) continue;
        if ( t->unum() < 1 ) continue;
        if ( t->pos().x <= ball_pos.x ) continue;          // forward only
        if ( t->pos().dist( ball_pos ) > LANE_RANGE_M ) continue;
        ++num_lanes;
        const rcsc::Segment2D lane( ball_pos, t->pos() );
        for ( const rcsc::PlayerObject * o : opps ) {
            if ( ! o ) continue;
            if ( o->isGhost() ) continue;
            if ( o->unum() < 1 ) continue;
            if ( lane.dist( o->pos() ) <= LANE_BLOCK_RADIUS_M ) {
                ++blocked_lanes;
                break;
            }
        }
    }
    double lane_term = 1.0;
    if ( num_lanes > 0 ) {
        lane_term = 1.0 - ( static_cast<double>(blocked_lanes) / num_lanes );
    }

    // ---- (4) counter-press recency bonus ----
    double press_bonus = 0.0;
    const long last_recover = counter_press_last_recovery_cycle();
    if ( last_recover >= 0 ) {
        const long age = wm.time().cycle() - last_recover;
        if ( age >= 0 && age <= PRESS_RECENCY_CYC
             && counter_press_last_recovery_in_opp_half() ) {
            press_bonus = PRESS_BONUS;
        }
    }
    // press_bonus already weighted by intent; W_PRESS keeps it inside the budget
    const double raw = clamp01(
        W_CONE  * cone_term
      + W_MOM   * mom_term
      + W_LANE  * lane_term
      + W_PRESS * ( press_bonus / PRESS_BONUS )   // normalize to [0,1] before weight
    );

    rcsc::dlog.addText( rcsc::Logger::TEAM,
                       "ChanceSignal=%.3f", raw );
    return raw;
}

} // namespace cyrus_phase5

// Weak default fallbacks for the counter-press hooks so this TU links cleanly
// before phase 5d lands. Phase 5d will provide strong overrides.
#if defined(__GNUC__)
namespace cyrus_phase5 {
__attribute__((weak)) long counter_press_last_recovery_cycle()        { return -1; }
__attribute__((weak)) bool counter_press_last_recovery_in_opp_half()  { return false; }
} // namespace cyrus_phase5
#endif
