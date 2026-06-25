// Phase 5e: dynamic defense block + wing-back retreat.
//
// modulate_position() returns a SHIFTED target relative to the raw
// formation target, blending three signals while defending:
//   - lateral compression toward the ball side (ball.x + opp density)
//   - vertical cap for forwards (don't sit ahead of the ball)
//   - explicit wing-back retreat to hold the back line
// An optional territory-recovery forward bias is added when the
// CYRUS_PHASE5_TERRITORY_RECOVERY feature flag is set.

#include "defense_block.h"

#include <rcsc/player/world_model.h>
#include <rcsc/player/player_object.h>
#include <rcsc/common/logger.h>

#include <algorithm>
#include <cmath>
#include <cstdio>

#if defined(CYRUS_PHASE5_TERRITORY_RECOVERY) && CYRUS_PHASE5_TERRITORY_RECOVERY
#  include "territory_recovery_state.h"
#endif

namespace cyrus_phase5 {

namespace {

inline double clamp_d( double v, double lo, double hi ) {
    if ( v < lo ) return lo;
    if ( v > hi ) return hi;
    return v;
}

// Count opponents within `radius` of the ball position.
int count_opp_near_ball( const rcsc::WorldModel & wm, double radius ) {
    const rcsc::Vector2D ball_pos = wm.ball().pos();
    int n = 0;
    const rcsc::PlayerObject::Cont & opps = wm.opponents();
    for ( rcsc::PlayerObject::Cont::const_iterator it = opps.begin();
          it != opps.end(); ++it ) {
        if ( *it == 0 ) continue;
        if ( (*it)->posCount() > 10 ) continue;
        if ( (*it)->pos().dist( ball_pos ) <= radius ) {
            ++n;
        }
    }
    return n;
}

} // namespace

// ---- helpers ----------------------------------------------------

bool is_wing_back( int self_unum ) {
    // 3-2-5 wing-backs.
    return ( self_unum == 5 || self_unum == 8 );
}

// True if the unum is a forward in 3-2-5 (CF / RF / LF).
static bool is_forward_unum( int self_unum ) {
    return ( self_unum == 9 || self_unum == 10 || self_unum == 11 );
}

double lateral_shift_amount( const rcsc::WorldModel & wm ) {
    const rcsc::Vector2D ball_pos = wm.ball().pos();

    double base = 6.0;
    if ( ball_pos.x < -20.0 ) {
        base = 8.0;   // deep in our half, compress harder
    } else if ( ball_pos.x > 10.0 ) {
        base = 4.0;   // ball near midline, less shift
    }

    const int num_opp_near_ball = count_opp_near_ball( wm, 10.0 );
    double density_mod = 1.0 + 0.2 * ( num_opp_near_ball - 2 );
    density_mod = clamp_d( density_mod, 0.6, 1.4 );

    return base * density_mod;
}

double vertical_compression( const rcsc::WorldModel & wm ) {
    // The actual per-player cap is computed inside modulate_position
    // (it depends on whether the player is a forward and on ball.x).
    // This helper just exposes the "never past ball" rule as a number,
    // so tests / dlog can probe it.
    return wm.ball().pos().x - 2.0;
}

// ---- main entry -------------------------------------------------

rcsc::Vector2D modulate_position(
    const rcsc::WorldModel & wm,
    int self_unum,
    const rcsc::Vector2D & raw_target )
{
    const rcsc::Vector2D ball_pos = wm.ball().pos();

    // Guard: we are not "defending" if we have the ball, a teammate
    // has the ball, or the ball is deep in opp half.
    if ( wm.self().isKickable()
         || wm.kickableTeammate() != 0
         || ball_pos.x > 15.0 ) {
        return raw_target;
    }

    double shifted_x = raw_target.x;
    double shifted_y = raw_target.y;

    // -- step 1: LATERAL SHIFT toward ball-side --------------------
    const double shift = lateral_shift_amount( wm );
    if ( ball_pos.y > raw_target.y ) {
        shifted_y = raw_target.y + shift;
    } else {
        shifted_y = raw_target.y - shift;
    }
    // never overshoot ball.y (don't go past the ball in y) and stay
    // inside the touchlines.
    if ( ball_pos.y > raw_target.y ) {
        shifted_y = std::min( shifted_y, ball_pos.y );
    } else {
        shifted_y = std::max( shifted_y, ball_pos.y );
    }
    shifted_y = clamp_d( shifted_y, -32.0, 32.0 );

    // -- step 2: VERTICAL COMPRESSION for forwards -----------------
    if ( is_forward_unum( self_unum ) ) {
        const double max_forward_x_when_defending = ball_pos.x - 2.0;
        shifted_x = std::min( shifted_x, max_forward_x_when_defending );
    }

    // -- step 3: WING-BACK EXPLICIT RETREAT ------------------------
    if ( is_wing_back( self_unum ) ) {
        if ( ball_pos.x < -10.0 ) {
            // deep in our half — they MUST hold the back line
            shifted_x = std::min( shifted_x, -22.0 );
        } else if ( ball_pos.x < 10.0 ) {
            // around midline — half retreat
            shifted_x = std::min( shifted_x, -12.0 );
        }
        // ball.x > 10 was guarded out at the top of the function.
    }

    // -- step 4: TERRITORY RECOVERY BIAS ---------------------------
#if defined(CYRUS_PHASE5_TERRITORY_RECOVERY) && CYRUS_PHASE5_TERRITORY_RECOVERY
    {
        const int cycle_now = wm.time().cycle();
        const TerritoryRecoveryState & trs = TerritoryRecoveryState::instance();
        if ( trs.active( cycle_now ) ) {
            const double bias = trs.forward_bias( cycle_now );
            // forward_bias() is expected to return values in [5..8] m
            // while active, decaying to 0. Push every target up by it.
            shifted_x += bias;
        }
    }
#endif

    // -- log summary (only when modulation actually occurred) ------
    const double dx = shifted_x - raw_target.x;
    const double dy = shifted_y - raw_target.y;
    if ( std::fabs( dx ) > 1.0e-3 || std::fabs( dy ) > 1.0e-3 ) {
        rcsc::dlog.addText( rcsc::Logger::TEAM,
                      "[DefBlock] shift=(%.1f,%.1f)",
                      dx, dy );
    }

    return rcsc::Vector2D( shifted_x, shifted_y );
}

} // namespace cyrus_phase5
