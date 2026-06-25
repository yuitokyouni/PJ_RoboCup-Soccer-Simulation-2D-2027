#ifndef CYRUS_PHASE5_BHV_SMART_CLEARANCE_H
#define CYRUS_PHASE5_BHV_SMART_CLEARANCE_H

#include <rcsc/player/soccer_action.h>

namespace rcsc {
class PlayerAgent;
}

namespace cyrus_phase5 {

// Phase 5c clearance replacement.
// Returns true from execute() iff a kick was actually issued.
// The caller MUST treat a false return as "fall through to default
// Body_AdvanceBall / Body_ClearBall2009 behavior".
class Bhv_SmartClearance : public rcsc::SoccerBehavior {
public:
    bool execute( rcsc::PlayerAgent * agent );
};

} // namespace cyrus_phase5

#endif // CYRUS_PHASE5_BHV_SMART_CLEARANCE_H
