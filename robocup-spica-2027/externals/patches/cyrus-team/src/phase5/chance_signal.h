// -*-c++-*-
#ifndef CYRUS_PHASE5_CHANCE_SIGNAL_H
#define CYRUS_PHASE5_CHANCE_SIGNAL_H

namespace rcsc {
class WorldModel;
}

namespace cyrus_phase5 {

// Returns a scalar in [0,1] describing how good the current attacking
// moment is. Used by chain_action to bias forward/shoot bonuses up and
// hold/lateral bonuses down.
double compute_chance_signal( const rcsc::WorldModel & wm );

} // namespace cyrus_phase5

#endif // CYRUS_PHASE5_CHANCE_SIGNAL_H
