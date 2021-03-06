## Build ensemble density provided weights, mean, and sd
## activity best fits were in log space
if (Sys.info()["sysname"] == "Darwin") j_drive <- "/Volumes/snfs"
if (Sys.info()["sysname"] == "Linux") j_drive <- "/home/j"
if (Sys.info()["sysname"] == "Windows") j_drive <- "J:"
user <- Sys.info()[["user"]]

## load distribution functions
source(paste0(j_drive,"/temp/",user,"/GBD_2016/calc_paf/parallel/ihmeDistList.R"))
## dlist is the universe of distribution families as defined in the above code
## classA is the majority of families, classB is scaled beta, classM is the mirror family of distributions
dlist <- c(classA,classB,classM)

library(dplyr)
library(data.table)
library(compiler)
library(fitdistrplus)
library(sfsmisc)

Rcpp::sourceCpp(paste0(j_drive,"/temp/",user,"/GBD_2016/calc_paf/scale_density_simpson.cpp"))

get_edensity_activity <- function(weights,mean,sd) {
  W_ <- weights
  M_ <- mean
  S_ <- sd
  
  mu <- log(M_/sqrt(1+(S_^2/(M_^2))))
  sdlog <- sqrt(log(1+(S_^2/M_^2)))
  
  XMIN <- qlnorm(.00001,mu,sdlog)
  XMAX <- qlnorm(.999,mu,sdlog)
  
  xx = seq(20,50000,length=1000)
  xx = log(xx)
  
  fx = 0*xx

  W_ = W_[which(W_>0)]
  
  buildDENlist <- function(jjj) {
    distn = names(W_)[[jjj]]
    EST <- NULL
    LENGTH <- length(formals(unlist(dlist[paste0(distn)][[1]]$mv2par)))
    if (LENGTH==4) {
      EST <- try(unlist(dlist[paste0(distn)][[1]]$mv2par(M_, (S_^2), XMIN=XMIN, XMAX=XMAX)),silent=T)
    } else {
      EST <- try(unlist(dlist[paste0(distn)][[1]]$mv2par(M_, (S_^2))),silent=T)
    }
    d.dist <- NULL
    d.dist <- try(dlist[paste0(distn)][[1]]$dF(xx,EST),silent=T)
    if (class(EST)=="numeric" & class(d.dist)=="numeric") {
      dEST <- EST
      dDEN <- d.dist
      weight <- W_[[jjj]]
    }
    else {
      dEST <- 0
      dDEN <- 0
      weight <- 0
    }
    dDEN[!is.finite(dDEN)] <- 0
    return(list(dDEN=dDEN,weight=weight))
  }
  denOUT <- suppressWarnings(lapply(1:length(W_),buildDENlist))
  
  ## re-scale weights
  TW = unlist(lapply(denOUT, function(x) (x$weight)))
  TW = TW/sum(TW,na.rm = T)
  fx <- Reduce("+",lapply(1:length(TW),function(jjj) denOUT[[jjj]]$dDEN*TW[jjj]))
  fx <- unlist(fx)
  fx[!is.finite(fx)] <- 0
  fx[length(fx)] <- 0
  fx[1] <- 0
  
  ## scale so integral is 1
  ## but operate in 0-1 space so integral approximation isn't in a number space that overflows
  dennspace = ((fx - min(fx,na.rm=T)) / (max(fx,na.rm=T) - min(fx,na.rm=T))) * (20 - 10) + 0
  integ <- integrate.xy(xx,dennspace)
  dOUT <- dennspace/integ

  return(list(fx=dOUT,x=xx,XMIN=XMIN,XMAX=XMAX))
  
}

get_edensity_activity<-cmpfun(get_edensity_activity)
