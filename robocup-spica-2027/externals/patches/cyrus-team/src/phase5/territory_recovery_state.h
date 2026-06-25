#ifndef CYRUS_PHASE5_TERRITORY_RECOVERY_STATE_H
#define CYRUS_PHASE5_TERRITORY_RECOVERY_STATE_H

namespace cyrus_phase5 {

class TerritoryRecoveryState {
public:
    static TerritoryRecoveryState & instance();

    // Trigger forward push-up bias starting at the given cycle.
    void trigger( int cycle_now );

    // True when the bias window is still open at cycle_now.
    bool active( int cycle_now ) const;

    // Bias in meters (5-8m), decays linearly to 0 over the active window.
    // Returns 0.0 when not active.
    double forward_bias( int cycle_now ) const;

private:
    TerritoryRecoveryState();
    TerritoryRecoveryState( const TerritoryRecoveryState & );
    TerritoryRecoveryState & operator=( const TerritoryRecoveryState & );

    int    M_trigger_cycle;   // cycle at which trigger() was called; -1 if never
    int    M_window_cycles;   // total cycles the bias persists (~50)
    double M_initial_bias;    // starting bias in meters (8.0)
    double M_minimum_bias;    // floor while active (5.0)
};

} // namespace cyrus_phase5

#endif // CYRUS_PHASE5_TERRITORY_RECOVERY_STATE_H
