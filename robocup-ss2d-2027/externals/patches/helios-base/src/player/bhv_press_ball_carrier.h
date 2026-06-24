// -*-c++-*-
//
// bhv_press_ball_carrier.h
//
// Phase 4a: press the opponent ball carrier from the goal-side angle.

#ifndef BHV_PRESS_BALL_CARRIER_H
#define BHV_PRESS_BALL_CARRIER_H

#include <rcsc/geom/vector_2d.h>
#include <rcsc/player/soccer_action.h>

class Bhv_PressBallCarrier
    : public rcsc::SoccerBehavior {
private:
    rcsc::Vector2D M_press_point;

public:
    explicit Bhv_PressBallCarrier( const rcsc::Vector2D & press_point )
      : M_press_point( press_point )
    { }

    bool execute( rcsc::PlayerAgent * agent );
};

#endif
