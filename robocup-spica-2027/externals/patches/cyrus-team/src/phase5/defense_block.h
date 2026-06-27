#ifndef CYRUS_PHASE5_DEFENSE_BLOCK_H
#define CYRUS_PHASE5_DEFENSE_BLOCK_H

#include <rcsc/geom/vector_2d.h>

namespace rcsc {
class WorldModel;
}

namespace cyrus_phase5 {

// Return the modulated target. Falls back to identity if no
// modulation applies (e.g., we have the ball, a teammate is
// kickable, or the ball is deep in the opponent half).
rcsc::Vector2D modulate_position(
    const rcsc::WorldModel & wm,
    int self_unum,
    const rcsc::Vector2D & raw_target );

// Helpers (exposed so tests / dlog can probe them).

// Lateral shift magnitude, blending the ball-position base value
// with the local opponent-density multiplier.
double lateral_shift_amount( const rcsc::WorldModel & wm );

// Vertical compression cap (placeholder helper; the actual cap is
// applied inside modulate_position based on ball.x).
double vertical_compression( const rcsc::WorldModel & wm );

// True if the given unum is a wing-back. In 3-2-5 these are
// uniform numbers 5 (left WB) and 8 (right WB). If the offense
// formation conf indicates different numbers later, adjust here.
bool is_wing_back( int self_unum );

} // namespace cyrus_phase5

#endif // CYRUS_PHASE5_DEFENSE_BLOCK_H
