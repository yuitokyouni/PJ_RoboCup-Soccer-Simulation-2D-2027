// -*-c++-*-
#include "intercept_discipline.h"

#include <rcsc/player/world_model.h>
#include <rcsc/player/player_object.h>
#include <rcsc/player/intercept_table.h>
#include <rcsc/common/server_param.h>
#include <rcsc/common/logger.h>
#include <rcsc/geom/vector_2d.h>

#include <algorithm>
#include <cmath>

namespace cyrus_phase5 {

namespace {

constexpr double OUR_GOAL_X        = -52.5;
constexpr double TEAMMATE_COVER_R  = 8.0;
constexpr double TEAMMATE_POSCOUNT = 10;
constexpr int    SELF_FAST_REACH   = 1;

inline bool is_cdm_unum( int u ) {
    return ( u == 6 || u == 7 );
}

// A teammate counts as "cover" if it sits within TEAMMATE_COVER_R of
// the midpoint between us and our goal AND librcsc's belief about the
// teammate's position is still fresh.
bool has_cover_behind( const rcsc::WorldModel & wm,
                       const rcsc::Vector2D & self_pos ) {
    const rcsc::Vector2D cover_mid(
        ( self_pos.x + OUR_GOAL_X ) * 0.5,
        self_pos.y * 0.5 );

    const rcsc::PlayerObject::Cont & mates = wm.teammates();
    for ( rcsc::PlayerObject::Cont::const_iterator it = mates.begin();
          it != mates.end(); ++it ) {
        if ( *it == 0 ) continue;
        if ( (*it)->posCount() > TEAMMATE_POSCOUNT ) continue;
        // Goalie at -52 inside the box does not count as midfield cover.
        if ( (*it)->goalie() ) continue;
        // Cover must actually be behind us, not ahead.
        if ( (*it)->pos().x >= self_pos.x ) continue;
        if ( (*it)->pos().dist( cover_mid ) <= TEAMMATE_COVER_R ) {
            return true;
        }
    }
    return false;
}

// A "runner" is an opponent positioned between us and our goal whose
// velocity has a meaningful component toward our goal (vel.x < 0 in
// team frame).
bool runner_behind( const rcsc::WorldModel & wm,
                    const rcsc::Vector2D & self_pos ) {
    const rcsc::PlayerObject::Cont & opps = wm.opponents();
    for ( rcsc::PlayerObject::Cont::const_iterator it = opps.begin();
          it != opps.end(); ++it ) {
        if ( *it == 0 ) continue;
        if ( (*it)->posCount() > 10 ) continue;
        const rcsc::Vector2D & op = (*it)->pos();
        if ( op.x >= self_pos.x ) continue;          // not behind us
        if ( op.x <= OUR_GOAL_X + 4.0 ) continue;    // already at/in our box
        if ( std::abs( op.y - self_pos.y ) > 18.0 ) continue;  // off the channel
        if ( (*it)->vel().x < -0.05 ) {
            return true;
        }
    }
    return false;
}

} // namespace

bool intercept_safe_for_unum( int self_unum,
                              const rcsc::WorldModel & wm ) {
    // PHASE8 KILL-SWITCH: balanced n=30 (15+15 LEFT-balanced) showed
    // Phase 8's gate regresses improved by -2.07 goal/match vs the prior
    // tie. The CDM is refusing intercepts in defensive cycles where it
    // should engage. Disabled pending a redesign:
    //   - tighter runner-velocity threshold (currently fires on any
    //     opp moving toward our goal)
    //   - looser cover-behind requirement (currently demands 8m radius
    //     around a midpoint that's effectively in the defensive third)
    //   - or restrict firing to opp-half counter-attacks only
    // See notes/2026-06-25_phase8_negative_result.md.
    return true;
    if ( ! is_cdm_unum( self_unum ) ) {
        return true;
    }

    const int self_min = wm.interceptTable().selfStep();
    if ( self_min <= SELF_FAST_REACH ) {
        // We are essentially on the ball; refusing here would let it
        // through unchallenged. Trust the standard Cyrus chase.
        return true;
    }

    const rcsc::Vector2D self_pos = wm.self().pos();
    const rcsc::Vector2D ipoint   = wm.ball().inertiaPoint( self_min );

    // If the intercept point is in the opponent half, there's no
    // "behind us" exposure worth worrying about — let the CDM go.
    if ( ipoint.x > 5.0 ) {
        return true;
    }

    // Safe iff we have teammate cover behind, OR no opponent runner
    // is threatening to break into the vacated zone.
    const bool cover = has_cover_behind( wm, self_pos );
    const bool runner = runner_behind( wm, self_pos );

    if ( cover ) {
        return true;
    }
    if ( ! runner ) {
        return true;
    }

    rcsc::dlog.addText( rcsc::Logger::TEAM,
        __FILE__": Phase8 refusing intercept unum=%d self_min=%d "
        "self=(%.1f,%.1f) ipoint=(%.1f,%.1f) no_cover runner_present",
        self_unum, self_min,
        self_pos.x, self_pos.y, ipoint.x, ipoint.y );
    return false;
}

} // namespace cyrus_phase5
