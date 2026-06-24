// -*-c++-*-
//
// defense_duty.cpp
//
// Phase 4 extension. See defense_duty.h.

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include "defense_duty.h"

#include <rcsc/player/world_model.h>
#include <rcsc/player/abstract_player_object.h>
#include <rcsc/player/player_object.h>
#include <rcsc/common/server_param.h>

using namespace rcsc;

namespace {

// Position quality threshold. Use only players whose self-observation
// hasn't gone stale; ghost players are excluded.
inline bool reliable( const AbstractPlayerObject * p )
{
    if ( ! p ) return false;
    if ( p->unum() < 1 ) return false;  // unknown unum
    if ( p->isGhost() ) return false;
    return true;
}

// Strict-less-than with unum tiebreak. Used in "am I the closest"
// loops so that two players who tie by distance still agree on which
// one of them is "the chosen one" (the lower unum wins).
inline bool nearer_than(
    double their_dist, int their_unum,
    double my_dist,    int my_unum )
{
    if ( their_dist < my_dist - 0.5 ) return true;
    if ( their_dist < my_dist + 0.5 && their_unum < my_unum ) return true;
    return false;
}

}  // namespace


DefenseDuty
DefenseDutyAssigner::assign( const WorldModel & wm )
{
    DefenseDuty duty;  // default NONE

    const Vector2D ball_pos = wm.ball().pos();
    const Vector2D self_pos = wm.self().pos();
    const int self_unum = wm.self().unum();

    // Goalie has its own RoleGoalie::doMove; we don't override that.
    if ( self_unum == 1 ) return duty;

    // Only activate when an opponent is on the ball AND ball is roughly
    // in our half of the pitch. In opponent territory the formation
    // file (offense/normal) drives positioning.
    const AbstractPlayerObject * carrier = wm.kickableOpponent();
    if ( ! carrier ) return duty;
    if ( ball_pos.x > 5.0 ) return duty;

    const Vector2D our_goal( -ServerParam::i().pitchHalfLength(), 0.0 );

    //-------------------------------------------------------------
    // Step 1: am I the presser?
    // The presser is the closest field-player teammate (including
    // self, excluding goalie) to the ball carrier.
    //-------------------------------------------------------------
    {
        const double my_dist = ( self_pos - carrier->pos() ).r();

        bool i_press = true;
        const PlayerObject::Cont & teammates = wm.teammates();
        for ( PlayerObject::Cont::const_iterator it = teammates.begin();
              it != teammates.end(); ++it )
        {
            if ( ! reliable( *it ) ) continue;
            if ( (*it)->unum() == 1 ) continue;  // skip goalie
            const double their_dist = ( (*it)->pos() - carrier->pos() ).r();
            if ( nearer_than( their_dist, (*it)->unum(), my_dist, self_unum ) )
            {
                i_press = false;
                break;
            }
        }

        if ( i_press )
        {
            duty.type = DefenseDuty::PRESS;
            duty.target = carrier;
            Vector2D dir = carrier->pos() - our_goal;
            if ( dir.r() < 0.01 ) dir = Vector2D( 1.0, 0.0 );
            else dir.setLength( 1.5 );
            duty.position = carrier->pos() - dir;
            return duty;
        }
    }

    //-------------------------------------------------------------
    // Step 2: do I cover an opponent?
    // For each opponent in our half (except the carrier), I claim
    // them if I'm the closest field-player teammate to them. Among
    // the opponents I claim, I take the one closest to our goal
    // (most dangerous).
    //-------------------------------------------------------------
    const AbstractPlayerObject * mark = 0;
    const PlayerObject::Cont & opps = wm.opponents();
    for ( PlayerObject::Cont::const_iterator it = opps.begin();
          it != opps.end(); ++it )
    {
        const AbstractPlayerObject * opp = *it;
        if ( ! reliable( opp ) ) continue;
        if ( opp == carrier ) continue;
        if ( opp->pos().x > 5.0 ) continue;          // not in our zone
        if ( opp->posCount() > 8 ) continue;         // observation too stale

        const double my_d = ( opp->pos() - self_pos ).r();
        if ( my_d > 22.0 ) continue;                 // too far away to mark

        // Am I the closest field-player teammate to this opp?
        bool i_am_closest = true;
        const PlayerObject::Cont & teammates = wm.teammates();
        for ( PlayerObject::Cont::const_iterator tm = teammates.begin();
              tm != teammates.end(); ++tm )
        {
            if ( ! reliable( *tm ) ) continue;
            if ( (*tm)->unum() == 1 ) continue;
            const double tm_d = ( (*tm)->pos() - opp->pos() ).r();
            if ( nearer_than( tm_d, (*tm)->unum(), my_d, self_unum ) )
            {
                i_am_closest = false;
                break;
            }
        }
        if ( ! i_am_closest ) continue;

        // Most dangerous = closest to our goal
        if ( mark == 0
             || ( opp->pos() - our_goal ).r() < ( mark->pos() - our_goal ).r() )
        {
            mark = opp;
        }
    }

    if ( mark )
    {
        duty.type = DefenseDuty::COVER;
        duty.target = mark;
        Vector2D dir = mark->pos() - our_goal;
        if ( dir.r() < 0.01 ) dir = Vector2D( 1.0, 0.0 );
        else dir.setLength( 2.5 );
        duty.position = mark->pos() - dir;
        return duty;
    }

    return duty;  // NONE
}
