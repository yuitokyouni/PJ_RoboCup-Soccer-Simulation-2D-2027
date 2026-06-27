#include "territory_recovery_state.h"

namespace cyrus_phase5 {

TerritoryRecoveryState::TerritoryRecoveryState()
    : M_trigger_cycle( -1 ),
      M_window_cycles( 50 ),
      M_initial_bias( 8.0 ),
      M_minimum_bias( 5.0 )
{
}

TerritoryRecoveryState &
TerritoryRecoveryState::instance()
{
    static TerritoryRecoveryState s_instance;
    return s_instance;
}

void
TerritoryRecoveryState::trigger( int cycle_now )
{
    M_trigger_cycle = cycle_now;
}

bool
TerritoryRecoveryState::active( int cycle_now ) const
{
    if ( M_trigger_cycle < 0 ) {
        return false;
    }
    const int elapsed = cycle_now - M_trigger_cycle;
    if ( elapsed < 0 ) {
        // clock went backwards (kickoff / restart); treat as expired
        return false;
    }
    return elapsed < M_window_cycles;
}

double
TerritoryRecoveryState::forward_bias( int cycle_now ) const
{
    if ( ! active( cycle_now ) ) {
        return 0.0;
    }
    const int elapsed = cycle_now - M_trigger_cycle;
    const double frac_remaining =
        1.0 - ( static_cast< double >( elapsed )
                / static_cast< double >( M_window_cycles ) );
    // Linear decay from M_initial_bias down to M_minimum_bias while active.
    const double span = M_initial_bias - M_minimum_bias;
    double bias = M_minimum_bias + span * frac_remaining;
    if ( bias < M_minimum_bias ) bias = M_minimum_bias;
    if ( bias > M_initial_bias ) bias = M_initial_bias;
    return bias;
}

} // namespace cyrus_phase5
