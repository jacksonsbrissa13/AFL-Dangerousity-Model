# ASA - Assignment 2

library(dplyr)
library(ggplot2)
library(ggforce)

afl <- read.csv('afl_tracking_plays.csv', stringsAsFactors = F)

# The plays in the dataset
unique(afl$id_play)

ground <- c(160, 129)
angle <- seq(-pi, pi, length = 50)
oval <- data.frame(y = ground[2]/2 * cos(angle), x = ground[1]/2 * sin(angle))

# Plot a single play:
plot_play <- 19594

ggplot(subset(afl, id_play == plot_play), aes(x=x,y=y)) +
  # players
  geom_point(aes(col = team)) +
  geom_point(data = subset(afl, id_play == plot_play & on_ball == 1), aes(col = 'ball'), size = 2) +
  # ground
  geom_polygon(data = oval, aes(x = x, y = y), alpha = 0.1, fill = '#4DBD33') +
  # goal and centre squares
  geom_rect(aes(xmin = -25, xmax = 25, ymin = -25, ymax = 25), fill = "transparent", color = 'black') +
  geom_rect(aes(xmin = 71, xmax = 80, ymin = -3.2, ymax = 3.2), fill = "transparent", color = 'black') +
  geom_rect(aes(xmin = -80, xmax = -71, ymin = -3.2, ymax = 3.2), fill = "transparent", color = 'black') +
  # looks
  theme_bw() +
  coord_equal() +
  ggtitle(plot_play)

# GLOSSARY ----
# carrier   the player with the ball (on_ball == 1)
# defs      the 18 defenders
#
# d_goal    carrier's distance to the goal
# theta     carrier's angle off centre (0 = dead in front)
#
# per defender:
#   d_i       distance from that defender to the carrier
#   alpha     that defender's angle off the carrier->goal line
#               0 deg   = between carrier and goal
#               90 deg  = beside
#               180 deg = behind
#   dv        that defender's speed minus the carrier's speed
#               positive = faster than the carrier (assumed closing)
#   r_base    size of his zone, set by alpha (6m / 4.5m / 3m)
#   r_i       his zone after stretching for closing speed
#   PR_i      pressure he applies: 1 at the core, 0 at the zone edge
#
# PR        all defenders combined, 0 to 1
# ST        structure: what's between the ball and the goal, 0 to 1
# LO        location: conversion chance from that spot, 0 to 1
# DA        final dangerousity
# w_shot    how much this play is a shot rather than a disposal (0-1)

# hand checking these plays (9128, 8929, 11328)


#xxxx GENERAL_PLAY ----
play_id <- 12491

#visual 
ggplot(subset(afl, id_play == play_id), aes(x=x,y=y)) +
  # players
  geom_point(aes(col = team)) +
  geom_point(data = subset(afl, id_play == play_id & on_ball == 1), aes(col = 'ball'), size = 2) +
  # ground
  geom_polygon(data = oval, aes(x = x, y = y), alpha = 0.1, fill = '#4DBD33') +
  # goal and centre squares
  geom_rect(aes(xmin = -25, xmax = 25, ymin = -25, ymax = 25), fill = "transparent", color = 'black') +
  geom_rect(aes(xmin = 71, xmax = 80, ymin = -3.2, ymax = 3.2), fill = "transparent", color = 'black') +
  geom_rect(aes(xmin = -80, xmax = -71, ymin = -3.2, ymax = 3.2), fill = "transparent", color = 'black') +
  # looks
  theme_bw() +
  coord_equal() +
  ggtitle(play_id)

## Pressure ----
# pull out the play 
this_play <- subset(afl, id_play == play_id)
# the ball carrier: exactly one row per play with on_ball == 1
carrier <- subset(this_play, on_ball == 1)
# the 18 defenders
defs <- subset(this_play, team == 'def')

### carrier's own geometry ----
# straight-line distance from the carrier to the centre of the goal
d_goal <- sqrt( (80 - carrier$x)^2 + (0 - carrier$y)^2 )

# angle off centre (0 = dead in front). Used later by Location, not Pressure.
theta <- atan2( abs(carrier$y), 80 - carrier$x )

cat('carrier at (', round(carrier$x,3), ',', round(carrier$y,3), ')',
    ' speed', round(carrier$v,3), '\n')
cat('distance to goal =', round(d_goal,3), 'm\n')
cat('angle off centre =', round(theta*180/pi,1), 'deg\n\n')

### direction from the carrier to the goal ----
# This is the reference direction, "straight ahead"
# Divided by d_goal so it has length 1 (a pure direction, no magnitude).
gx <- (80 - carrier$x) / d_goal
gy <- (0  - carrier$y) / d_goal

###  inputs for every defender ----
# 1. offset from the carrier
defs$dx <- defs$x - carrier$x
defs$dy <- defs$y - carrier$y

# 2. INPUT ONE: distance from the defender to the carrier
defs$d_i <- sqrt(defs$dx^2 + defs$dy^2)

# 3. INPUT TWO: closing speed. Positive means the defender is moving faster than the carrier.
defs$dv <- defs$v - carrier$v

# 4. INPUT THREE: angle between "carrier -> goal" and "carrier -> defender".
#    0 deg   = defender is directly between the carrier and the goal
#    90 deg  = square beside the carrier
#    180 deg = directly behind the carrier
#    Unit vector from the carrier to each defender:
defs$ux <- defs$dx / defs$d_i
defs$uy <- defs$dy / defs$d_i

#    Dot product of two unit vectors = cosine of the angle between them.
#    pmax/pmin guard against floating point pushing it just past +/-1,
#    which would make acos() return NaN.
defs$cos_a <- pmax(-1, pmin(1, defs$ux*gx + defs$uy*gy))
defs$alpha <- acos(defs$cos_a)              # radians
defs$alpha_deg <- defs$alpha * 180/pi       # degrees, easier to read

### sort by proximity and look at the closest defenders ----
defs <- defs[order(defs$d_i), ]

print(
  data.frame(
    x         = round(defs$x, 2),
    y         = round(defs$y, 2),
    v         = round(defs$v, 2),
    d_i       = round(defs$d_i, 3),      # how far away
    alpha_deg = round(defs$alpha_deg, 1),# where he's standing
    dv        = round(defs$dv, 3)        # is he closing
  )[1:6, ],
  row.names = FALSE
)

### the single defender worked by hand ----
d1 <- defs[1, ]
cat('\nDEFENDER 1 (closest)\n')
cat('  d_1     =', round(d1$d_i, 3),      'm\n')
cat('  dv_1    =', round(d1$dv, 3),       'm/s\n')
cat('  alpha_1 =', round(d1$alpha_deg, 1),'deg\n')


## Pressure rating ----

# Zone radii (m) = disposal time x closing speed: 1.5s x 4.06 m/s ~ 6m head-on.
# SENSITIVITY: 1.0s -> 4m, 2.0s -> 8m.
r_headon  <- 6.0    # alpha <= 45    between carrier and goal
r_lateral <- 4.5    # 45 - 135       beside the carrier
r_behind  <- 4.0    # > 135          behind the carrier


lambda <- 1.0     # how much a closing defender stretches his zone
v_ref  <- 3       # reference closing speed (max dv observed is 3.76)
r_core <- 1       # inside this, pressure is maximal regardless of angle
k3     <- 1.0     # saturation rate when several defenders apply pressure

# STEP 1: zone size from the angle.
#   <= 45 deg   head-on: between the carrier and the goal, largest zone
#   45-135 deg  lateral: beside the carrier
#   > 135 deg   hind: behind the carrier, smallest zone
defs$r_base <- ifelse(defs$alpha_deg <= 45,  r_headon,
                     ifelse(defs$alpha_deg <= 135, r_lateral,
                            r_behind))

# STEP 2: stretch the zone if he is closing.
# pmax(0, dv) means a defender slower than the carrier gets no stretch,
# so this collapses to Link's original model when nobody is closing.
defs$stretch <- 1 + lambda * pmax(0, defs$dv) / v_ref
defs$r_i     <- defs$r_base * defs$stretch

# STEP 3: pressure from each defender.
# 1 inside the core, falling linearly to 0 at the edge of his zone.
# pmax(0, ...) clamps anyone outside his zone to zero, so no explicit
# distance cutoff is needed.
defs$PR_i <- ifelse(defs$d_i <= r_core,
                    1,
                    pmax(0, 1 - defs$d_i / defs$r_i))

# STEP 4: combine into one number for the play.
# Saturating: each extra defender adds less than the last, and PR can
# never exceed 1. Zeroed on set shots - defenders are frozen by rule and
# cannot pressure the kick.
is_general <- this_play$play_phase[1] == 'GENERAL_PLAY'
PR <- (1 - exp(-k3 * sum(defs$PR_i))) * is_general

# --- look at the working ---
print(
  data.frame(
    d_i     = round(defs$d_i, 3),
    alpha   = round(defs$alpha_deg, 1),
    dv      = round(defs$dv, 3),
    r_base  = defs$r_base,
    stretch = round(defs$stretch, 3),
    r_i     = round(defs$r_i, 3),
    PR_i    = round(defs$PR_i, 4)
  )[1:6, ],
  row.names = FALSE
)

cat('\nphase        =', this_play$play_phase[1], '\n')
cat('sum of PR_i  =', round(sum(defs$PR_i), 4), '\n')
cat('PR           =', round(PR, 4), '\n')
cat('contributing =', sum(defs$PR_i > 0), 'of', nrow(defs), 'defenders\n')

## Structure rating ----

k5    <- 0.2    # how sharply ST responds to the numbers advantage M
n_ref <- 3      # scales ST by defender presence: empty F50 obstructs nothing

# Interception zone = the forward 50 (AFL rule-defined)
defs$d_goal <- sqrt((80 - defs$x)^2 + defs$y^2)

# carrier excluded - he cannot be his own kicking target
atts        <- subset(this_play, team == 'att' & on_ball == 0)
atts$d_goal <- sqrt((80 - atts$x)^2 + atts$y^2)

n_def_f50 <- sum(defs$d_goal <= 50)
n_att_f50 <- sum(atts$d_goal <= 50)
M         <- n_def_f50 - n_att_f50    # positive = defence outnumbers

# 0.5 when even, rising as the defence outnumbers, scaled by how many are there
ST <- (0.5 + atan(k5 * M) / pi) * (1 - exp(-n_def_f50 / n_ref))

cat('\ndef in F50 =', n_def_f50, ' att in F50 =', n_att_f50, ' M =', M, '\n')
cat('occupancy  =', round(1 - exp(-n_def_f50/n_ref), 4), '\n')
cat('ST =', round(ST, 4), '\n')
## Location rating ----

# LO is the ceiling: the conversion chance from this spot if nothing goes
# wrong. Three multiplied parts - distance, angle, reachability.

# Distance: fit to Anderson et al. (2018) Table 1, n = 4599
a_LO <- 7.181
b_LO <- -1.923

# Angle: A = fraction of the goal visible from the ball, raised to p.
# p calibrated to Anderson's acute/front ratio 0.628; depends on the assumed
# typical angle of his ">=30 deg" bin: 30deg -> 1.63, 40deg -> 0.88, 45deg -> 0.68.
# Lower end taken: Anderson is 2012 set-shot data, and a set-shot player picks
# the technique that suits the angle. See report.
# SENSITIVITY: 0.7 to 1.6
p_ang <- 0.7

# Reachability: calibrated so LO(54m) = 0.355, Anderson's 50m+ band
# SENSITIVITY: 52m -> d_max 63, 56m -> 70
d_max <- 66
s_rng <- 5

R_d <- 1 / (1 + exp((d_goal - d_max) / s_rng))

# Perpendicular distance to the goal line, NOT d_goal. d_goal is measured to
# the goal centre, which puts the reference behind the player and lets the
# ratio exceed 1 at close range (8929 gave LO = 1.023).
x_perp <- 80 - carrier$x

# goal angle seen by the carrier, vs the best on the same parallel line
w_P <- abs( atan2( 3.2 - carrier$y, x_perp) -
              atan2(-3.2 - carrier$y, x_perp) )
w_0 <- abs( atan2( 3.2, x_perp) - atan2(-3.2, x_perp) )

LO <- plogis(a_LO + b_LO * log(d_goal)) * pmin(1, w_P / w_0)^p_ang * R_d

cat('\nbase (distance) =', round(plogis(a_LO + b_LO*log(d_goal)), 4), '\n')
cat('A (angle)       =', round(pmin(1, w_P/w_0)^p_ang, 4), '\n')
cat('R (reach)       =', round(R_d, 4), '\n')
cat('LO              =', round(LO, 4), '\n')

## Dangerousity ----

# w_shot: how much this play is a shot rather than a disposal. Set shots drop
# the angle term - he has marked it and will shoot regardless of angle.
w_shot <- if (is_general) R_d * cos(theta) else R_d

k_cap <- 2.5    # max discount = 2/k_cap = 80%. Link uses 0.5 (k = 4).

# SENSITIVITY: 2.5, 3.3, 4

DA <- LO * (1 - (PR + (1 - w_shot) * ST) / k_cap)

cat('\n--- PLAY', play_id, '---\n')
cat('phase    =', this_play$play_phase[1], '\n')
cat('LO       =', round(LO, 4), '\n')
cat('PR       =', round(PR, 4), '\n')
cat('ST       =', round(ST, 4), '\n')
cat('w_shot   =', round(w_shot, 4), '\n')
cat('discount =', round((PR + (1 - w_shot)*ST)/k_cap, 4), '\n')
cat('DA       =', round(DA, 4), '\n')


# Refactor: danger() now takes a parameter list so constants can be varied.
# Replace the fixed constants inside danger() with P$name, and set the
# defaults in P0 below.

P0 <- list(r_headon = 6, r_lateral = 4.5, r_behind = 4,
           lambda = 1, v_ref = 3, r_core = 1, k3 = 1,
           k5 = 0.2, n_ref = 3,
           a_LO = 7.181, b_LO = -1.923, p_ang = 0.7,
           d_max = 66, s_rng = 5, k_cap = 2.5)

danger <- function(pid, P = P0){
  
  this_play <- subset(afl, id_play == pid)
  carrier   <- subset(this_play, on_ball == 1)
  defs      <- subset(this_play, team == 'def')
  atts      <- subset(this_play, team == 'att' & on_ball == 0)
  
  x_perp <- 80 - carrier$x
  d_goal <- sqrt(x_perp^2 + carrier$y^2)
  theta  <- atan2(abs(carrier$y), x_perp)
  is_general <- this_play$play_phase[1] == 'GENERAL_PLAY'
  
  # --- PRESSURE ---
  gx <- x_perp / d_goal
  gy <- (0 - carrier$y) / d_goal
  defs$dx  <- defs$x - carrier$x
  defs$dy  <- defs$y - carrier$y
  defs$d_i <- sqrt(defs$dx^2 + defs$dy^2)
  defs$dv  <- defs$v - carrier$v
  defs$alpha_deg <- acos(pmax(-1, pmin(1,
                                       (defs$dx/defs$d_i)*gx + (defs$dy/defs$d_i)*gy ))) * 180/pi
  
  defs$r_base <- ifelse(defs$alpha_deg <= 45,  P$r_headon,
                        ifelse(defs$alpha_deg <= 135, P$r_lateral, P$r_behind))
  defs$r_i  <- defs$r_base * (1 + P$lambda * pmax(0, defs$dv) / P$v_ref)
  defs$PR_i <- ifelse(defs$d_i <= P$r_core, 1, pmax(0, 1 - defs$d_i/defs$r_i))
  PR <- (1 - exp(-P$k3 * sum(defs$PR_i))) * is_general
  
  # --- STRUCTURE ---
  defs$d_goal <- sqrt((80 - defs$x)^2 + defs$y^2)
  atts$d_goal <- sqrt((80 - atts$x)^2 + atts$y^2)
  n_def_f50 <- sum(defs$d_goal <= 50)
  n_att_f50 <- sum(atts$d_goal <= 50)
  M         <- n_def_f50 - n_att_f50
  ST <- (0.5 + atan(P$k5 * M) / pi) * (1 - exp(-n_def_f50 / P$n_ref))
  
  # --- LOCATION ---
  R_d <- 1 / (1 + exp((d_goal - P$d_max) / P$s_rng))
  w_P <- abs( atan2( 3.2 - carrier$y, x_perp) - atan2(-3.2 - carrier$y, x_perp) )
  w_0 <- abs( atan2( 3.2, x_perp) - atan2(-3.2, x_perp) )
  A   <- pmin(1, w_P / w_0)^P$p_ang
  LO  <- plogis(P$a_LO + P$b_LO * log(d_goal)) * A * R_d
  
  # --- COMBINE ---
  w_shot <- if (is_general) R_d * cos(theta) else R_d
  DA <- LO * (1 - (PR + (1 - w_shot) * ST) / P$k_cap)
  
  data.frame(id_play = pid, phase = this_play$play_phase[1],
             d_goal = d_goal, theta = theta*180/pi,
             LO = LO, PR = PR, ST = ST, w_shot = w_shot,
             M = M, n_def_f50 = n_def_f50, DA = DA,
             stringsAsFactors = FALSE)
}

run_all <- function(P = P0) do.call(rbind, lapply(unique(afl$id_play), danger, P = P))

base <- run_all(P0)


# --- sensitivity: vary one constant at a time, compare the whole ranking ---
grid <- list(p_ang    = c(0.7, 1.0, 1.3, 1.6),
             d_max    = c(63, 66, 70),
             k_cap    = c(2.5, 3.3, 4.0),
             k5       = c(0.1, 0.2, 0.5),
             n_ref    = c(2, 3, 5),
             r_headon = c(4, 6, 8))

sens <- do.call(rbind, lapply(names(grid), function(nm){
  do.call(rbind, lapply(grid[[nm]], function(v){
    P <- P0; P[[nm]] <- v
    # keep Link's 4:3:2 proportions when scaling the zone radii
    if (nm == 'r_headon'){ P$r_lateral <- v*0.75; P$r_behind <- v*(2/3) }
    r <- run_all(P)
    data.frame(constant = nm, value = v,
               rho = cor(base$DA, r$DA, method = 'spearman'),
               top10 = length(intersect(order(-base$DA)[1:10], order(-r$DA)[1:10])),
               stringsAsFactors = FALSE)
  }))
}))
sens


# --- baseline comparison (Carey, slide 72) ---
c(distance_only = cor(base$DA, -base$d_goal,  method = 'spearman'),
  location_only = cor(base$DA,  base$LO,      method = 'spearman'))

# top-10 overlap against a distance-only ranking
length(intersect(order(-base$DA)[1:10], order(base$d_goal)[1:10]))








