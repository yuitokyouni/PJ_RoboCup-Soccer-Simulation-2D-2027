// -*-c++-*-
//
// bhv_cover_goal_side.h
//
// Phase 4c / 4b-overlap: stay on the goal-side of a specific opponent.

#ifndef BHV_COVER_GOAL_SIDE_H
#define BHV_COVER_GOAL_SIDE_H

#include <rcsc/geom/vector_2d.h>
#include <rcsc/player/soccer_action.h>

namespace rcsc {
class AbstractPlayerObject;
}

class Bhv_CoverGoalSide
    : public rcsc::SoccerBehavior {
private:
    rcsc::Vector2D M_cover_point;
    const rcsc::AbstractPlayerObject * M_mark;  // may be 0 if mark vanished

public:
    Bhv_CoverGoalSide( const rcsc::Vector2D & cover_point,
                       const rcsc::AbstractPlayerObject * mark )
      : M_cover_point( cover_point )
      , M_mark( mark )
    { }

    bool execute( rcsc::PlayerAgent * agent );
};

#endif
