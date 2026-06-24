// -*-c++-*-
//
// defense_duty.h
//
// Phase 4 extension to helios-base. Assigns each field player a
// per-cycle "defensive duty" (press / cover / none) so the team can
// stop relying on Bhv_BasicMove's universal chase-the-ball heuristic.
//
// Added by: 2026-06-24 robocup-ss2d-2027/scripts session.
// Not part of helios upstream.

#ifndef DEFENSE_DUTY_H
#define DEFENSE_DUTY_H

#include <rcsc/geom/vector_2d.h>

namespace rcsc {
class WorldModel;
class AbstractPlayerObject;
}

class DefenseDuty {
public:
    enum Type {
        NONE,    // no defensive duty; fall through to formation
        PRESS,   // press the ball carrier; close down goal-side
        COVER,   // cover a specific opponent goal-side (mark + cut lane)
    };

    Type type;
    const rcsc::AbstractPlayerObject * target;  // carrier (PRESS) or marked opp (COVER)
    rcsc::Vector2D position;                    // computed press / cover point

    DefenseDuty()
      : type( NONE )
      , target( 0 )
      , position( 0.0, 0.0 )
    { }
};

class DefenseDutyAssigner {
public:
    // Compute MY duty from the world. Each player runs this
    // independently every cycle; the algorithm is deterministic so
    // all 11 players agree on the assignment without explicit
    // communication.
    static DefenseDuty assign( const rcsc::WorldModel & wm );
};

#endif
