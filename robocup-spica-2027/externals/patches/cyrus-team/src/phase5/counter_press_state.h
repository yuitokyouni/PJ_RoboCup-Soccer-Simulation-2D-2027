#ifndef CYRUS_PHASE5_COUNTER_PRESS_STATE_H
#define CYRUS_PHASE5_COUNTER_PRESS_STATE_H

namespace rcsc {
class WorldModel;
}

namespace cyrus_phase5 {

class CounterPressState {
public:
    static CounterPressState & instance();

    // Called once per cycle by some player (we wire this into
    // bhv_basic_move). Detects possession changes by comparing
    // wm.kickableTeammate() / wm.kickableOpponent() with the
    // previous cycle.
    void update( const rcsc::WorldModel & wm );

    // True when the team is in counter-press mode (just lost
    // ball in opp half within last N cycles).
    bool counter_press_active( int cycle_now ) const;

    // 1.0 normally, 1.5 during counter-press (multiplies mark
    // pursuit distance and dash power).
    double aggression_multiplier( int cycle_now ) const;

    // Aux: useful for chance_signal "we just won it" bonus.
    bool just_won_in_opp_half( int cycle_now ) const;
    int  last_loss_cycle() const { return M_last_loss_cycle; }
    int  last_win_cycle() const { return M_last_win_cycle; }
    bool last_win_in_opp_half() const { return M_last_win_in_opp_half; }

private:
    CounterPressState();
    CounterPressState( const CounterPressState & );
    CounterPressState & operator=( const CounterPressState & );

    enum class Possession { Ours, Theirs, Loose };

    int        M_last_loss_cycle;        // cycle we last lost possession
    int        M_last_win_cycle;         // cycle we last won possession
    bool       M_last_loss_in_opp_half;
    bool       M_last_win_in_opp_half;
    int        M_prev_state_cycle;       // for update() bookkeeping
    Possession M_prev_possession;
};

} // namespace cyrus_phase5

#endif // CYRUS_PHASE5_COUNTER_PRESS_STATE_H
