// Phase 5e (v2 2026-06-25): dynamic shape transition on F433.
//
// User insight: F433 / F523 / F325 are the same SHAPE if you let the
// roles transition between phases. Instead of swapping formation .conf
// files, we keep F433 and rewrite this modulator so that:
//
//   ATTACK PHASE  (we have the ball or ball is in opp half)
//     - SB unum 3 / 4 push UP to be wing-backs:
//         their target.x lifts toward the half-way line, making the
//         live shape effectively 2-2-5 / 3-2-5 (the 2 CDMs at #5/#6
//         already drop between the CBs when out of possession).
//     - Forwards keep their high formation positions.
//
//   DEFENSE PHASE  (opp has ball in our half / midline)
//     - SB unum 3 / 4 drop DOWN to form a 5-back:
//         their target.x caps at the CB line, so the shape becomes
//         5-2-3 (matches the user's tactical reference image).
//     - Forwards drop to midline so we don't get stretched.
//     - Lateral compression toward ball side, flexible amount based on
//         ball.x and opp density (matches "横シフトの寄せ範囲は柔軟に"
//         from the spec).
//
// The forward push-up + back drop-down both happen on the SAME unums,
// so transitions are seamless inside a single formation file.

#include "defense_block.h"

#include <rcsc/player/world_model.h>
#include <rcsc/player/player_object.h>
#include <rcsc/common/logger.h>

#include <algorithm>
#include <cmath>
#include <cstdio>

#if defined(CYRUS_PHASE5_TERRITORY_RECOVERY) && CYRUS_PHASE5_TERRITORY_RECOVERY
#  include "territory_recovery_state.h"
#endif

namespace cyrus_phase5 {

namespace {

inline double clamp_d( double v, double lo, double hi ) {
    if ( v < lo ) return lo;
    if ( v > hi ) return hi;
    return v;
}

int count_opp_near_ball( const rcsc::WorldModel & wm, double radius ) {
    const rcsc::Vector2D ball_pos = wm.ball().pos();
    int n = 0;
    const rcsc::PlayerObject::Cont & opps = wm.opponents();
    for ( rcsc::PlayerObject::Cont::const_iterator it = opps.begin();
          it != opps.end(); ++it ) {
        if ( *it == 0 ) continue;
        if ( (*it)->posCount() > 10 ) continue;
        if ( (*it)->pos().dist( ball_pos ) <= radius ) {
            ++n;
        }
    }
    return n;
}

} // namespace

// In F433 the side-back unums are 3 (LB) and 4 (RB). These are the
// players who become "wing-backs" in the attacking phase and "5-back
// outsides" in the defensive phase. Both behaviors live in this file.
bool is_wing_back( int self_unum ) {
    return ( self_unum == 3 || self_unum == 4 );
}

// In F433 the holding CDMs are 5 and 6 (pp_ch). When we're building
// up, ONE CDM drops between the CBs — Pep-style "midfielder dropping
// to form a back-3" so we can push one SB high without exposing the
// back line.
//
// Phase 6 (2026-06-25): symmetric CDM drop based on attack side.
//   left attack  (ball.y < -3) -> unum 6 drops (mirrors LB push)
//   right attack (ball.y > +3) -> unum 7 drops (mirrors RB push)
//   center        -> unum 6 drops (same default as the SB picker)
// This guarantees the dropping CDM is on the SAME side as the
// pushing SB, so the back-3 forms as: stay-side SB + remaining CBs
// + dropping CDM, all on the side away from the attack.
static bool is_build_up_drop_cdm( int self_unum, const rcsc::WorldModel & wm ) {
    const double by = wm.ball().pos().y;
    if ( by > 3.0 ) return ( self_unum == 7 );  // right attack
    // ball.y <= 3.0 (left or center) -> unum 6 drops
    return ( self_unum == 6 );
}

// Phase 6 false-9 detection: in build-up phase (ball still in our
// half), the centre forward drops into the half-space behind the
// SF/RF line so a wedge pass from the WB has a receiver between the
// opp DM line and the opp CB line.
static bool is_false_nine( int self_unum ) {
    return ( self_unum == 11 );  // CF in F433
}

// Decide which SB pushes high this cycle. The user's spec: only ONE
// SB at a time becomes a wing-back; the other SB stays at the back
// line and forms part of the 3-back / 4-back. The side with the ball
// picks the wing-back.
//   ball.y < -3  -> left attack -> unum 3 (LB) pushes; unum 4 stays.
//   ball.y > +3  -> right attack -> unum 4 (RB) pushes; unum 3 stays.
//   ball.y in [-3,3] -> hysteresis: pick the side where we have more
//   attackers ahead of the ball, fall back to LB if symmetric.
static bool should_this_sb_push( int self_unum, const rcsc::WorldModel & wm ) {
    const double by = wm.ball().pos().y;
    // (Phase 6.1 center-skip reverted: n=20 showed regression to
    //  +0.55 vanilla. The center channel default-push back to LB.)
    if ( by < -3.0 ) return ( self_unum == 3 );
    if ( by >  3.0 ) return ( self_unum == 4 );
    return ( self_unum == 3 );  // center channel -> LB push by default
}

// Forwards in F433 are 9 / 10 / 11. In defense they drop to support
// the midfield two; in attack they keep their formation x.
static bool is_forward_unum( int self_unum ) {
    return ( self_unum == 9 || self_unum == 10 || self_unum == 11 );
}

double lateral_shift_amount( const rcsc::WorldModel & wm ) {
    const rcsc::Vector2D ball_pos = wm.ball().pos();

    // Base shift: more compression deeper in our half, less near the
    // midline. ball.x interpolated linearly between -45..+10.
    const double bx = clamp_d( ball_pos.x, -45.0, 10.0 );
    const double base = 4.0 + ( -bx + 10.0 ) * (8.0 - 4.0) / (10.0 - (-45.0));
    //                                            ^ base goes 4 -> 8 as ball moves from +10 to -45

    // Density modifier: more bodies near the ball, larger compression.
    const int num_opp_near_ball = count_opp_near_ball( wm, 10.0 );
    double density_mod = 1.0 + 0.15 * ( num_opp_near_ball - 2 );
    density_mod = clamp_d( density_mod, 0.7, 1.4 );

    return base * density_mod;
}

double vertical_compression( const rcsc::WorldModel & wm ) {
    return wm.ball().pos().x - 2.0;
}

// True if our team actually has the ball. We deliberately do NOT
// classify loose balls in opp half as "attack": that previously
// caused SBs to over-push and leak counter-attacks. With this
// stricter definition, SBs only abandon the back line when we
// genuinely control possession.
static bool in_attack_phase( const rcsc::WorldModel & wm ) {
    if ( wm.self().isKickable() ) return true;
    if ( wm.kickableTeammate() != 0 ) return true;
    return false;
}

rcsc::Vector2D modulate_position(
    const rcsc::WorldModel & wm,
    int self_unum,
    const rcsc::Vector2D & raw_target )
{
    const rcsc::Vector2D ball_pos = wm.ball().pos();

    double shifted_x = raw_target.x;
    double shifted_y = raw_target.y;

    const bool attacking = in_attack_phase( wm );

    if ( attacking ) {
        // -- ATTACK PHASE -----------------------------------------------
        // User-specified shape (Pep / Nuno-Mendes diagonal-wedge
        // pattern). ONE SB pushes high to be the wing-attacker; the
        // OTHER SB stays at the back line. One CDM (unum 6) drops
        // between the CBs to form a 3-back during build-up.
        if ( is_wing_back( self_unum ) ) {
            if ( should_this_sb_push( self_unum, wm ) ) {
                const double target_min_x = std::max( -5.0, ball_pos.x - 5.0 );
                if ( shifted_x < target_min_x ) {
                    shifted_x = target_min_x;
                }
                // Push width kept at ±22 per user direction.
                const double width_target = ( self_unum == 3 ) ? -22.0 : 22.0;
                if ( ( self_unum == 3 && shifted_y > -15.0 )
                     || ( self_unum == 4 && shifted_y <  15.0 ) ) {
                    shifted_y = width_target;
                }
            } else {
                // Stay-back SB: tuck inside to support the 3-back.
                shifted_x = std::min( shifted_x, -18.0 );
                const double y_inside = ( self_unum == 3 ) ? -8.0 : 8.0;
                if ( self_unum == 3 && shifted_y < y_inside ) shifted_y = y_inside;
                if ( self_unum == 4 && shifted_y > y_inside ) shifted_y = y_inside;
            }
        }
        // CDM CB-ization (Phase 6 symmetric): drop the same-side CDM
        // so the resulting 3-back is on the opposite flank from the
        // pushing SB.
        if ( is_build_up_drop_cdm( self_unum, wm ) ) {
            if ( ball_pos.x < 10.0 ) {
                shifted_x = std::min( shifted_x, -20.0 );
                // Side-aware y: place the dropping CDM on the side
                // OPPOSITE to the pushing SB so it covers the gap.
                const double by = ball_pos.y;
                const double cdm_y = ( by > 3.0 ) ? -4.0   // right attack -> CDM left of centre
                                  : ( by < -3.0 ) ? 4.0    // left attack -> CDM right of centre
                                  : 0.0;                   // center
                shifted_y = cdm_y;
            }
        }
        // iter 2 CF push reverted -- iter_003 showed possession
        // collapse (opp_half 373 vs iter_002's 814) and 8 dangerous
        // SPs (vs 1). The CF target was outside formation context,
        // ChainAction pass selection couldn't reach him.
        // PHASE9 OFF (2026-06-26): Phase 7 false-9 pocket run pulled
        // CF unum 11 wide (y = ±12), away from the central scoring
        // zone. With the apply_phase5.sh step 9 switch to "Formation":
        // "433" (Phase 9), the CF is a true centre-forward; the pocket
        // run was designed for the F325 hybrid where unum 11 was an
        // outside wing-forward. In n=20 balanced eval, leaving Phase 7
        // on under F433 made Spica score 0 / 20; turning it off let
        // Spica score (1 win + draws) at the best stable -0.75 vs
        // -0.95 with Phase 7 still on. Disabled pending an F325-conf
        // retune via Cyrus's FormationEditor.
        // if ( is_false_nine( self_unum )
        //      && ball_pos.x >= -25.0
        //      && std::abs( ball_pos.y ) > 3.0 ) {
        //     const double by = ball_pos.y;
        //     const double pocket_y = ( by > 3.0 ) ?  12.0
        //                           :               -12.0;
        //     const double pocket_x = clamp_d( ball_pos.x + 25.0, 15.0, 38.0 );
        //     if ( pocket_x > shifted_x ) shifted_x = pocket_x;
        //     shifted_y = pocket_y;
        // }
        // Forwards (SF / RF — unum 9 / 10): keep raw formation target.
    } else {
        // -- DEFENSE PHASE -------------------------------------------
        // Skip very deep opp-half attacks (we're already chasing).
        if ( ball_pos.x > 15.0 ) {
            return raw_target;
        }

        // step 1: lateral shift toward ball-side (flexible amount).
        const double shift = lateral_shift_amount( wm );
        if ( ball_pos.y > raw_target.y ) {
            shifted_y = raw_target.y + shift;
            shifted_y = std::min( shifted_y, ball_pos.y );
        } else {
            shifted_y = raw_target.y - shift;
            shifted_y = std::max( shifted_y, ball_pos.y );
        }
        shifted_y = clamp_d( shifted_y, -32.0, 32.0 );

        // step 2: forwards drop to midline (so the block stays compact
        // and the midfield two aren't outnumbered).
        if ( is_forward_unum( self_unum ) ) {
            // Keep forwards as outlets. Stay near the midline unless
            // ball is very deep in our half.
            const double cap = std::max( 0.0, ball_pos.x + 10.0 );
            shifted_x = std::min( shifted_x, cap );
        }

        // step 3: SBs drop to form a 5-back. THE KEY transition.
        if ( is_wing_back( self_unum ) ) {
            if ( ball_pos.x < -10.0 ) {
                // deep in our half: pin to the back line ( ~ -22 )
                shifted_x = std::min( shifted_x, -22.0 );
            } else {
                // ball near midline: half retreat
                shifted_x = std::min( shifted_x, -14.0 );
            }

            // PSG-loop iter 7: CB Y-mirror enforcement.
            // iter_005 and iter_006 both conceded with CB pair (u2,
            // u5) BOTH on the +y side, leaving -y uncovered. The
            // Y-symmetrized formation often leaves both CBs near
            // their "center" formation slot when ball is at +y,
            // because each CB independently tracks the ball without
            // splitting. PSG-style: the FAR CB stays goalside on
            // the opposite Y to cover late runners.
            // (Currently inside the is_wing_back block; logically
            // separate -- moved below.)
            //
            // Observed iter_000 issue (notes/2026-06-27_psg_loop.md):
            // SPICA0-1V conceded goal at cyc 5618 had u4 stranded at
            // y=+22.9 with the ball at y=-2.3 -- the RB was on the
            // wrong side of the pitch entirely. Same pattern across
            // multiple Phase 9c REV concessions.
            //
            // Cap to |y| <= 12 when ball is in our own PA-edge zone
            // (x < -30). This still leaves the SB wider than the CB
            // pair (|y| ~ 5) so the back four covers the box width,
            // but not as wide as the touchline (|y| ~ 22) where the
            // SB cannot help with central runners.
            if ( ball_pos.x < -30.0 ) {
                if ( shifted_y >  12.0 ) shifted_y =  12.0;
                if ( shifted_y < -12.0 ) shifted_y = -12.0;
            }
        }

        // PSG-loop iter 7: CB Y-mirror enforcement (u5 = LCB).
        // Only fires when ball is deep in our half (x < -30) AND on
        // a clear side (|y| > 5). The FAR CB stays on the opposite
        // side to cover the back-post runner; the NEAR CB (u2)
        // tracks the ball naturally via the existing lateral shift.
        //
        // This is the conservative subset of Phase 9d.1 #3 -- only
        // u5, only deep+wide ball, only adjusting y not x.
        if ( self_unum == 5
             && ball_pos.x < -30.0
             && std::fabs( ball_pos.y ) > 5.0 ) {
            const double cover_y = ( ball_pos.y > 0.0 ) ? -5.0 : 5.0;
            shifted_y = cover_y;
        }
    }

    // step 4: territory recovery bias (push everyone up briefly after
    // a smart clearance).
#if defined(CYRUS_PHASE5_TERRITORY_RECOVERY) && CYRUS_PHASE5_TERRITORY_RECOVERY
    {
        const int cycle_now = wm.time().cycle();
        const TerritoryRecoveryState & trs = TerritoryRecoveryState::instance();
        if ( trs.active( cycle_now ) ) {
            shifted_x += trs.forward_bias( cycle_now );
        }
    }
#endif

    // dlog only when modulation actually occurred.
    const double dx = shifted_x - raw_target.x;
    const double dy = shifted_y - raw_target.y;
    if ( std::fabs( dx ) > 1.0e-3 || std::fabs( dy ) > 1.0e-3 ) {
        rcsc::dlog.addText( rcsc::Logger::TEAM,
                            "[DefBlock] unum=%d phase=%s shift=(%.1f,%.1f)",
                            self_unum,
                            attacking ? "ATK" : "DEF",
                            dx, dy );
    }

    return rcsc::Vector2D( shifted_x, shifted_y );
}

} // namespace cyrus_phase5
