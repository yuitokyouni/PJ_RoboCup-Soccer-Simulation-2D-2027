#include "counter_press_state.h"

#include <rcsc/player/world_model.h>
#include <rcsc/common/logger.h>

namespace cyrus_phase5 {

namespace {
// Counter-press window: 50 cycles after a loss-in-opp-half event.
const int COUNTER_PRESS_WINDOW = 50;
// Aggression multiplier values.
const double NORMAL_MULTIPLIER       = 1.0;
const double COUNTER_PRESS_MULTIPLIER = 1.5;
// Window for "just won in opp half" auxiliary signal.
const int JUST_WON_WINDOW = 10;
} // anonymous namespace

CounterPressState::CounterPressState()
    : M_last_loss_cycle( -1 ),
      M_last_win_cycle( -1 ),
      M_last_loss_in_opp_half( false ),
      M_last_win_in_opp_half( false ),
      M_prev_state_cycle( -1 ),
      M_prev_possession( Possession::Loose )
{
}

CounterPressState &
CounterPressState::instance()
{
    static CounterPressState s_instance;
    return s_instance;
}

void
CounterPressState::update( const rcsc::WorldModel & wm )
{
    const int cycle_now = wm.time().cycle();

    // Guard against double-counting: only register a transition once
    // per cycle.
    if ( M_prev_state_cycle == cycle_now ) {
        return;
    }

    // Determine current possession.
    const bool ours_now = ( wm.kickableTeammate() != 0 )
                          || wm.self().isKickable();
    const bool theirs_now = ( wm.kickableOpponent() != 0 );

    Possession current = Possession::Loose;
    if ( ours_now && ! theirs_now ) {
        current = Possession::Ours;
    } else if ( theirs_now && ! ours_now ) {
        current = Possession::Theirs;
    } else if ( ours_now && theirs_now ) {
        // Contested kickable: treat as loose for transition purposes.
        current = Possession::Loose;
    } else {
        current = Possession::Loose;
    }

    // Detect transitions only when we have a known previous state.
    if ( M_prev_state_cycle >= 0 ) {
        // LOSS event: Ours -> Theirs.
        if ( M_prev_possession == Possession::Ours
             && current == Possession::Theirs )
        {
            // Loss "in opp half" means ball.x > 0 from our POV.
            const bool in_opp_half = ( wm.ball().pos().x > 0.0 );
            M_last_loss_cycle      = cycle_now;
            M_last_loss_in_opp_half = in_opp_half;
            if ( in_opp_half ) {
                rcsc::dlog.addText( rcsc::Logger::TEAM,
                              "[CounterPress] LOST in opp_half at cycle %d",
                              cycle_now );
            } else {
                rcsc::dlog.addText( rcsc::Logger::TEAM,
                              "[CounterPress] LOST in own_half at cycle %d",
                              cycle_now );
            }
        }
        // WIN event: Theirs -> Ours.
        else if ( M_prev_possession == Possession::Theirs
                  && current == Possession::Ours )
        {
            const bool in_opp_half = ( wm.ball().pos().x > 0.0 );
            M_last_win_cycle      = cycle_now;
            M_last_win_in_opp_half = in_opp_half;
            if ( in_opp_half ) {
                rcsc::dlog.addText( rcsc::Logger::TEAM,
                              "[CounterPress] WON in opp_half at cycle %d",
                              cycle_now );
            } else {
                rcsc::dlog.addText( rcsc::Logger::TEAM,
                              "[CounterPress] WON in own_half at cycle %d",
                              cycle_now );
            }
        }
    }

    M_prev_possession  = current;
    M_prev_state_cycle = cycle_now;
}

bool
CounterPressState::counter_press_active( int cycle_now ) const
{
    if ( M_last_loss_cycle < 0 || ! M_last_loss_in_opp_half ) {
        return false;
    }
    const int elapsed = cycle_now - M_last_loss_cycle;
    if ( elapsed < 0 ) {
        // Clock went backwards (kickoff / restart); treat as expired.
        return false;
    }
    return elapsed < COUNTER_PRESS_WINDOW;
}

double
CounterPressState::aggression_multiplier( int cycle_now ) const
{
    return counter_press_active( cycle_now )
           ? COUNTER_PRESS_MULTIPLIER
           : NORMAL_MULTIPLIER;
}

bool
CounterPressState::just_won_in_opp_half( int cycle_now ) const
{
    if ( M_last_win_cycle < 0 || ! M_last_win_in_opp_half ) {
        return false;
    }
    const int elapsed = cycle_now - M_last_win_cycle;
    if ( elapsed < 0 ) {
        return false;
    }
    return elapsed < JUST_WON_WINDOW;
}

} // namespace cyrus_phase5

// Strong overrides for the weak extern hooks declared in chance_signal.cpp.
// chance_signal.cpp declares these at global scope with __attribute__((weak));
// when this TU is also linked into the binary, the strong definitions below
// win and chance_signal can read the real CounterPressState getters.
long counter_press_last_recovery_cycle()
{
    return static_cast<long>(
        cyrus_phase5::CounterPressState::instance().last_win_cycle());
}

bool counter_press_last_recovery_in_opp_half()
{
    return cyrus_phase5::CounterPressState::instance().last_win_in_opp_half();
}
