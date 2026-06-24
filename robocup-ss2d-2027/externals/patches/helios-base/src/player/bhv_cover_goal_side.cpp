// -*-c++-*-

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include "bhv_cover_goal_side.h"

#include "basic_actions/basic_actions.h"
#include "basic_actions/body_go_to_point.h"
#include "basic_actions/neck_turn_to_ball_or_scan.h"

#include <rcsc/player/player_agent.h>
#include <rcsc/player/world_model.h>
#include <rcsc/common/logger.h>
#include <rcsc/common/server_param.h>

using namespace rcsc;

bool
Bhv_CoverGoalSide::execute( PlayerAgent * agent )
{
    dlog.addText( Logger::TEAM,
                  __FILE__": Bhv_CoverGoalSide point=(%.1f %.1f)",
                  M_cover_point.x, M_cover_point.y );

    // Slightly below max power: covers don't need to sprint flat-out
    // and lose stamina on every cycle. 85% gives them recovery room.
    const double dash_power = ServerParam::i().maxDashPower() * 0.85;
    const double dist_thr = 0.8;

    agent->debugClient().addMessage( "Cover%.0f", dash_power );
    agent->debugClient().setTarget( M_cover_point );
    agent->debugClient().addCircle( M_cover_point, dist_thr );

    if ( ! Body_GoToPoint( M_cover_point, dist_thr, dash_power
                           ).execute( agent ) )
    {
        // Already at cover point: face the ball so we can react.
        Body_TurnToBall().execute( agent );
    }

    // Scan to keep both ball and the marked opponent in view.
    agent->setNeckAction( new Neck_TurnToBallOrScan( 0 ) );
    return true;
}
