# version: v01.00
# Author: Joey/Jiaoyan Huang
# Contact: jhuang@sonomatech.com
# Created: 07/21/2020
# The code is modified from Leimng Zhang's code described in Atmos. Chem. Phys., 3, 2067-2082, 2003
# A revised parameterization for gaseous dry deposition in air-quality models
# Zhang et al., 2002a Atmospheric Environment 36 (2002) 537-560 
# Modelling gaseous dry deposition in AURAMS: a unified regional air-quality modelling system
# Zhang et al., 2001 Atmospheric Environment 35 (2001) 549}560
# A size-segregated particle dry deposition scheme for an atmospheric aerosol module
# please check all TODO lines

# TODO overall JH 20200814
# 1. separate gas and aerosol dry deposition velocity but they are sharing the same Ra in line 173
# 2. differet size bins? currently the script can only handle a single particle size
# 3. pressure correction, I've applied the correction for vapor pressure, but not sure diffusivity 
# please check all lines contain TODO 
# when you add a comment or edit lines, please add your initial and date
# also, please do not delete the orginal lines in case we need it later

library(readxl)
# library(here) here seems not working well under gitbash condistion

#functions
# Define the function for saturation vapor pressure (mb)
ES <- function(TEMP, PRESS){
  ES <- 6.108*exp(17.27*(TEMP - 273.16)/(TEMP - 35.86)) * PRESS/101325
  return(ES)
} 

# site info
GLAT_d <- 78.9
GLON_d <- -11.9
GLAT   <- GLAT_d/180*pi
GLON   <- GLON_d/180*pi
LUC    <- 22 # please see related data
z2 <- 10


# species info
MW <- 271 #g/mole
RM <- 100
ALPHA <- 2 # scaling factor
BETA  <- 2 # scaling factor
# Alpha and Beta please see ZHang et al., 2003 and Lyman et al., 2007 SI
# Zhang et al., 2003 outline a method for choosing scaling parameters for any
# chemical species of interest based on the effective Henry's Law constant (H*) and the
# negative log of electron activity for half-redox reactions in neutral solutions [pe0(W)]. In
# this study, H* for HgCl2 and Hg(OH)2 were calculated using available data (5, 37). For
# calculation of H* for HgCl2, [Cl-] was assumed to be 0.2 mg L-1, a typical value for
# continental rainwater (38). pe0(W) was calculated for the half-redox reaction.
# The calculated values for H* and pe0(W) were used to compare
# RGM to gaseous species listed in Zhang et al. (23), and, based on evident similarity, the
# scaling parameters listed for nitrous acid (HONO) were used to scale Rg and Rcut for
# RGM (?? = ?? = 2).
Dp <- 0.68 # paritcle diameter
RHOP <- 1200  #1769 was used in Zhang et al 2001, but I feel 1200 make more sense to normal aerosol particle density kg/m3

# data availabilty
USTAR_provided <- TRUE #see line 154

setwd("C:/Users/jhuang/Dry_Depo_multi_res_model")  #where you download the repo
# MET_file <- "C:/Users/jhuang/Desktop/JH other projects/Zepplin_GOMdrydepo_2019_so_V2.xlsx"
source("Hg_dry_depo_related_data.R")
MET_file <- "Zepplin_GOMdrydepo_2019_so_V2.xlsx"
MET_data <- read_excel(MET_file,1)
MET_data$IYR <- as.numeric(substring(MET_data$time,1,4))
MET_data$IMO <- as.numeric(substring(MET_data$time,6,7))
MET_data$ID <- as.numeric(substring(MET_data$time,9,10))
MET_data$IH <- as.numeric(substring(MET_data$time,12,13))
MET_data$JD <- as.numeric(format(MET_data$time,"%j"))

#calculate solar zenith angle, COSZEN Cosine of solar zenith angle, this impacts the stomatal resistence
MET_data$declin <- asin(sin(23.5*pi/180)*sin((MET_data$JD-81)*2*pi/365))
MET_data$short1 <- sin(GLAT)*sin(MET_data$declin)
MET_data$short2 <- cos(GLON)*cos(MET_data$declin)
MET_data$cosze <- (as.numeric(MET_data$IH)-12)*pi/12
MET_data$coszen <- MET_data$short1+MET_data$short2*cos(MET_data$cosze)
MET_data$RH <- MET_data$rh

#interpolate LAI, LAI data
MET_data$LAI_F  = LAI[MET_data$IMO,LUC]+ MET_data$ID/ 30.5 * (LAI[MET_data$IMO,LUC]-LAI[MET_data$IMO+1,LUC])

#calculate ES=saturation vapor pressure (mb) at 2 m and at soil surface
# MET_data$ES2= 6.108*exp(17.27*(MET_data$t2m - 273.16)/(MET_data$t2m - 35.86))
# MET_data$ESS= 6.108*exp(17.27*(MET_data$skt - 273.16)/(MET_data$skt - 35.86))
MET_data$ES2= 6.108*exp(17.27*(MET_data$t2m - 273.16)/(MET_data$t2m - 35.86)) * MET_data$sp/101325 #consider the atmospheric pressure
MET_data$ESS= 6.108*exp(17.27*(MET_data$skt - 273.16)/(MET_data$skt - 35.86)) * MET_data$sp/101325 #consider the atmospheric pressure
MET_data$u2_adjusted <- 0
for (r in nrow(MET_data)){
  #Set minimum wind speed as 1.0 m/s, due to wind speed measurement uncertainties, this can be changed to another reasonable number
  MET_data$u2_adjusted[r] = max(MET_data$u2[r],1)
}
#Potential temperature at reference height Z2 
MET_data$T2P = MET_data$t2m + z2 * 0.0098

# calculating friction velocity and stability related varibles
# for water surfaces (LUC 1, 3), z0 is a function of wind speed
# water LUC
if(LUC == 1 | LUC == 3){
  E <- MET_data$RH * MET_data$ES2
  Q <- 0.622 *E/(MET_data$sp-E)
  T2PV <- MET_data$T2P * (1 +0.61*Q)
  E <- MET_data$ESS
  QS <- 0.622 *E/(MET_data$sp-E)
  TSV <- MET_data$skt * (1 +0.61*QS)
  DTHV <- (T2PV - TSV)
  CUN <- 7.5E-4+6.7E-5*MET_data$u2
  EL <- 9999
  n <- which(abs(DTHV) > 1.0E-6)
  EL[n] <- T2PV[n]*CUN[n]^1.5*MET_data$u2[n]^2/(5.096E-3*DTHV[n])
  n <- which(EL >0 & EL < 5)
  EL[n] <- 5
  n <- which(EL <0 & EL > -5)
  EL[n] <- -5
  ZL = z2/EL
  ZL10m=10./EL
  PSIT <- array(0,length(ZL))
  PSIU <- array(0,length(ZL))
  rm(X)
  rm(Y)
  for(r in 1:length(ZL)){
    if(ZL[r] < 0){
      X <- (1.0 - 15.0*ZL[r])^0.25
      PSIU[r] <- 2*log(0.5*(1+X))+log(0.5*(1+X*X))-2*atan(X) + 0.5*3.1415926
      Y <- sqrt(1 - 9*ZL[r])
      PSIT[r] <- 2*0.74*log((1+Y)/2)
    }else{
      PSIU[r] <- -4.7*ZL[r]
      PSIT[r] <- PSIU[r]
    }
  }

  MET_data$Z0_F <- 0.000002 * MET_data$u2^2.5
  MET_data$USTAR = 0.4* MET_data$u2/(log(z2/MET_data$Z0_F) - PSIU)
  MET_data$THSTAR = 0.4*(MET_data$T2P- MET_data$skt)/(0.74*log(z2/MET_data$Z0_F)-PSIT)
}else{
  if(Z02[LUC] > Z01[LUC]){
    MET_data$Z0_F <- Z01[LUC]+(MET_data$LAI_F-min(LAI[,LUC]))/(max(LAI[,LUC])-min(LAI[,LUC]))*(Z02[LUC]-Z01[LUC])
  }else{
    MET_data$Z0_F <- Z01[LUC] 
  }
  MET_data$RIB <- 9.81*z2*(MET_data$T2P - MET_data$skt)/(MET_data$skt*MET_data$u2^2)
  MET_data$RIB[which(MET_data$ssr > 0 & MET_data$RIB > 0)] <- 1E-15
  DELTAT <-  MET_data$T2P - MET_data$skt
  DELTAT[which(abs(DELTAT) <= 1E-10)] <- 1E-10 #TODO JH 20200814 need double check
  TBAR <- 0.5*(MET_data$T2P + MET_data$skt)
  RATIOZ <- z2/MET_data$Z0_F
  ASQ <- 0.16/log(RATIOZ)^2
  MET_data$FM <- 0
  MET_data$FH <- 0
  for(r in 1:length(MET_data$RIB)){
    if(MET_data$RIB[r] <= 0){
      AA <- ASQ[r]*9.4*sqrt(RATIOZ[r])
      CM <- 7.4*AA
      CH <- 5.3*AA
      MET_data$FM[r] <- 1 - (9.4*MET_data$RIB[r]/(1. + CM*sqrt(abs(MET_data$RIB[r]))))
      MET_data$FH[r] <- 1 - (9.4*MET_data$RIB[r]/(1. + CH*sqrt(abs(MET_data$RIB[r]))))
    }else{
      MET_data$FM[r] <- 1/((1 + 4.7*MET_data$RIB[r])^2)
      MET_data$FH[r] <- MET_data$FM[r]
    }
  }
  MET_data$USTARSQ <- ASQ*MET_data$u2^2*MET_data$FM
  MET_data$UTSTAR  <- ASQ*MET_data$u2^2*MET_data$FH*DELTAT/0.74
  MET_data$USTAR   <- sqrt(MET_data$USTARSQ)
  MET_data$THSTAR  <- MET_data$UTSTAR/MET_data$USTAR
  EL = TBAR*MET_data$USTARSQ/(0.4*9.81*MET_data$THSTAR)
  n <- which(EL >0 & EL < 5)
  EL[n] <- 5
  n <- which(EL <0 & EL > -5)
  EL[n] <- -5
  ZL = z2/EL
  ZL10m=10./EL
}
#selct USTAR from your data
if(USTAR_provided){
  MET_data$USTAR <- MET_data$zust
}
# TODO JH 20200814
# Also Dr Zhang suggests in Forest LCU, when USTAR < 0.5 use 0.5 especially for those MET data measured in a forest
# Aerodynamic resistance above canopy
MET_data$Ra <- 0
# for ZL >= 0
n <- which(ZL >= 0)
MET_data$Ra[n] <- (.74*log(z2/MET_data$Z0_F[n])+4.7*ZL[n])/0.4/MET_data$USTAR[n]
# for ZL < 0
n <- which(ZL < 0)
MET_data$Ra[n] <- 0.74/0.4/MET_data$USTAR[n]*(log(z2/MET_data$Z0_F[n])-2*log((1+sqrt(1-9.*ZL[n]))*0.5))
MET_data$Ra[which(MET_data$Ra < 5.0)] <- 5.0
if(LUC == 1 | LUC == 3){
  n <- which(MET_data$Ra > 2000)
  MET_data$Ra[n] <- 2000
}else{
  n <- which(MET_data$Ra > 1000)
  MET_data$Ra[n] <- 1000
}

# Only calculate stomatal resistance if there is solar radiation, 
# leaf area index is not zero, and within reasonable temperature range
RDU <- RDV <- WW1 <- WW2 <- WW <- RDM <- RDN <- RV <- RN <- array(0,nrow(MET_data))
RATIO <- SV <- FV1 <- FV <- PARDIR <- PARDIF <- array(0,nrow(MET_data))

n <- which(MET_data$ssrd >= 0.1 & MET_data$skt < (tmax[LUC] + 273.15) &  MET_data$skt > tmin[LUC] + 273.15 
           & MET_data$LAI_F[r] > 0.001 & MET_data$coszen > 0.001)
RDU[n] <- 600*exp(-0.185/MET_data$coszen[n])*MET_data$coszen[n]
RDV[n] <- 0.4*(600-RDU[n])*MET_data$coszen[n]
WW1[n] <- -log(MET_data$coszen[n])/2.302585
WW2[n] <- -1.195+0.4459*WW1[n]-0.0345*WW1[n]^2
WW[n] <- 1320*10**WW2[n]
RDM[n] <- (720.*exp(-0.06/MET_data$coszen[n])-WW[n])*MET_data$coszen[n]
RDN[n] <- 0.6*(720-RDM[n]-WW[n])*MET_data$coszen[n]
RV <- RDU+RDV 
RV[which(RV < 0.1)] <- 0.1
RN <- RDM + RDN
RN[which(RN < 0.01)] <- 0.01
RATIO[n] <- MET_data$ssrd[n]/(RV[n]+RN[n])
RATIO[which(RATIO < 0.9)] <- 0.9
SV[n] <- RATIO[n]*RV[n]                       # Total PAR 
FV1 <-  (0.9-RATIO)/0.7
FV1[which(FV1 < 0.99)] <- 0.99
FV[n] <- RDU[n]/RV[n]*(1.0-FV1[n]^0.6667)
FV[which(FV < 0.01)] <- 0.01                  # fraction of PAR in the direct beam 
PARDIR[n]=FV[n]*SV[n]                         # PAR from direct radiation 
PARDIF[n]=SV[n]-PARDIR[n]                     # PAR from diffuse radiation

# Calculate sunlight and shaded leaf area, PAR for sunlight and shaded leaves 
PSHAD <- PSUN <- RSHAD <- RSUN <- GSHAD <- GSUN <- FSUN <- FSHAD <- array(0,nrow(MET_data))
n <- which(MET_data$LAI_F > 2.5 & MET_data$ssrd > 200)
PSHAD[n] <- PARDIF[n]*exp(-0.5*MET_data$LAI_F[n]^0.8) + 0.07*PARDIR[n]*(1.1-0.1*MET_data$LAI_F[n])*exp(-MET_data$coszen[n])
PSUN[n] <- PARDIR[n]^0.8*0.5/MET_data$coszen[n] + PSHAD[n]
n <- which(MET_data$LAI_F <= 2.5 | MET_data$ssrd <= 200)
PSHAD[n] <- PARDIF[n]*exp(-0.5*MET_data$LAI_F[n]^0.7) + 0.07*PARDIR[n]*(1.1-0.1*MET_data$LAI_F[n])*exp(-MET_data$coszen[n])
PSUN[n] <- PARDIR[n]*0.5/MET_data$coszen[n] + PSHAD[n]

RSHAD <- RSmin[LUC]+BRS[LUC]*RSmin[LUC]/PSHAD 
RSUN  <- RSmin[LUC]+BRS[LUC]*RSmin[LUC]/PSUN
GSHAD <- 1/RSHAD
GSUN  <- 1/RSUN
FSUN  <- 2*MET_data$coszen*(1-exp(-0.5*MET_data$LAI_F/MET_data$coszen))  # Sunlight leaf area 
FSHAD <- MET_data$LAI_F-FSUN                                             # Shaded leaf area 

# Stomatal conductance before including effects of temperature, 
# vapor pressure defict and water stress.

GSPAR <- FSUN * GSUN + FSHAD * GSHAD  

# function for temperature effect, in R T means TRUE, so I changed T to Temp
Temp <- MET_data$skt - 273.15      
BT <- (tmax[LUC] - topt[LUC])/(tmax[LUC] - tmin[LUC])
GT <- (tmax[LUC]-Temp)/(tmax[LUC] - topt[LUC])
GT <- GT^BT
GT <- GT*(Temp-tmin[LUC])/(topt[LUC]-tmin[LUC]) 

# function for vapor pressure deficit 
ES_skt <- ES(MET_data$skt, MET_data$sp)
D0 <- ES_skt*(1 - MET_data$RH)/10           # kPa 
GD <- 1 -BVPD[LUC]*D0

# function for water stress 
PSI <- (-0.72-0.0013*MET_data$ssrd)
GW  <- (PSI-PSI2[LUC])/(PSI1[LUC]-PSI2[LUC])
GW[which(GW > 1)] <- 1
GW[which(GW < 0.1)] <- 0.1
GD[which(GD > 1)] <- 1
GD[which(GD < 0.1)] <- 0.1

# Set a big value for stomatal resistance when stomata are closed
RST <- array(99999.9,nrow(MET_data))
# Stomatal resistance for water vapor 
n <- which(MET_data$ssrd >= 0.1 & MET_data$skt < (tmax[LUC] + 273.15) &  MET_data$skt > tmin[LUC] + 273.15 
           & MET_data$LAI_F[r] > 0.001 & MET_data$coszen > 0.001)
RST[n]=1.0/(GSPAR[n]*GT[n]*GD[n]*GW[n]) 
n <- which(GSUN == 0 | GSHAD ==0)
RST[n] <- 99999.9
RST[is.na(RST)] <- 99999.9
# RST[which(RST > 99999.9)] <- 99999.9 #TODO JH 20200814 not sure a upper limit is needed  
# we are seeing about 70% data RST were replcaed by 99999.9, it is not way to off, 
# Nevada's simulation, we usually see 50%

# check if dew or rain occurs.
WST <- array(0,nrow(MET_data))
dewcode <- array(0,nrow(MET_data))
dewcode[which(MET_data$tcc < 0.25)] <- 0.3
dewcode[which(MET_data$tcc >= 0.25 & MET_data$tcc < 0.75)] <- 0.2
dewcode[which(MET_data$tcc >= 0.75)] <- 0.1
DQ <- 0.622/1000 * ES_skt*(1 - MET_data$RH )*1000
DQ[which(DQ < 0.0001)] <- 0.0001
USmin <- 1.5/DQ*dewcode
# TODO JH 20200814 not sure which dew check we should use
dew <- array(FALSE,nrow(MET_data))
dew[which(MET_data$t2m > 273.15 & (MET_data$UTSTAR - USmin) >0)] <- TRUE
# dew[which((MET_data$d2m - MET_data$t2m) > 0)] <- TRUE
rain <- array(FALSE,nrow(MET_data))
rain[which(MET_data$t2m > 273.15 & MET_data$tp > 0)] <- TRUE # TODO JH 20200814 use site specific number not 0.2
n <- which((dew == T | rain == T) & MET_data$ssrd > 200)
WST[n] <- (MET_data$ssrd[n] - 200)/800
WST[which(WST > 0.5)] <- 0.5

# In-canopy aerodynamic resistance 
Rac <- Rac1[LUC]+(MET_data$LAI_F-min(LAI[,LUC]))/(max(LAI[,LUC])-min(LAI[,LUC])+1.E-10)*(Rac2[LUC]-Rac1[LUC]) 
Rac <- Rac*MET_data$LAI_F^0.25/MET_data$USTAR/MET_data$USTAR 

# Ground resistance for O3 
RgO_F <- array(RgO[LUC],nrow(MET_data))
if( LUC == 4){
  for(r in 1:nrow(MET_data)){
    if(MET_data$skt[r] < 272.15){
      tmp1 <- RgO[LUC] * exp(0.2*(272.15- MET_data$skt[r]))
      tmp2 <- RgO[LUC]*2
      RgO_F[r] <- min(tmp1,tmp2)
    }
  }
}

# Ground resistance for SO2 
RgS_F <- array(RgS[LUC],nrow(MET_data))
if(LUC == 2){
  RgS_F <-RgS[LUC] * (275.15 - MET_data$skt)
  RgS_F[which(RgS_F > 500)] <- 500
  RgS_F[which(RgS_F < 100)] <- 100
}else if(LUC == 4){
  for(r in 1:nrow(MET_data)){
    if(rain[r] == TRUE){
      RgS_F[r] <- 50
    }else if(dew[r] == TRUE){
      RgS_F[r] <- 100
    }else{
      RgS_F[r] <- RgS[LUC]
    }
  }
}

# Cuticle resistance for O3 AND SO2  
RcutO_F <- array(0,nrow(MET_data))
RcutS_F <- array(0,nrow(MET_data))
if(RcutdO[LUC] <= -1){
  RcutO_F <- 1.E25 
  RcutS_F <- 1.E25 
}else{
  for(r in 1:nrow(MET_data)){
    if(rain[r] == TRUE){
      RcutO_F[r] = RcutwO[LUC]/MET_data$LAI_F[r]^0.5/MET_data$USTAR[r] 
      RcutS_F[r] = 50/MET_data$LAI_F[r]^0.5/MET_data$USTAR[r] 
      RcutS_F[r] <- max(RcutS_F[r],20) 
    }else if(dew[r] == TRUE){
      RcutO_F[r] = RcutwO[LUC]/MET_data$LAI_F[r]^0.5/MET_data$USTAR[r] 
      RcutS_F[r] = 100/MET_data$LAI_F[r]^0.5/MET_data$USTAR[r] 
      RcutS_F[r] <- max(RcutS_F[r],20) 
    }else if(MET_data$skt[r] <272.15){
      RcutO_F[r] <- RcutdO[LUC]/exp(3*MET_data$RH[r])/MET_data$LAI_F[r]^0.25/MET_data$USTAR[r]
      RcutS_F[r] <- RcutdS[LUC]/exp(3*MET_data$RH[r])/MET_data$LAI_F[r]^0.25/MET_data$USTAR[r] 
      RcutO_F[r] <- min(RcutO_F[r]*2, RcutO_F[r] * exp(0.2*(272.15- MET_data$skt[r]))) 
      RcutS_F[r] <- min(RcutS_F[r]*2, RcutS_F[r] * exp(0.2*(272.15- MET_data$skt[r]))) 
      RcutO_F[r] <- max(RcutO_F[r],100.) 
      RcutS_F[r] <- max(RcutS_F[r],100.) 
    }else{
      RcutO_F[r] <- RcutdO[LUC]/exp(3*MET_data$RH[r])/MET_data$LAI_F[r]^0.25/MET_data$USTAR[r]
      RcutS_F[r] <- RcutdS[LUC]/exp(3*MET_data$RH[r])/MET_data$LAI_F[r]^0.25/MET_data$USTAR[r] 
      RcutO_F[r] <- max(RcutO_F[r],100) 
      RcutS_F[r] <- max(RcutS_F[r],100) 
    }
  }
}

# If snow occurs, Rg and Rcut are adjusted by snow cover fraction
fsnow <- MET_data$sd/sdmax[LUC]
fsnow[which(fsnow > 1)] <- 1  #snow cover fraction for leaves 
RsnowS <- array(0,nrow(MET_data))
if(LUC == 4){
  for(r in 1:nrow(MET_data)){
    if(fsnow[r] > 0.0001){
      RsnowS[r] <- min(70*(275.15- MET_data$skt[r]), 500) 
      RsnowS[r] <- max(RSnowS[r], 100)
      RcutS_F[r] <- 1/((1-fsnow[r])/RcutS_F[r] + fsnow[r]/RsnowS[r]) 
      RcutO_F[r] <- 1/((1-fsnow[r])/RcutO_F[r] + fsnow[r]/2000)
      fsnowg <- min(1, fsnow[r]*2)   #snow cover fraction for ground 
      RgS_F[r] <- 1/((1-fsnowg)/RgS_F[r]+fsnowg/RsnowS[r]) 
      RgO_F[r] <- 1/((1-fsnowg)/RgO_F[r]+fsnowg/2000.) 
    }
  }
}

# Calculate diffusivity for each gas species
# dir density and water vapor density
# TODO JH 20200814
# I feel diffusivity is related to atmospheric pressure, but cannot find a simple equation to adjust the number
dair <- 0.369*29 + 6.29  
dh2o <- 0.369*18 + 6.29
dgas <- 0.369*MW+6.29  
DI <- 0.001*MET_data$skt^1.75*sqrt((29+MW)/MW/29)      
DI <- DI/1/(dair^0.3333+dgas^0.3333)^2    
VI <- 145.8*1.E-4*(MET_data$skt*0.5+MET_data$t2m*0.5)^1.5/(MET_data$skt*0.5+MET_data$t2m*0.5+110.4)

# Calculate quasi-laminar resistance 
Rb  <- 5/MET_data$USTAR*(VI/DI)^0.666667   

# Calculate stomatal resistance for each species from the ratio of
# diffusity of water vapor to the gas species
# RM please check Modelling Gaseous Dry Deposition in AURAMS A Unified Regional
# Air-quality Modelling System, Atmos. Environ GOM can be 0 or 100 dependent on species and GEM is 500
DVh2o <- 0.001*MET_data$skt^1.75*sqrt((29+18)/29/18)
DVh2o <- DVh2o/(dair^0.3333+dh2o^0.3333)^2
RS <- RST*DVh2o/DI + RM #double check this 

# Scale cuticle and ground resistances for each species 
Rcut <- 1/(ALPHA/RcutS_F+BETA/RcutO_F)
Rg <- 1/(ALPHA/RgS_F+BETA/RgO_F)

# Calculate total surface resistance  
Rc <- (1-WST)/RS+1./(Rac+Rg)+1/Rcut 
# Set minimum surface resistance as 10 s/m 
for(r in 1:nrow(Rc)){
  if(is.na(Rc[r])){
   Rc[r] <- 10 
  }else if(1/Rc[r] > 10){
    Rc[r] <- 1/Rc[r]
  }else{
    Rc[r] <- 10
  }
}
# Deposition velocity 
MET_data$Rb <- Rb
MET_data$Rc <- Rc
MET_data$VDF = 1/(MET_data$Ra+MET_data$Rb+MET_data$Rc) # m/s

# particulate dry deposition
# Atmospheric chemsitry and physics Seinfeld and Pandis 1998 page 909
# parameters for air dynamic properties 
AA1 <- 1.257
AA2 <- 0.4
AA3 <- 1.1
AMFP <- 6.53E-8
ROAROW <- 1.19
BOLTZK <- 1.3806044503487214E-23
# AIR'S DYNAMIC VISCOSITY
AMU <- 145.8*1.E-8*MET_data$t2m^1.5/(MET_data$t2m+110.4) # Zhang et al., 2001
# AMU_test <- 1.8E-5*(MET_data$t2m/298)^0.85 # Seinfeld and Pandis
# AIR'S KINEMATIS VISCOSITY
ANU=AMU/ROAROW
#lamda  = 0.0651 at 1atm and 298K
lamda <- 0.0651 * (MET_data$t2m/298)^0.5
Cc <- 1+2*lamda/Dp*(1.257+0.4*exp(-0.55*Dp/lamda)) 
DIp <- 1.38E-23*MET_data$t2m*Cc/(3*pi*AMU*0.00000068)#particle diffusivity
PLLP <- PLLP2[LUC] -(MET_data$LAI_F-min(LAI[,LUC]))/(max(LAI[,LUC])-min(LAI[,LUC])+1.E-10)*(PLLP2[LUC]-PLLP1[LUC])

# CUNNINGHAM SLIP CORRECTION FACTOR AND RELAXATION TIME = vg/Grav.
PRII <- 2./9.*9.81/AMU
PRIIV <- PRII*(RHOP-ROAROW)
VPHIL <- 0
CFAC <- 1+ AMFP/(Dp/2)*(AA1+AA2*exp(-AA3*Dp/2/AMFP)) #TODO JH 20200814 we don't use aerosol bin, so radius  = Dp/2
TAUREL <- PRIIV*(Dp*1E-6/2)^2*CFAC/9.81 #Dp into meter
TAUREL[which(TAUREL < 0)] <- 0

# STOKES FRICTION AND DIFFUSION COEFFICIENTS.
AMOB <- 6*pi*AMU*(Dp/2)/CFAC
DIFF <- BOLTZK*MET_data$t2m/AMOB
SCHM <- ANU/DIFF

# GRAVITATIONAL SETTLING VELOCITY.
PDEPV <- TAUREL*9.81

# Efficiency by diffusion, impaction, interception and particle rebound.
St <- array(0,nrow(MET_data))
for(r in 1:nrow(MET_data)){
  if(PLLP[r] <= 0){
    St[r] <- TAUREL[r] * MET_data$UTSTAR[r]^2/ANU[r]
  }else{
    St[r] <- TAUREL[r] * MET_data$USTAR[r]/PLLP[r]*1000
  }
}
EB <- SCHM^(-gama[LUC]) 
EIM <- (St/(St+AEST[LUC]))^2
EIN <- array(0,nrow(MET_data))
for(r in 1:nrow(MET_data)){
  if(PLLP[r] > 0){
    EIN[r] <- (1000*2*(Dp/2)/PLLP)^2*0.5 
  }
}
R1 <- exp(-St^0.5)
R1[which(R1 < 0.5)] <- 0.5
MET_data$Rs <- 1/3/MET_data$USTAR/(EB+EIM+EIN)/R1

# Deposition velocity 
MET_data$VDSIZE <- PDEPV + 1/(MET_data$Ra+MET_data$Rs) #m/s