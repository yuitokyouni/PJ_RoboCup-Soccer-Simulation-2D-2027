#ifndef CYRUS_PHASE5_INTERCEPT_DISCIPLINE_H
#define CYRUS_PHASE5_INTERCEPT_DISCIPLINE_H

// Phase 8: position-aware intercept gate for the CDM line.
//
// Vanilla Cyrus's bhv_basic_move.cpp invokes Body_InterceptPlan
// unconditionally whenever the player can reach the ball. For a CDM
// this is structurally unsafe: stepping out to grab a wedge pass at
// its inertia point pulls the CDM out of the central screen, and the
// opposite-side striker runs into the vacated zone (the conceded-goal
// pattern observed in Phase 7 imp-vs-van match-by-match analysis).
//
// This gate returns false for the CDM uniforms (6, 7) when committing
// to intercept would leave the central channel exposed. All other
// uniforms get a passthrough so existing behavior is preserved.

namespace rcsc {
class WorldModel;
}

namespace cyrus_phase5 {

// True iff Body_InterceptPlan should be allowed to execute this cycle.
// Defaults to true for non-CDM uniforms and for CDMs that already have
// shape cover; only refuses when the intercept would leave a free zone
// behind the CDM toward our goal.
bool intercept_safe_for_unum( int self_unum,
                              const rcsc::WorldModel & wm );

} // namespace cyrus_phase5

#endif // CYRUS_PHASE5_INTERCEPT_DISCIPLINE_H
