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
#include <rcsc/common/server_param.h>
#include <rcsc/game_mode.h>

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

// Phase 9d: defensive set piece detection + post-SP persistence.
//
// All 6 conceded goals over the Phase 9c tournament came from
// opponent set pieces (corner / kick-in / free kick / indirect FK)
// AND in the DEF-C (own central) zone. The conceded-goal preambles
// show the team's defensive shape is incorrect right at and just
// after a set piece against us. Phase 9d encodes:
//
//   - is_their_set_piece: rcssserver play modes for opp-initiated SP.
//   - is_dangerous_sp:    the SP is within 25m of our goal (ball
//                         deep in our half).
//   - post_sp_active:     a 30-cycle window after the SP concluded
//                         (referee resumes play_on) during which the
//                         block stays compact (mitigates the
//                         "foul -> FK -> play -> foul -> FK -> goal"
//                         chain we saw in Phase 9c).
//
// is_their_set_piece keys off rcssserver's GameMode codes via
// gameMode().type() rather than the play-mode string so it's
// resilient to v18/v19 string changes. We invert by ourSide().
static bool is_their_set_piece( const rcsc::WorldModel & wm ) {
    using namespace rcsc;
    const GameMode & gm = wm.gameMode();
    const GameMode::Type t = gm.type();
    const SideID our = wm.ourSide();
    // PlayOn is not a set piece. BeforeKickOff/AfterGoal_ handled
    // separately by the kickoff formation set, so we treat them as
    // not "dangerous" from a deep-block standpoint.
    if ( t == GameMode::PlayOn ) return false;
    if ( t == GameMode::BeforeKickOff || t == GameMode::AfterGoal_ ) return false;
    if ( t == GameMode::TimeOver ) return false;
    // KickIn / FreeKick / CornerKick / IndFreeKick / GoalKick / KickOff
    // all carry the awarded-to side in gm.side(). If the awarded side
    // is the opponent, it's a defensive SP.
    if ( gm.side() != NEUTRAL && gm.side() != our ) {
        return true;
    }
    return false;
}

static double our_goal_x( const rcsc::WorldModel & /*wm*/ ) {
    // librcsc's coordinate convention from the WorldModel: positions
    // are in the "our team attacks +x" frame irrespective of the
    // actual rcssserver side. So our goal sits at x = -half-pitch.
    return -rcsc::ServerParam::i().pitchHalfLength();
}

// Returns true if the current set piece is within 25m of our own goal
// AND it's a set piece against us. Used to drive the heavy
// shape override that addresses Phase 9c conceded goals.
static bool is_dangerous_sp( const rcsc::WorldModel & wm ) {
    if ( ! is_their_set_piece( wm ) ) return false;
    const double dist_to_goal = std::abs( wm.ball().pos().x - our_goal_x( wm ) );
    return dist_to_goal < 25.0;
}

// Phase 9d.6: post-set-piece concentration window.
// A simple file-scope state. Caller is one player; each match starts
// a fresh process. Coarser than CounterPressState because we only
// need a "since" cycle.
namespace {
    int g_last_dangerous_sp_cycle = -1;
}

static void tick_post_sp_state( const rcsc::WorldModel & wm ) {
    if ( is_dangerous_sp( wm ) ) {
        g_last_dangerous_sp_cycle = wm.time().cycle();
    }
}

static bool post_sp_active( const rcsc::WorldModel & wm ) {
    if ( g_last_dangerous_sp_cycle < 0 ) return false;
    const int dc = wm.time().cycle() - g_last_dangerous_sp_cycle;
    return ( dc >= 0 && dc <= 30 );
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

    // Phase 9d: tick the dangerous-SP timestamp so post_sp_active()
    // reads up-to-date state for downstream decisions.
    tick_post_sp_state( wm );

    const bool attacking = in_attack_phase( wm );

    // Phase 9d.set-piece: hard overrides for opponent set pieces
    // inside our defensive third. These dominate the attack/defense
    // branches below because the formation conf positions for set
    // piece play do not place CBs / WBs near enough to the ball.
    //
    // Addresses tournament conceded-goal analysis (Phase 9c):
    //   #2: WB/SB unum 3, 4 drop into PA (saw u4 at y=+14..+20 on
    //       Phase 9c goals G1/G3/G4/G5).
    //   #3: CB unum 2 / 5 Y-axis split (both were +y on G1/G3 leaving
    //       -y exposed for the runner).
    //   #5: defenders' x clamped to <= ball.x + 3 so we can't get
    //       caught higher than the ball (G4/G5 line was -34 with ball
    //       at -43).
    //   #6: keep the same compact shape for 30 cycles after the SP
    //       ends to mitigate the foul -> FK -> play -> foul -> FK ->
    //       goal chain that produced G3 / G5.
    if ( is_dangerous_sp( wm ) || post_sp_active( wm ) ) {
        const double goal_x = our_goal_x( wm );
        // Reference depth: 6m in front of own goal during a SP, 4m
        // during the post-SP window.
        const bool live_sp = is_dangerous_sp( wm );
        const double ref_x = goal_x + ( live_sp ? 6.0 : 8.0 );
        // SP-#3: CB pair Y-split. The closer CB (paired side to ball)
        // tracks ball.y; the other CB covers the opposite side.
        if ( self_unum == 2 || self_unum == 5 ) {
            const double by = ball_pos.y;
            // Y split: u2 takes the side AWAY from the ball, u5 the
            // ball side (the closer marker). This guarantees one CB
            // per Y half so no runner is uncontested.
            const double away_y =  ( by >= 0.0 ) ? -5.0 :  5.0;
            const double near_y =  ( by >= 0.0 ) ?  5.0 : -5.0;
            shifted_y = ( self_unum == 2 ) ? away_y : near_y;
            shifted_x = ref_x;
            // Skip the rest of the modulator; the SP override is
            // authoritative for these unums.
            rcsc::dlog.addText( rcsc::Logger::TEAM,
                                "[DefBlock SP] CB-split u%d x=%.1f y=%.1f live=%d",
                                self_unum, shifted_x, shifted_y, live_sp ? 1 : 0 );
            return rcsc::Vector2D( shifted_x, shifted_y );
        }
        // SP-#2: WB/SB drop into the box edge. Wide so they cover the
        // far post on a cross, but inside enough to mark a runner.
        if ( self_unum == 3 || self_unum == 4 ) {
            const double y_target = ( self_unum == 3 ) ? -10.0 : 10.0;
            shifted_x = ref_x + 1.0;
            shifted_y = y_target;
            rcsc::dlog.addText( rcsc::Logger::TEAM,
                                "[DefBlock SP] WB-drop u%d x=%.1f y=%.1f live=%d",
                                self_unum, shifted_x, shifted_y, live_sp ? 1 : 0 );
            return rcsc::Vector2D( shifted_x, shifted_y );
        }
        // SP-#5: defenders' x cap relative to ball.x. The "defenders"
        // here are unums 6, 7 (CDMs). We don't want them ahead of the
        // ball during a SP against us.
        if ( self_unum == 6 || self_unum == 7 ) {
            const double cap_x = ball_pos.x + 3.0;
            if ( shifted_x > cap_x ) shifted_x = cap_x;
            // Also pull the CDMs inside (Y closer to the centre line)
            // so they form the screen layer in front of the back four.
            shifted_y = clamp_d( shifted_y, -8.0, 8.0 );
            rcsc::dlog.addText( rcsc::Logger::TEAM,
                                "[DefBlock SP] CDM-cap u%d x=%.1f y=%.1f",
                                self_unum, shifted_x, shifted_y );
            return rcsc::Vector2D( shifted_x, shifted_y );
        }
        // For other unums (forwards 9/10/11, goalie 1): leave the
        // existing modulator behavior. Forwards should still drop
        // toward the midline (handled by is_forward_unum block below).
    }

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
        }

        // Phase 9d.5: defensive line height cap vs ball.x. From the
        // Phase 9c conceded-goal analysis: G4 and G5 both had the
        // defensive line at x ~ -34 while the ball was at x ~ -43,
        // i.e. the runner was deeper than our DL. Cap defenders
        // (unum 2..8, the goal-side of the formation) at ball.x + 3
        // so we cannot be played behind.
        if ( self_unum >= 2 && self_unum <= 8 ) {
            const double cap_x = ball_pos.x + 3.0;
            if ( shifted_x > cap_x ) {
                shifted_x = cap_x;
            }
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
