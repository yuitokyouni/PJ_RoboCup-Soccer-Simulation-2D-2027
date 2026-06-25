// -*-c++-*-
//
// update_formation_325.cpp
//
// The body of Strategy::updateFormation325(). It lives here as a
// free function pasted into strategy.cpp by apply_phase5.sh so the
// rest of strategy.cpp does not have to be inlined into the patch
// directory.
//
// Mirrors updateFormation523() but for the 3-2-5 (rest: 3-4-3) shape:
//
//   PostLine:   1=golie | 2,3,4=back | 5,6,7,8=half | 9,10,11=forward
//   PlayerPost: 1=pp_gk | 2,3,4=pp_cb | 5=pp_lb (LWB) | 6,7=pp_ch (DH)
//               8=pp_rb (RWB) | 9=pp_lf | 10=pp_rf | 11=pp_cf
//
// WBs (5/8) drop to PostLine::back when ball is deep in our half OR
// opp is favored on the intercept table -- same trick 523 uses for
// its #5/#6 inside-CB swap. This is the formation-level half of the
// "WB explicit retreat" the user asked for; the per-cycle modulation
// (Phase 5e defense_block.cpp) does the rest.

void Strategy::updateFormation325( const WorldModel & wm ){
    int opp_min = wm.interceptTable().opponentStep();
    int mate_min = std::min(wm.interceptTable().teammateStep(), wm.interceptTable().selfStep());

    M_tm_line[1] = PostLine::golie;

    M_tm_line[2] = PostLine::back;
    M_tm_line[3] = PostLine::back;
    M_tm_line[4] = PostLine::back;

    // Wing-backs drop into the back line when defending. Mirror the
    // F523 swap criterion (ball deep in our half or opp closer on
    // the intercept table by 2+ steps).
    if ( wm.ball().pos().x < -5.0 || opp_min < mate_min - 2 ) {
        M_tm_line[5] = PostLine::back;
        M_tm_line[8] = PostLine::back;
        M_tm_post[5] = pp_lb;
        M_tm_post[8] = pp_rb;
    } else {
        M_tm_line[5] = PostLine::half;
        M_tm_line[8] = PostLine::half;
        M_tm_post[5] = pp_lb;  // keep the "this is a wing" identity
        M_tm_post[8] = pp_rb;
    }

    M_tm_line[6] = PostLine::half;
    M_tm_line[7] = PostLine::half;

    M_tm_line[9]  = PostLine::forward;
    M_tm_line[10] = PostLine::forward;
    M_tm_line[11] = PostLine::forward;

    M_tm_post[1] = pp_gk;
    M_tm_post[2] = pp_cb;
    M_tm_post[3] = pp_cb;
    M_tm_post[4] = pp_cb;

    M_tm_post[6] = pp_ch;
    M_tm_post[7] = pp_ch;

    M_tm_post[9]  = pp_lf;
    M_tm_post[10] = pp_rf;
    M_tm_post[11] = pp_cf;

    if ( wm.gameMode().type() == GameMode::PlayOn ) {
        if (M_current_situation == Defense_Situation)
            M_current_formation = M_F325_defense_formation;
        else if (M_current_situation == Offense_Situation)
            M_current_formation = M_F325_offense_formation;
        else
            M_current_formation = M_F325_offense_formation;
    }
    else if ( wm.gameMode().type() == GameMode::KickIn_
              || wm.gameMode().type() == GameMode::CornerKick_ ) {
        if ( wm.ourSide() == wm.gameMode().side() )
            M_current_formation = M_F325_kickin_our_formation;
        else
            M_current_formation = M_F325_setplay_opp_formation;
    }
    else if ( ( wm.gameMode().type() == GameMode::BackPass_
                && wm.gameMode().side() == wm.theirSide() )
              || ( wm.gameMode().type() == GameMode::IndFreeKick_
                   && wm.gameMode().side() == wm.ourSide() ) ) {
        M_current_formation = M_F325_setplay_our_formation;
    }
    else if ( ( wm.gameMode().type() == GameMode::BackPass_
                && wm.gameMode().side() == wm.ourSide() )
              || ( wm.gameMode().type() == GameMode::IndFreeKick_
                   && wm.gameMode().side() == wm.theirSide() ) ) {
        M_current_formation = M_F325_setplay_opp_formation;
    }
    else if ( wm.gameMode().type() == GameMode::FoulCharge_
              || wm.gameMode().type() == GameMode::FoulPush_ ) {
        if ( wm.gameMode().side() == wm.ourSide() )
            M_current_formation = M_F325_setplay_opp_formation;
        else
            M_current_formation = M_F325_setplay_our_formation;
    }
    else if ( wm.gameMode().type() == GameMode::GoalKick_
              || wm.gameMode().type() == GameMode::GoalieCatch_) {
        if ( wm.gameMode().side() == wm.ourSide() )
            M_current_formation = M_F325_goal_kick_our_formation;
        else
            M_current_formation = M_F325_goal_kick_opp_formation;
    }
    else if ( wm.gameMode().type() == GameMode::BeforeKickOff
              || wm.gameMode().type() == GameMode::AfterGoal_ ) {
        if ( wm.gameMode().type() == GameMode::BeforeKickOff ) {
            if ( wm.ourSide() == getBeforeKickOffSide(wm) )
                M_current_formation = M_F325_before_kick_off_formation_for_our_kick;
            else
                M_current_formation = M_F325_before_kick_off_formation;
        } else {
            if ( wm.gameMode().side() == wm.ourSide() )
                M_current_formation = M_F325_before_kick_off_formation;
            else
                M_current_formation = M_F325_before_kick_off_formation_for_our_kick;
        }
    }
    else if ( wm.gameMode().isOurSetPlay( wm.ourSide() ) ) {
        M_current_formation = M_F325_setplay_our_formation;
    }
    else if ( wm.gameMode().type() != GameMode::PlayOn ) {
        M_current_formation = M_F325_setplay_opp_formation;
    }
    else {
        if (M_current_situation == Defense_Situation)
            M_current_formation = M_F325_defense_formation;
        else if (M_current_situation == Offense_Situation)
            M_current_formation = M_F325_offense_formation;
        else
            M_current_formation = M_F325_offense_formation;
    }
}
