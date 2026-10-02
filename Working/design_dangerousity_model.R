# =====================================================================
# AFL DANGEROUSITY MODEL DESIGN
# =====================================================================
#
# OUTPUT
#   DA = estimated probability of a goal on this play. Continuous 0-1.
#
# ASSUMPTIONS (report: criterion 2)
#   1. Goal only. Behinds score zero.
#   2. Conditional on a shot eventuating from approximately the current
#      ball location. The dataset gives no information on what follows
#      each frame, so the "does a shot even happen" step is not modelled.
#      Read scores as relative danger rankings, not calibrated probabilities.
#   3. Match context (score, clock) ignored. Note: in late-game states a
#      behind can be as valuable as a goal -> see EXTENSIONS.
#   4. All players priced at league-average kicking ability.
#   5. v is a scalar. A defender near the ball travelling faster than the
#      carrier is assumed to be closing on them.
#
# FRAME OF REFERENCE (verified from the data, not assumed)
#   att attacks +x. Goal centre (80, 0), posts (80, +/-3.2).
#   Checks: 0 of 102 carriers have x < 0; mean deepest att x = -21.2 vs
#   mean deepest def x = +65.0; on_ball is team 'att' in all 102 plays.
#
#   d     = sqrt((80 - x_b)^2 + y_b^2)        distance to goal
#   theta = atan2(abs(y_b), 80 - x_b)         angle off centre
#
# DATA NOTES
#   102 plays, 36 rows each (18 att / 18 def). One clock value per play:
#   each play is a single frozen frame, not a time series.
#   Exactly one on_ball == 1 per play, always att. No ball row.
#   60 SET / 42 GENERAL_PLAY.
#   Carrier distance to goal: min 1.6, median 59.1, max 91.2.
#   60 of 102 plays sit beyond 55m, i.e. beyond Anderson's fitted range.
#
# ---------------------------------------------------------------------
# COMPONENTS  (maps onto Link et al. 2016: ZO / CO / PR / DE)
# ---------------------------------------------------------------------
#   LO  Location   quality of the spot                    <- Link's ZO
#   PR  Pressure   can the carrier execute the kick       <- Link's PR
#   ST  Structure  balance of att/def between ball and goal,
#                  and congestion of the corridor the kick
#                  must travel through                    <- Link's DE
#
#   Link's CO (Control) is NOT computable: no possession-type variable.
#   play_phase is a weak proxy on SET plays only. See EXTENSIONS.
#
# ---------------------------------------------------------------------
# FORMULA
# ---------------------------------------------------------------------
#   DA = LO * ( 1 - (PR + ST) / k )
#
#   Multiplicative base, additive penalties (Link Eq 1 structure).
#   LO is a ceiling: PR and ST only ever subtract from it.
#
# --- LO ---------------------------------------------------------------
#   LO = plogis(a + b*log(d)) * A(theta) * R(d)
#
#   a = 7.1810, b = -1.9228     fitted to Anderson et al. 2018, n = 4599
#     pooled set-shot accuracy by distance (key fwds + others, weighted):
#       0-15m 96.2% (n=186)    15-30m 77.5% (767)   30-40m 57.8% (1057)
#       40-50m 47.4% (1876)    50m+   35.5% (713)
#     Form motivated by angle of opportunity: the goal subtends an angle
#     ~ 1/d, so log-odds should fall linearly in log(d).
#     SSE 0.00047, better than linear / exponential / logistic-in-d,
#     and derived from a mechanism rather than chosen for fit.
#
#   A(theta) = ( w(P) / w_centre(d) )^p
#     w(P) = angle subtended at the ball by the two goal posts.
#     Checked: w ratio is near-independent of d (0.873 at 20m, 0.867 at
#     60m) -> justifies multiplying the angle term rather than fitting a
#     joint surface.
#     p calibrated so A matches Anderson's acute/front ratio 39.6/63.1
#     = 0.628. p depends on the assumed representative angle of the
#     ">= 30 deg" bin: 30deg -> p=3.28, 40deg -> 1.77, 45deg -> 1.36.
#     START p = 2.0, RUN SENSITIVITY over 1.4 - 3.3.
#
#   R(d) = 1 / (1 + exp((d - d_max)/s))      reachability
#     The fitted curve extrapolates to 22% from 80m, which is nonsense.
#     Anderson: 50+ m is "beyond the kicking range of most professional
#     AF players". START d_max = 55, s = 6. Both need a football argument.
#
# --- PR ---------------------------------------------------------------
#   For each defender i:
#     dv_i = v_i - v_b
#     r_i  = r_base(alpha_i) * (1 + lambda * max(0, dv_i) / v_ref)
#     PR_i = 1                     if d_i <= r_core
#            max(0, 1 - d_i/r_i)   otherwise
#
#   PR = (1 - exp(-k3 * sum(PR_i))) * (play_phase == 'GENERAL_PLAY')
#
#   r_base by zone (alpha measured from the carrier->goal direction).
#   Link's soccer values - MUST BE RE-ARGUED FOR AFL:
#     core    any        1 m
#     head-on <= 45 deg  4 m
#     lateral 45-135     3 m
#     hind    > 135      2 m
#
#   AFL DEPARTURE 1 - PHASE MODIFIER
#     On a SET shot the defenders are frozen by rule and cannot pressure
#     the kick, so PR = 0. Mechanistic, not correlational. 60 of 102 plays.
#     Soccer has no equivalent; Link has no phase term.
#
#   AFL DEPARTURE 2 - CHASE-DOWN TACKLE
#     Soccer has no tackle, so Link's hind zone is his smallest (2m).
#     In AFL a defender closing from behind can end the play outright.
#     The (1 + lambda*max(0,dv)/v_ref) factor stretches the zone for a
#     closing defender and collapses to Link's original when dv <= 0.
#     Data check: 45/102 plays have a defender within 8m behind the
#     carrier; in 25 of those he is faster (median advantage 1.03 m/s,
#     max 3.76). 12 of those 25 are GENERAL_PLAY, i.e. tackles are legal.
#     Consistent with the phase modifier: the other 13 are SET, where
#     PR is already zeroed.
#     Relative speed is used in the source paper too (Link Eq 2, v_rel).
#
# --- ST ---------------------------------------------------------------
#   ST = C * SD + (1 - C) * PD                          Link Eq 5
#
#   C = R(d) * cos(theta)          blend weight, no new constants
#     Central and in range -> the question is "can they block the shot".
#     Wide or deep       -> the question is "is there anyone to kick to".
#
#   SD  defenders inside the wedge from the carrier to the two posts
#       SD_i = 1 - d_i / d                              Link Eq 6
#       SD   = 1 - exp(-k4 * sum(SD_i))
#
#   PD  M  = (defenders in F50) - (attackers in F50)
#       PD = 0.5 + atan(k5 * M) / pi                    Link Eq 7
#       Interception zone = the forward 50: a rule-defined AFL zone,
#       not an arbitrary rectangle (Link's is arbitrary - see slide 55).
#
# --- k ----------------------------------------------------------------
#   PR, ST in [0,1] so (PR + ST) in [0,2].
#     k = 2 / (maximum allowed reduction)
#   Link caps reduction at 0.5 -> k = 4. For AFL, six defenders in the
#   goalsquare should arguably cost more than half. Cap 0.8 -> k = 2.5.
#   BIGGEST SINGLE LEVER IN THE MODEL. Needs an explicit argument.
#
# ---------------------------------------------------------------------
# CONSTANTS TO SET  (Carey slides 50, 55, 58: every one needs a source
# or a football argument, or it is an "arbitrary number")
# ---------------------------------------------------------------------
#   a, b        7.181, -1.923   FITTED to data (Anderson 2018)
#   p           2.0             calibrated + sensitivity 1.4 - 3.3
#   d_max, s    55, 6           Anderson discussion on kicking range
#   r_base      4/3/2/1 m       Link (soccer) - RE-ARGUE FOR AFL
#   lambda      ?               chase-down stretch. judgement
#   v_ref       3               near max closing advantage observed (3.76)
#   k3, k4      ?               saturation rates
#   k5          ?               majority sensitivity
#   k           2.5 - 4         max discount
#
# OPEN DECISIONS
#   1. k - how much can the defence take off you
#   2. lambda
#   3. k3, k4, k5
#   4. Are Link's 4/3/2m radii right for a sport with tackling
#   5. PD = 0.5 when numbers are even, so ST is never zero and every play
#      eats a discount. Check against play 8929 (1.6m out, 0 def
#      goal-side, LO ~ 0.99). Should an even contest be neutral instead?
#
# ---------------------------------------------------------------------
# EXTENSIONS  (brief requires these to be clearly labelled)
# ---------------------------------------------------------------------
#   1. CARRIER / DEFENDER DIRECTION. v is a scalar. With velocity vectors
#      the closing assumption disappears and momentum toward goal could
#      be modelled directly. Player influence is commonly modelled as
#      decaying with distance and scaled by speed and heading
#      (Fernandez & Bornn 2018).
#   2. POSSESSION QUALITY (= Link's Control). Clean mark vs contested
#      ground ball changes danger enormously at identical coordinates.
#      Needs a possession-type variable per frame.
#   3. PLAYER KICKING ABILITY. Anderson: key forwards 6% more accurate
#      than others in front of goal, but NOT on angles >= 30 deg, and
#      experience had no effect on accuracy. Arguably league-average is
#      the correct choice for a situation model rather than a player one.
#   4. STATE-DEPENDENT SCORE VALUE. E[value] = P(goal)*V_goal(state) +
#      P(behind)*V_behind(state). Scores level, 30 seconds left, a behind
#      wins the game and is worth as much as a goal. Needs margin, time
#      remaining, and a win probability model.
#   5. PITCH CONTROL for ST. Sum of bivariate normals per player, signed
#      by team, squashed logistically (Week 4 workshop; Fernandez & Bornn
#      2018). More principled than counting but adds a covariance matrix
#      to justify, and the brief says start simple.
#   6. GROUND CONDITIONS. Wind materially changes conversion at distance.
#      Anderson: wet weather cut set-shot volume 13% but did not affect
#      accuracy.
#
# ---------------------------------------------------------------------
# LIMITATIONS TO WRITE UP  (criterion 6)
# ---------------------------------------------------------------------
#   - 60 of 102 plays are beyond Anderson's fitted range. LO extrapolates
#     for the majority of the dataset; ST carries those plays.
#   - LO is data-anchored; PR and ST are reasoned only. State the
#     asymmetry rather than implying all three are equally grounded.
#   - Link validated dangerousity against betting odds. Odds are not
#     ground truth: they are another model's output, carry an overround,
#     and move with money flow. Agreement between two models is not
#     evidence either is correct. Carey, slide 65: "this validity metric
#     is strange - I'm not 100% convinced".
#   - Calibration cannot be assessed. No outcomes, and 102 plays would be
#     too few to test a probability even with them. Ranking is testable
#     (the comparison uses correlation); level is not.
#   - No baseline comparison unless one is built. Carey, slide 72:
#     "could a simpler approach accomplish the same thing?" A distance-
#     only model is the obvious baseline.
#
# ---------------------------------------------------------------------
# SOURCES
# ---------------------------------------------------------------------
#   Link, D., Lang, S., & Seidenschwarz, P. (2016). Real Time
#     Quantification of Dangerousity in Football Using Spatiotemporal
#     Tracking Data. PLoS ONE, 11(12), e0168768.
#   Anderson, D., Breed, R., Spittle, M., & Larkin, P. (2018). Factors
#     Affecting Set Shot Goal-kicking Performance in the Australian
#     Football League. Perceptual and Motor Skills, 125(4), 817-833.
#   Browne, P. R., Sweeting, A. J., & Robertson, S. (2022). Modelling the
#     Influence of Task Constraints on Goal Kicking Performance in
#     Australian Rules Football. Sports Medicine - Open, 8, 13.
#   Fernandez, J., & Bornn, L. (2018). Wide Open Spaces: A statistical
#     technique for measuring space creation in professional soccer.
#     MIT Sloan Sports Analytics Conference.
# =====================================================================