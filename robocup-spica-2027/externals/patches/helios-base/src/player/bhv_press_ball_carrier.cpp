// -*-c++-*-

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include "bhv_press_ball_carrier.h"

#include "basic_actions/basic_actions.h"
#include "basic_actions/body_go_to_point.h"
#include "basic_actions/body_intercept.h"
#include "basic_actions/neck_turn_to_ball.h"

#include <rcsc/player/player_agent.h>
#include <rcsc/player/world_model.h>
#include <rcsc/player/intercept_table.h>
#include <rcsc/common/logger.h>
#include <rcsc/common/server_param.h>

using namespace rcsc;

bool
Bhv_PressBallCarrier::execute( PlayerAgent * agent )
{
    const WorldModel & wm = agent->world();

    dlog.addText( Logger::TEAM,
                  __FILE__": Bhv_PressBallCarrier point=(%.1f %.1f)",
                  M_press_point.x, M_press_point.y );

    // If the ball is interceptable, just grab it. Otherwise the
    // carrier escapes any moment now.
    const int self_min = wm.interceptTable().selfStep();
    if ( self_min <= 4 )
    {
        Body_Intercept().execute( agent );
        agent->setNeckAction( new Neck_TurnToBall() );
        agent->debugClient().addMessage( "Press:Intercept" );
        return true;
    }

    // Otherwise drive to the press point (goal-side of carrier) at
    // close to full power.
    const double dash_power = ServerParam::i().maxDashPower();
    const double dist_thr = 0.5;

    agent->debugClient().addMessage( "Press%.0f", dash_power );
    agent->debugClient().setTarget( M_press_point );
    agent->debugClient().addCircle( M_press_point, dist_thr );

    if ( ! Body_GoToPoint( M_press_point, dist_thr, dash_power
                           ).execute( agent ) )
    {
        // Already at press point: face the ball.
        Body_TurnToBall().execute( agent );
    }

    agent->setNeckAction( new Neck_TurnToBall() );
    return true;
}
