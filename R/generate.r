

## Unexported local functions

generate.ESS<- function(x, ctrl, projdat2, sc_df){
  
  # projdat stuff for which no ESS is specified
  projdat_noess <- projdat2[is.element(projdat2$fishery, sc_df$fishery[is.na(sc_df$ess)]),]
  # projdat stuff with an ESS to be applied to length comps
  projdat_ess_l <- projdat2[is.element(projdat2$fishery, sc_df$fishery[!is.na(sc_df$ess)]) & 
                              is.element(projdat2$fishery, sc_df$fishery[sc_df$length]),]
  # projdat stuff with an ESS to be applied to weight comps
  projdat_ess_w <- projdat2[is.element(projdat2$fishery, sc_df$fishery[!is.na(sc_df$ess)]) & 
                              is.element(projdat2$fishery, sc_df$fishery[sc_df$weight]),]
  # add length and weight frequency data to the frq
  lengths <- seq(lf_range(x)["LFFirst"], by=lf_range(x)["LFWidth"], length=lf_range(x)["LFIntervals"])
  weights <- seq(lf_range(x)["WFFirst"], by=lf_range(x)["WFWidth"], length=lf_range(x)["WFIntervals"])
  
  projdat_ess_ll <- as.data.frame(lapply(projdat_ess_l, rep, each=length(lengths)))
  projdat_ess_ww <- as.data.frame(lapply(projdat_ess_w, rep, each=length(weights)))
  projdat_ess_ll$length <- lengths
  projdat_ess_ww$weight <- weights
  
  projdat2      <- rbind(projdat_noess, projdat_ess_ll, projdat_ess_ww)
  projdat2$freq <- 0
  
  for(ff in 1:n_fisheries(x))
    projdat2[projdat2$length==lf_range(x)["LFFirst"] & projdat2$fishery==ff,'freq'] <- ess(ctrl)[ff]
  
  return(projdat2)
}









#' generate
#'
#' generates modified input files for mfcl.
#' Currently works when projection years are scaled by a single reference year.
#' Use of mulitple reference years eg.2008:2012 may cause problems.
#'
#' @param x:    Either an object of class MFCLFrq or of class MFCLPar.
#' @param y:    Eitehr an object of class MFCLprojCtrl or MFCLPar as generated by makepar.
#'
#' @param ... Additional argument list that might not ever
#'  be used.
#'
#' @return Modified input file in accordance with projection settings.
#' 
#' @seealso \code{\link{projCtrl}} 
#' 
#' @export
#' @docType methods
#' @rdname generate-methods
#'
#' @examples
#' generate(MFCLFrq(), MFCLprojControl())
#' generate(MFCLPar(), MFCLPar())

setGeneric('generate', function(x, y, ...) standardGeneric('generate')) 



#' @rdname generate-methods
#' @aliases generate

setMethod("generate", signature(x="MFCLFrq", y="MFCLprojControl"), 
         function(x, y, ...){
            
            ctrl     <- y
            proj.yrs <- seq(range(x)['maxyear']+1, range(x)['maxyear']+nyears(ctrl))
            qtrs     <- sort(unique(freq(x)$month))
            
            week   <- rev(freq(x)$week)[1]
            if(!all(freq(x)$week==week))
              warning("Differences in week not accounted for in projection frq")
            
            if(length(caeff(ctrl))>1 & length(caeff(ctrl))!=n_fisheries(x))
              stop("Error: caeff values do not match number of fisheries")
            if(length(scaler(ctrl))>1 & length(scaler(ctrl))!=n_fisheries(x))
              stop("Error: scaler values do not match number of fisheries")
            
            sc_df <- data.frame(fishery=1:n_fisheries(x), caeff  = caeff(ctrl), scaler = scaler(ctrl), ess=ess(ctrl), 
                                length=tapply(freq(x)$length, freq(x)$fishery, function(tt){any(!is.na(tt))}), 
                                weight=tapply(freq(x)$weight, freq(x)$fishery, function(tt){any(!is.na(tt))}))
            
            avdata <- freq(x)[is.element(freq(x)$year, avyrs(ctrl)) & is.na(freq(x)$length) & is.na(freq(x)$weight) ,]
            avdata <- rbind(avdata, freq(x)[is.element(freq(x)$year, avyrs(ctrl)) & freq(x)$length %in% lf_range(x)['LFFirst'] ,],
                                    freq(x)[is.element(freq(x)$year, avyrs(ctrl)) & freq(x)$weight %in% lf_range(x)['WFFirst'] ,])
            avdata <- avdata[!duplicated(avdata[,1:7]),] # remove duplicates that can occur if you have both length and wgt freq data
            
            avdata$catch[avdata$catch == -1] <- NA
            avdata$effort[avdata$effort == -1] <- NA
            
            flts     <- as.numeric(colnames(tapply(avdata$catch,  list(avdata$month, avdata$fishery), sum)))
            avcatch  <- sweep(tapply(avdata$catch,  list(avdata$month, avdata$fishery), sum), 2, sc_df$scaler[flts], "*")
            aveffort <- sweep(tapply(avdata$effort, list(avdata$month, avdata$fishery), sum), 2, sc_df$scaler[flts], "*")
            
            projdat  <- data.frame(year    = rep(proj.yrs, each=(length(flts)*length(qtrs))),
                                   month   = qtrs,
                                   week    = week,
                                   fishery = rep(rep(flts, each=length(qtrs)), nyears(ctrl)),
                                   catch   = c(avcatch), 
                                   effort  = c(aveffort),
                                   penalty = -1.0, length=NA, weight=NA, freq=-1)
            
            # remove records with missing values from projection years
            projdat2 <- rbind(projdat[is.element(projdat$fishery, sc_df[sc_df$caeff==1, 'fishery']) & !is.na(projdat$catch),],
                              projdat[is.element(projdat$fishery, sc_df[sc_df$caeff==2, 'fishery']) & !is.na(projdat$effort),])
            
            # set the penalty to 1.0 for those fisheries with standardised CPUE -- maybe ?
            std.fish <- seq(1:n_fisheries(x))[tapply(freq(x)$penalty, freq(x)$fishery, mean)>0]
            projdat2$penalty[is.element(projdat2$fishery, std.fish)] <- 1.0
            
            # set catch/effort to -1 for fisheries projected on effort/catch
            projdat2[is.element(projdat2$fishery, sc_df[sc_df$caeff==1, 'fishery']),'effort'] <- -1
            projdat2[is.element(projdat2$fishery, sc_df[sc_df$caeff==2, 'fishery']),'catch'] <- -1
            
            ## STOCHASTIC PROJECTIONS WITH ESS
            # if an ESS is specified - include length composition data and set first value to ESS
            if(!all(is.na(ess(ctrl)))){
              projdat2 <- generate.ESS(x, ctrl, projdat2, sc_df)
            }

            freq(x) <- rbind(freq(x), projdat2)
            
            data_flags(x)[2,] <- as.numeric(max(avyrs(ctrl)))+1
            data_flags(x)[3,] <- as.numeric(qtrs[1])
            lf_range(x)['Datasets'] <- lf_range(x)['Datasets']+nrow(projdat2)
            slot(x,'range')['maxyear']     <- max(freq(x)$year)
            
            return(x)
          })

    






#' @rdname generate-methods
#' @aliases generate

setMethod("generate", signature(x="MFCLPar", y="MFCLPar"), 
          function(x, y, ...){
     
     # set stochastic recruitment flags
     if(flagval(x, 1, 232)$value == 0)
       flagval(x, 1, 232) <- recPeriod(x, af199=flagval(x, 2, 199)$value, af200=flagval(x, 2, 200)$value)['pf232']
     if(flagval(x, 1, 233)$value == 0)
       flagval(x, 1, 233) <- recPeriod(x, af199=flagval(x, 2, 200)$value, af200=flagval(x, 2, 200)$value)['pf233']
     
     
     proj.yrs <- dimnames(rel_rec(y))[[2]][!is.element(dimnames(rel_rec(y))[[2]], dimnames(rel_rec(x))[[2]])]
       
     rep_rate_dev_coffs(x) <- rep_rate_dev_coffs(y)
     fm_level_devs(x)      <- fm_level_devs(y)
     
     q_dev_coffs(x)        <- q_dev_coffs(y)
     sel_dev_coffs(x)      <- sel_dev_coffs(y)
     sel_dev_coffs2(x)     <- sel_dev_coffs2(y)
     growth_devs_cohort(x) <- growth_devs_cohort(y)
     unused(x)             <- unused(y)
     lagrangian(x)         <- lagrangian(y)
     
     eff_dev_coff_incs     <- unlist(lapply(effort_dev_coffs(y),length)) - unlist(lapply(effort_dev_coffs(x),length))
     effort_dev_coffs(x)   <- lapply(1:dimensions(x)["fisheries"], function(g) c(effort_dev_coffs(x)[[g]], rep(0, eff_dev_coff_incs[g])))
     
#     catch_dev_coffs(x)    <- lapply(1:dimensions(x)["fisheries"], function(g) c(catch_dev_coffs(x)[[g]], 
#                                                    rep(0, length(rep_rate_dev_coffs(y)[[g]])-length(catch_dev_coffs(x)[[g]]))))
     
     catch_dev_coffs(x)    <- lapply(1:length(catch_dev_coffs(x)), 
                                     function(g) c(catch_dev_coffs(x)[[g]], rep(0, length(proj.yrs)*dimensions(x)['seasons'])))
     
     region_rec_var(x)     <- window(region_rec_var(x), start=range(x)['minyear'], end=range(y)['maxyear'])
     region_rec_var(x)[is.na(region_rec_var(x))] <- 0
     
     rel_rec(x) <- window(rel_rec(x), start=range(x)['minyear'], end=range(y)['maxyear'])
     rel_rec(x)[,proj.yrs] <- rel_rec(y)[,proj.yrs] 
    
     
     dimensions(x)         <- dimensions(y)
     range(x)              <- range(y)
     
     return(x)
            
})



