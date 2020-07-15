## ---- include=TRUE, echo=FALSE------------------------------------------------
# --------------------------------------------------------------
# generate R file with code from this file
# --------------------------------------------------------------
knitr::purl(input = "SAVVY_AEprobs.Rmd", output = "SAVVY_AEprobs.r")


## ---- include=TRUE, echo=TRUE-------------------------------------------------
# --------------------------------------------------------------
# packages
# --------------------------------------------------------------
packs <- c("data.table", "etm", "survival", "mvna", "knitr")    
for (i in 1:length(packs)){library(packs[i], character.only = TRUE)}


## ---- include=TRUE, echo=TRUE-------------------------------------------------
# --------------------------------------------------------------
# functions
# --------------------------------------------------------------

# function to generate dataset with constant hazards for AE, death, and soft competing events
data_generation_constant_cens <- function(N, min.cens, max.cens.A, haz.AE, haz.death,
                                          haz.soft, seed = 57 * i + 5){
  
  # status, 1 for AE, 2 for death 3 for soft competing event
  set.seed(seed)
  haz.all <- haz.AE + haz.death + haz.soft

  my.data <- data.table(time_to_event = rep(0, N), type_of_event = rep(0, N))
  my.data$time_to_event<- rexp(n = N, rate = haz.all) # event time
  my.data$type_of_event <- rbinom(n = N, size = 2, 
                                  prob = c(haz.AE / haz.all, haz.death / haz.all, haz.soft / haz.all)) + 1
                                  # status, 1 for AE, 2 for death 3 for soft competing event
  my.data$cens <- runif(n = N, min = min.cens, max = max.cens)
  my.data$type_of_event <- as.numeric(my.data$time_to_event <= my.data$cens) * my.data$type_of_event
  my.data$time_to_event <- pmin(my.data$time_to_event, my.data$cens)
  my.data$id <- 1:N

  # reorder columns
  my.data <- my.data[, c("id", "time_to_event", "type_of_event", "cens")]
  return(my.data)
}

# compute incidence proportion
incidenceProportion <- function(data, tau){

  ae <- nrow(data[type_of_event == 1 & time_to_event <= tau]) / nrow(data)
  ae_prob_var <- ae * (1 - ae) / nrow(data)

  res <- c("ae_prob" = ae, "ae_prob_var" = ae_prob_var)
  return(res)
}

# compute probability transform incidence density
probTransIncidenceDensity <- function(data, tau){

  time <- data$time_to_event
  incidence.dens <- nrow(data[type_of_event == 1 & time_to_event <= tau]) / 
    sum(ifelse(time <= tau, time, tau))
  ae <- 1 - exp(-incidence.dens * tau)

  var_A_var <- nrow(data[type_of_event == 1 & time_to_event <= tau]) / 
    sum(ifelse(time <= tau, time, tau)) ^ 2
  ae_var <- exp(-incidence.dens * tau) ^ 2 * var_A_var * tau ^ 2

  res <- c("ae_prob" = ae, "ae_prob_var" = ae_var)
  return(res)
}

# compute 1 - Kaplan-Meier
oneMinusKaplanMeier <- function(data, tau){

  if(nrow(data[type_of_event == 1]) == 0){
    ae_prob <- 0
    ae_prob_var <- 0
  }

  if(nrow(data[type_of_event == 1]) > 0){
    help <- data.frame(id = data$id)
    help$from <- 0
    help$to <- ifelse(data$type_of_event != 1, "cens", data$type_of_event)
    help$time <-ifelse(data$time_to_event == 0, 0.001, data$time_to_event)

    tra <- matrix(FALSE, 2, 2)
    tra[1, 2] <- TRUE
    state.names <-as.character(0:1)
    etmmm <-etm(help, state.names, tra, "cens", s = 0)

    ae_prob <- summary(etmmm)[[2]][sum(summary(etmmm)[[2]]$time <= tau),]$P
    ae_prob_var <- summary(etmmm)[[2]][sum(summary(etmmm)[[2]]$time <= tau),]$var
  }

  res <- c("ae_prob" = ae_prob, "ae_prob_var" = ae_prob_var)
  return(res)
}

# compute Aalen-Johansen estimator
AJE <- function(data, CE, tau){

  data[, type_of_event2 := ifelse(CE == 2 & data$type_of_event == 3, 0, 
                                  ifelse(CE == 3 & data$type_of_event == 3, 2, type_of_event))]
  time <- data$time_to_event
  type2 <- data$type_of_event2
  
  # conditions
  c1 <- nrow(data[type_of_event2 == 1])
  c2 <- nrow(data[type_of_event2 == 2])
  
  if(c1 == 0){
   ae_prob <- 0
   ae_prob_var <- 0
  }

  if(c2 == 0){
    ce_prob <- 0
    ce_prob_var <- 0
  }

  # define auxiliary objects
  help <- data.frame(id = data$id)
  help$from <- 0
  help$time <-ifelse(time == 0, 0.001, time)
  tra <- matrix(FALSE, 2, 2)
  tra[1, 2] <- TRUE
  state.names <- as.character(0:1)
  
  if(c1 == 0 & c2 != 0){
    help$to <- ifelse(type2 != 2, "cens", type2 - 1)
    etmmm <- etm(help, state.names, tra, "cens", s = 0)
    setmm <- summary(etmmm)[[2]]
    ce_prob <- setmm[sum(setmm$time <= tau),]$P
    ce_prob_var <- setmm[sum(setmm$time <= tau),]$var
  }

  if(c1 != 0 & c2 == 0){
    help$to <- ifelse(type2 != 1, "cens", type2)
    etmmm <- etm(help, state.names, tra, "cens", s = 0)
    setmm <- summary(etmmm)[[2]]
   
    ae_prob <- setmm[sum(setmm$time <= tau),]$P
    ae_prob_var <- setmm[sum(setmm$time <= tau),]$var
  }

  if(c1 != 0 & c2 != 0){
    help$to <- ifelse(!(type2 %in% c(1, 2)),"cens", type2)

    tra <- matrix(FALSE, 3, 3)
    tra[1, 2:3] <- TRUE
    state.names <- as.character(0:2)
    etmmm <- etm(help, state.names, tra, "cens", s = 0)
    setmm <- summary(etmmm)
   
    ae_prob <- setmm[[2]][sum(setmm[[2]]$time <= tau),]$P
    ae_prob_var <- setmm[[2]][sum(setmm[[2]]$time <= tau),]$var

    ce_prob <- setmm[[3]][sum(setmm[[3]]$time <= tau),]$P
    ce_prob_var <- setmm[[3]][sum(setmm[[3]]$time <= tau),]$var
  }

  res_ae <- c("ae_prob" = ae_prob, "ae_prob_var" = ae_prob_var)
  res_ce <- c("ce_prob" = ce_prob, "ce_prob_var" = ce_prob_var)
  
  res <- rbind(res_ae, res_ce)
  return(res)
}


## ---- include=TRUE, echo=TRUE-------------------------------------------------

# sample size
N <- 200

# support of uniform censoring distribution
min.cens <- 0
max.cens <- 1000

# hazards for the three event types
haz.AE <- 0.00265
haz.death <- 0.00151
haz.soft <- 0.00227

# generate dataset
dat1 <- data_generation_constant_cens(N, min.cens, max.cens, haz.AE, haz.death, haz.soft, seed = 2020)

# compute tau
tau <- max(dat1[, "time_to_event"])


## ---- include=TRUE, echo=TRUE-------------------------------------------------
kable(head(dat1, 10), align = c("crcr"))


## ---- include=TRUE, echo=TRUE-------------------------------------------------

# compute each estimator
IP <- incidenceProportion(dat1, tau)
ID <- probTransIncidenceDensity(dat1, tau)
KM <- oneMinusKaplanMeier(dat1, tau)
AJ2 <- AJE(dat1, CE = 2, tau)
AJ3 <- AJE(dat1, CE = 3, tau)

# display
tab <- rbind(IP, ID, KM, AJ2, AJ3)
colnames(tab) <- c("estimated AE probability", "variance of estimation")
rownames(tab) <- c("incidence proportion", "incidence density", "1 - Kaplan-Meier", 
                   "Aalen-Johansen (death only), AE risk", "Aalen-Johansen (death only), CE risk",
                   "Aalen-Johansen (all CEs), AE risk", "Aalen-Johansen (all CEs), CE risk")
kable(tab, digits = c(3, 5))
