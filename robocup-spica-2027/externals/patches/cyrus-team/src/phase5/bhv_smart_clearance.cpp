#include "bhv_smart_clearance.h"
#include "territory_recovery_state.h"

#include <rcsc/player/player_agent.h>
#include <rcsc/player/world_model.h>
#include <rcsc/player/debug_client.h>
#include "../basic_actions/basic_actions.h"
#include "../basic_actions/body_kick_one_step.h"
#include "../basic_actions/body_advance_ball.h"
#include <rcsc/common/server_param.h>
#include <rcsc/geom/vector_2d.h>
#include <rcsc/geom/segment_2d.h>
#include <rcsc/geom/line_2d.h>
#include <rcsc/math_util.h>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace rcsc;

namespace cyrus_phase5 {

namespace {

// Forbidden midfield band: 10 < x < 25 .
const double FORBIDDEN_X_MIN = 10.0;
const double FORBIDDEN_X_MAX = 25.0;

// Path-clearance threshold against opponents who sit in our half.
const double OPP_BLOCK_RADIUS = 1.5;

// Suggested first-step kick speed for clearance.
const double CLEARANCE_KICK_SPEED = 2.7;

inline double signof_y( double y )
{
    if ( y > 0.0 ) return  1.0;
    if ( y < 0.0 ) return -1.0;
    return 1.0; // arbitrary tie-break
}

// Returns true if target lands in the forbidden opponent-midfield band.
inline bool in_forbidden_midfield( const rcsc::Vector2D & t )
{
    return ( t.x > FORBIDDEN_X_MIN && t.x < FORBIDDEN_X_MAX );
}

// Is any opponent closer than OPP_BLOCK_RADIUS to the segment from
// ball -> predicted resting point?
//
// AUDIT S3c fix (docs/REPO_AUDIT_2026-07.md): the old check skipped
// every opponent at x >= 0, so when the ball was near midfield no
// opponent could ever reject a candidate.
bool path_blocked_by_opponent( const rcsc::WorldModel & wm,
                               const rcsc::Vector2D & ball,
                               const rcsc::Vector2D & target )
{
    const rcsc::Segment2D path( ball, target );
    const rcsc::PlayerObject::Cont::const_iterator end = wm.opponentsFromSelf().end();
    for ( rcsc::PlayerObject::Cont::const_iterator it = wm.opponentsFromSelf().begin();
          it != end;
          ++it )
    {
        const rcsc::AbstractPlayerObject * opp = *it;
        if ( ! opp ) continue;
        const double d = path.dist( opp->pos() );
        if ( d < OPP_BLOCK_RADIUS ) {
            return true;
        }
    }
    return false;
}

// AUDIT S3d fix: predicted resting point of a one-step kick. A ball
// kicked at speed v with decay d rolls a total of v / (1 - d) meters.
// The old code compared the forbidden midfield band against TARGET
// coordinates (x=45 / x=28 — provably never inside 10<x<25) while the
// real ball routinely died inside the band.
rcsc::Vector2D predicted_resting_point( const rcsc::Vector2D & ball,
                                        const rcsc::Vector2D & target,
                                        double kick_speed )
{
    const double decay = rcsc::ServerParam::i().ballDecay();
    const double travel = kick_speed / std::max( 1.0e-6, 1.0 - decay );
    rcsc::Vector2D dir = target - ball;
    const double dist_to_target = dir.r();
    if ( dist_to_target < 1.0e-6 ) return ball;
    dir /= dist_to_target;
    return ball + dir * std::min( travel, dist_to_target + 100.0 );
}

} // anonymous namespace

bool
Bhv_SmartClearance::execute( rcsc::PlayerAgent * agent )
{
    if ( ! agent ) return false;

    const rcsc::WorldModel & wm = agent->world();

    if ( ! wm.self().isKickable() ) {
        return false;
    }

    const rcsc::Vector2D ball = wm.ball().pos();

    // AUDIT S3c fix: clearance is a DEFENSIVE action. This behavior is
    // injected at the top of hold_ball, which chain_action also reaches
    // as the fallback for failed shots/passes in the ATTACKING third —
    // where poking the ball toward the corner is a voluntary turnover.
    // Only clear when the ball is genuinely in our defensive zone.
    if ( ball.x > -10.0 ) {
        return false;
    }

    const double sy = signof_y( ball.y );

    // Candidate targets in priority order:
    //  (1) same-side opponent corner (x >= 30, |y| >= 24)
    //  (2) past opponent CB region   (x >= 25, |y| <  24)
    //  (3) opposite-side opponent corner (fallback within accepted zones)
    std::vector< rcsc::Vector2D > candidates;
    candidates.reserve( 3 );
    candidates.push_back( rcsc::Vector2D( 45.0,  sy * 30.0 ) );
    candidates.push_back( rcsc::Vector2D( 28.0,  sy * 14.0 ) );
    candidates.push_back( rcsc::Vector2D( 45.0, -sy * 30.0 ) );

    for ( std::size_t i = 0; i < candidates.size(); ++i ) {
        const rcsc::Vector2D & target = candidates[ i ];

        // AUDIT S3d fix: judge the forbidden band against where the
        // ball will actually STOP, not the (unreachable) target. A
        // 2.7 m/s one-step kick from our half dies around x ≈ +16 —
        // inside the band — when aimed at the far corner.
        const rcsc::Vector2D rest =
            predicted_resting_point( ball, target, CLEARANCE_KICK_SPEED );
        if ( in_forbidden_midfield( rest ) ) {
            continue;
        }

        // Reject if an opponent blocks the kick path.
        if ( path_blocked_by_opponent( wm, ball, target ) ) {
            continue;
        }

        // Accept this candidate: kick toward it.
        // AUDIT S3 fix: check the kick actually executed. With
        // force_mode=false Body_KickOneStep silently degrades to
        // HoldBall/StopBall when the kick is infeasible — in that case
        // the clearance did NOT happen: report failure so the caller's
        // fallback runs, and do NOT trigger the push-up bias.
        if ( ! Body_KickOneStep( target,
                                 CLEARANCE_KICK_SPEED,
                                 false ).execute( agent ) ) {
            continue;
        }

        // Trigger team push-up bias for bhv_basic_move.
        TerritoryRecoveryState::instance().trigger( wm.time().cycle() );

        agent->debugClient().addMessage( "SmartClear%.0f", target.x );
        agent->debugClient().setTarget( target );

        return true;
    }

    // No acceptable target -> caller falls through to Body_AdvanceBall.
    return false;
}

} // namespace cyrus_phase5
