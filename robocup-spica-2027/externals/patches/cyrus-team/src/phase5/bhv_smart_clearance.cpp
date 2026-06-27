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

// Is any opponent in our own half (x < 0) closer than OPP_BLOCK_RADIUS
// to the segment from ball -> target ?
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
        const rcsc::Vector2D & op = opp->pos();
        if ( op.x >= 0.0 ) continue; // only block opponents in OUR half
        const double d = path.dist( op );
        if ( d < OPP_BLOCK_RADIUS ) {
            return true;
        }
    }
    return false;
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

        // Reject if target lands in forbidden opponent-midfield band.
        if ( in_forbidden_midfield( target ) ) {
            continue;
        }

        // Reject if a closer opponent in our half blocks the kick path.
        if ( path_blocked_by_opponent( wm, ball, target ) ) {
            continue;
        }

        // Accept this candidate: kick toward it.
        const rcsc::AngleDeg dir = ( target - ball ).th();

        Body_KickOneStep( target,
                          CLEARANCE_KICK_SPEED,
                          false ).execute( agent );

        // Trigger team push-up bias for bhv_basic_move.
        TerritoryRecoveryState::instance().trigger( wm.time().cycle() );

        agent->debugClient().addMessage( "SmartClear%.0f", target.x );
        agent->debugClient().setTarget( target );
        (void)dir; // angle currently informational; reserved for future use

        return true;
    }

    // No acceptable target -> caller falls through to Body_AdvanceBall.
    return false;
}

} // namespace cyrus_phase5
