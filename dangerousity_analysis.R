# DANGEROUSITY - all 102 plays
afl <- read.csv('afl_tracking_plays.csv', stringsAsFactors = F)

## Constants ----
# Set once here, read inside the danger function. Grouped by the term that uses them.

# Location (LO) 
a_LO   <- 7.181   
b_LO   <- -1.923 
p_ang  <- 0.7     
d_max  <- 66     
s_rng  <- 5 
# Pressure (PR) 
r_headon  <- 6.0  
r_lateral <- 4.5 
r_behind  <- 4.0 
r_core    <- 1  
lambda    <- 1.0 
v_ref     <- 3 
k3        <- 1.0 
# Structure (ST)
k5     <- 0.2    
n_ref  <- 3   
# Dangerousity (DA) 
k_cap  <- 2.5 

## DA Function ----
# Takes one play id, subsets the frame to that play, and returns one-row
# data frame of the four terms plus DA. Called once per play by lapply below.
danger <- function(pid){
  
  this_play <- subset(afl, id_play == pid)
  carrier   <- subset(this_play, on_ball == 1)
  defs      <- subset(this_play, team == 'def')
  atts      <- subset(this_play, team == 'att' & on_ball == 0)

x_perp <- 80 - carrier$x
d_goal <- sqrt(x_perp^2 + carrier$y^2)  
theta  <- atan2(abs(carrier$y), x_perp)
is_general <- this_play$play_phase[1] == 'GENERAL_PLAY'

#LOCATION (LO)
# Three multipliers built from the carrier's x_perp, d_goal and y, then multiplied.
R_d <- 1 / (1 + exp((d_goal - d_max) / s_rng))
w_P <- abs( atan2( 3.2 - carrier$y, x_perp) - atan2(-3.2 - carrier$y, x_perp) )
w_0 <- abs( atan2( 3.2, x_perp) - atan2(-3.2, x_perp) )
A   <- pmin(1, w_P / w_0)^p_ang
LO  <- plogis(a_LO + b_LO * log(d_goal)) * A * R_d

#PRESSURE (PR)
# Adds one column per quantity to defs, so each of the 18 defenders is scored -
# in PR_i, then collapses those 18 values to a single number for the frame.
# Multiplying by is_general uses TRUE/FALSE as 1/0 to zero set shots.
gx <- x_perp / d_goal                         
gy <- (0 - carrier$y) / d_goal
defs$dx  <- defs$x - carrier$x
defs$dy  <- defs$y - carrier$y
defs$d_i <- sqrt(defs$dx^2 + defs$dy^2)     
defs$dv  <- defs$v - carrier$v                
defs$alpha_deg <- acos(pmax(-1, pmin(1,
                                     (defs$dx/defs$d_i)*gx + (defs$dy/defs$d_i)*gy ))) * 180/pi
defs$r_base <- ifelse(defs$alpha_deg <= 45,  r_headon,
                      ifelse(defs$alpha_deg <= 135, r_lateral, r_behind))
defs$r_i  <- defs$r_base * (1 + lambda * pmax(0, defs$dv) / v_ref)  
defs$PR_i <- ifelse(defs$d_i <= r_core, 1, pmax(0, 1 - defs$d_i/defs$r_i))
PR <- (1 - exp(-k3 * sum(defs$PR_i))) * is_general

#STRUCTURE (ST) and SHOT INTENT (SI)
# Counts rows in defs and atts within 50 m of goal and takes the difference.
defs$d_goal <- sqrt((80 - defs$x)^2 + defs$y^2)
atts$d_goal <- sqrt((80 - atts$x)^2 + atts$y^2)
n_def_f50 <- sum(defs$d_goal <= 50)
n_att_f50 <- sum(atts$d_goal <= 50)
M         <- n_def_f50 - n_att_f50 
ST <- (0.5 + atan(k5 * M) / pi) * (1 - exp(-n_def_f50 / n_ref))
SI <- if (is_general) R_d * cos(theta) else R_d

# DANGEROUSITY (DA), Equation 1 
# Combines the four scalars, returned below as a one-row data frame.
DA <- LO * (1 - (PR + (1 - SI) * ST) / k_cap)

data.frame(id_play = pid,
           phase   = this_play$play_phase[1],
           d_goal  = d_goal,
           theta   = theta * 180/pi,
           LO = LO, PR = PR, ST = ST, SI = SI,
           M = M, n_def_f50 = n_def_f50,
           DA = DA,
           stringsAsFactors = FALSE)
}
## Run all plays ----
# rbind the 102 one-row frames into one table, then sort by DA.
results <- do.call(rbind, lapply(unique(afl$id_play), danger))
results <- results[order(-results$DA), ]

summary(results$DA)

# all 102 plays, highest dangerousity first
DA_output <- results[, c("id_play", "phase", "DA", "LO", "PR", "ST", "SI",
                   "d_goal", "theta", "n_def_f50")]

num <- c("DA", "LO", "PR", "ST", "SI", "d_goal", "theta")
DA_output[num] <- round(DA_output[num], 3)

names(DA_output) <- c("id_play", "phase", "DA", "LO", "PR", "ST", "SI",
                "distance from goal (m)", "angle to goal (deg)", "#defi50")

options(width = 130)
print(DA_output, row.names = FALSE)
if (interactive()) View(DA_output) 
