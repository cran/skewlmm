#main functions from skewlmm package - SMSN-LMM
smsn.lmm <- function(data,formFixed,groupVar,formRandom=~1,depStruct = "UNC", timeVar=NULL,
                     distr="sn",pAR=1,luDEC=10,
                     tol=1e-6,max.iter=200,calc.se=TRUE,lb=NULL,lu=NULL,
                     initialValues =list(beta=NULL,sigma2=NULL,D=NULL,lambda=NULL,phi=NULL,nu=NULL),
                     quiet=FALSE,showCriterium=FALSE) {
  if (class(formFixed)!="formula") stop("formFixed must be a formula")
  if (class(formRandom)!="formula") stop("formRandom must be a formula")
  if (!is.list(initialValues)) stop("initialValues must be a list")
  if (all(c("D","dsqrt") %in% names(initialValues))) initialValues$dsqrt<-NULL
  if (any(!(names(initialValues) %in% c("beta","sigma2","D","lambda","phi","nu")))) warning("initialValues must be a list with named elements beta, sigma2, D, lambda, phi and/or nu, elements with other names are ignored")
  #
  if (!is.character(groupVar)) stop("groupVar must be a character containing the name of the grouping variable in data")
  if (!is.null(timeVar)&!is.character(timeVar)) stop("timeVar must be a character containing the name of the time variable in data")
  if (length(formFixed)!=3) stop("formFixed must be a two-sided linear formula object")
  if (!is.data.frame(data)) stop("data must be a data.frame")
  if (length(class(data))>1) data=as.data.frame(data)
  vars_used<-unique(c(all.vars(formFixed),all.vars(formRandom),groupVar,timeVar))
  vars_miss <- which(!(vars_used %in% names(data)))
  if (length(vars_miss)>0) stop(paste(vars_used[vars_miss],"not found in data"))
  data = data[,vars_used]
  #
  if (!is.factor(data[,groupVar])) data[,groupVar]<-as.factor(data[,groupVar])
  x <- model.matrix(formFixed,data=data)
  y <-data[,all.vars(formFixed)[1]]
  z<-model.matrix(formRandom,data=data)
  ind <-data[,groupVar]
  data$ind <-data[,groupVar]
  m<-nlevels(ind)#n_distinct(ind)
  if (m<=1) stop(paste(groupVar,"must have more than 1 level"))
  p<-ncol(x)
  q1<-ncol(z)
  if ((sum(is.na(x))+sum(is.na(z))+sum(is.na(y))+sum(is.na(ind)))>0) stop ("NAs not allowed")
  if (!is.null(timeVar) & sum(is.na(data[,timeVar]))) stop ("NAs not allowed")
  #
  if (distr=="ssl") distr<-"ss"
  if (!(distr %in% c("sn","st","ss","scn"))) stop("Accepted distributions: sn, st, ssl, scn")
  if ((!is.null(lb))&distr!="sn") if((distr=="st"&(lb<=1))|(distr=="ss"&(lb<=.5))) stop("Invalid lb")
  if (is.null(lb)&distr!="sn") lb = ifelse(distr=="scn",rep(.01,2),ifelse(distr=="st",1.01,.51))
  if (is.null(lu)&distr!="sn") lu = ifelse(distr=="scn",rep(.99,2),ifelse(distr=="st",100,50))
  #
  if (depStruct=="ARp" & !is.null(timeVar) & ((sum(!is.wholenumber(data[,timeVar]))>0)|(sum(data[,timeVar]<=0)>0))) stop("timeVar must contain positive integer numbers when using ARp dependency")
  if (depStruct=="ARp" & !is.null(timeVar)) if (min(data[,timeVar])!=1) warning("consider using a transformation such that timeVar starts at 1")
  if (depStruct=="CI") depStruct = "UNC"
  if (!(depStruct %in% c("UNC","ARp","CS","DEC","CAR1"))) stop("accepted depStruct: UNC, ARp, CS, DEC or CAR1")
  #
  if (is.null(initialValues$beta)|is.null(initialValues$sigma2)|is.null(initialValues$lambda)|is.null(initialValues$D)) {
    lmefit = try(lme(formFixed,random=formula(paste('~',as.character(formRandom)[length(formRandom)],
                                                    '|',"ind")),data=data),silent=T)
    if (class(lmefit)=="try-error") {
      lmefit = try(lme(formFixed,random=~1|ind,data=data),silent=TRUE)
      if (class(lmefit)=="try-error") {
        stop("error in calculating initial values")
      } else {
        lambdainit <- rep(3,q1)*sign(as.numeric(skewness(random.effects(lmefit))))
        D1init <- diag(q1)*as.numeric(var(random.effects(lmefit)))
      }
    } else {
      lambdainit <- sign(as.numeric(skewness(random.effects(lmefit))))*3
      D1init <- (var(random.effects(lmefit)))
    }
  }
  if (!is.null(initialValues$beta)) {
    beta1 <- initialValues$beta
  } else beta1 <- as.numeric(lmefit$coefficients$fixed)
  if (!is.null(initialValues$sigma2)) {
    sigmae <- initialValues$sigma2
  } else sigmae <- as.numeric(lmefit$sigma^2)
  if (!is.null(initialValues$D)) {
    D1 <- initialValues$D
  } else D1 <- D1init
  if (!is.null(initialValues$lambda)) {
    lambda <- initialValues$lambda
  } else lambda <- lambdainit
  #
  if (length(D1)==1 & !is.matrix(D1)) D1=as.matrix(D1)
  #
  if (length(beta1)!=p) stop ("wrong dimension of beta")
  if (length(lambda)!=q1) stop ("wrong dimension of lambda")
  if (!is.matrix(D1)) stop("D must be a matrix")
  if ((ncol(D1)!=q1)|(nrow(D1)!=q1)) stop ("wrong dimension of D")
  if (length(sigmae)!=1) stop ("wrong dimension of sigma2")
  if (sigmae<=0) stop("sigma2 must be positive")
  #
  if (depStruct=="ARp") phiAR<- initialValues$phi
  if (depStruct=="CS") phiCS<- initialValues$phi
  if (depStruct=="DEC") parDEC<- initialValues$phi
  if (depStruct=="CAR1") phiCAR1<- initialValues$phi
  #
  nu = initialValues$nu
  #
  if (distr=="st"&is.null(nu)) nu=10
  if (distr=="ss"&is.null(nu)) nu=5
  if (distr=="scn"&is.null(nu)) nu=c(.05,.8)
  #
  if (distr=="st"&length(nu)!=1) stop ("wrong dimension of nu")
  if (distr=="ss"&length(nu)!=1) stop ("wrong dimension of nu")
  if (distr=="scn"&length(nu)!=2) stop ("wrong dimension of nu")
  ###
  if (depStruct=="UNC") obj.out <- EM.Skew(formFixed,formRandom,data,groupVar,distr,beta1,sigmae,D1,
                                          lambda,nu,lb,lu,precisao=tol,informa=calc.se,max.iter=max.iter,showiter=!quiet,showerroriter = (!quiet)&showCriterium)
  if (depStruct=="ARp") obj.out <- EM.SkewAR(formFixed,formRandom,data,groupVar,pAR,timeVar,
                                             distr,beta1,sigmae,phiAR,D1,lambda,nu,lb,lu,
                                             precisao=tol,informa=calc.se,max.iter=max.iter,showiter=!quiet,showerroriter = (!quiet)&showCriterium)
  if (depStruct=="CS") obj.out <-EM.SkewCS(formFixed,formRandom,data,groupVar,
                                           distr,beta1,sigmae,phiCS,D1,lambda,nu,lb,lu,
                                           precisao=tol,informa=calc.se,max.iter=max.iter,showiter=!quiet,showerroriter = (!quiet)&showCriterium)
  if (depStruct=="DEC") obj.out <-EM.SkewDEC(formFixed,formRandom,data,groupVar,timeVar,
                                             beta1,sigmae,D1,lambda,distr,nu,parDEC,lb,lu,luDEC,
                                             precisao=tol,informa=calc.se,max.iter=max.iter,showiter=!quiet,showerroriter = (!quiet)&showCriterium)
  if (depStruct=="CAR1") obj.out <-EM.SkewCAR1(formFixed,formRandom,data,groupVar,timeVar,
                                               distr,beta1,sigmae,phiCAR1,D1,lambda,nu,lb,lu,
                                               precisao=tol,informa=calc.se,max.iter=max.iter,showiter=!quiet,showerroriter = (!quiet)&showCriterium)
  obj.out$call <- match.call()

  npar<-length(obj.out$theta);N<-nrow(data)
  obj.out$criteria$AIC <- 2*npar-2*obj.out$loglik
  obj.out$criteria$BIC <- log(N)*npar - 2*obj.out$loglik
  obj.out$data = data
  obj.out$formula$formFixed=formFixed
  obj.out$formula$formRandom=formRandom
  obj.out$depStruct = depStruct
  if (distr=="ss") distr<-"ssl"
  obj.out$distr=distr
  obj.out$N = N
  obj.out$n = m#n_distinct(ind)
  obj.out$groupVar = groupVar
  obj.out$timeVar = timeVar
  #
  fitted <- numeric(N)
  ind_levels <- levels(ind)
  for (i in seq_along(ind_levels)) {
    seqi <- ind==ind_levels[i]
    xfiti <- matrix(x[seqi,],ncol=p)
    zfiti <- matrix(z[seqi,],ncol=q1)
    fitted[seqi]<- xfiti%*%obj.out$estimates$beta + zfiti%*%obj.out$random.effects[i,]
  }
  obj.out$fitted <- fitted

  class(obj.out)<- c("SMSN","list")
  obj.out
}

print.SMSN <- function(x,...){
  cat("Linear mixed models with distribution", x$distr, "and dependency structure",x$depStruct,"\n")
  cat("Call:\n")
  print(x$call)
  cat("\nFixed:")
  print(x$formula$formFixed)
  #print(x$theta)
  cat("Random:")
  print(x$formula$formRandom)
  cat("  Estimated variance (D):\n")
  D1 = Dmatrix(x$estimates$dsqrt)%*%Dmatrix(x$estimates$dsqrt)
  colnames(D1)=row.names(D1)= colnames(model.matrix(x$formula$formRandom,data=x$data))
  print(D1)
  cat("\nEstimated parameters:\n")
  if (!is.null(x$std.error)) {
    tab = round(rbind(x$theta,x$std.error),4)
    colnames(tab) = names(x$theta)
    rownames(tab) = c("","s.e.")
  }
  else {
    tab = round(rbind(x$theta),4)
    colnames(tab) = names(x$theta)
    rownames(tab) = c("")
  }
  print(tab)
  cat('\n')
  cat('Model selection criteria:\n')
  critFin <- c(x$loglik, x$criteria$AIC, x$criteria$BIC)
  critFin <- round(t(as.matrix(critFin)),digits=3)
  dimnames(critFin) <- list(c(""),c("logLik", "AIC", "BIC"))
  print(critFin)
  cat('\n')
  cat('Number of observations:',x$N,'\n')
  cat('Number of groups:',x$n,'\n')
}

summary.SMSN <- function(object,confint.level=.95,...){
  cat("Linear mixed models with distribution", object$distr, "and dependency structure",object$depStruct,"\n")
  cat("Call:\n")
  print(object$call)
  cat("\nDistribution", object$distr)
  if (object$distr!="sn") cat(" with nu =", object$estimates$nu,"\n")
  cat("\nRandom effects: ")
  print(object$formula$formRandom)
  cat("  Estimated variance (D):\n")
  D1 = Dmatrix(object$estimates$dsqrt)%*%Dmatrix(object$estimates$dsqrt)
  colnames(D1)=row.names(D1)= colnames(model.matrix(object$formula$formRandom,data=object$data))
  print(D1)
  cat("\nFixed effects: ")
  print(object$formula$formFixed)
  if (!is.null(object$std.error)) cat("with approximate confidence intervals\n")
  else cat(" (std errors not estimated)\n")
  p<-length(object$estimates$beta)
  if (!is.null(object$std.error)) {
    qIC <- qnorm(.5+confint.level/2)
    ICtab <- cbind(object$estimates$beta-qIC*object$std.error[1:p],
                  object$estimates$beta+qIC*object$std.error[1:p])
    tab = (cbind(object$estimates$beta,object$std.error[1:p],
                      ICtab))
    rownames(tab) = names(object$theta[1:p])
    colnames(tab) = c("Value","Std.error",paste0("CI ",confint.level*100,"% lower"),
                      paste0("CI ",confint.level*100,"% upper"))
  }
  else {
    tab = rbind(object$estimates$beta)
    colnames(tab) = names(object$theta[1:p])
    rownames(tab) = c("Value")
  }
  print(tab)
  cat("\nDependency structure:", object$depStruct)
  cat("\n  Estimate(s):\n")
  covParam <- c(object$estimates$sigma2, object$estimates$phi)
  if (object$depStruct=="UNC") names(covParam) <- "sigma2"
  else names(covParam) <- c("sigma2",paste0("phi",1:(length(covParam)-1)))
  print(covParam)
  cat("\nSkewness parameter estimate:", object$estimates$lambda)
  cat('\n')
  cat('\nModel selection criteria:\n')
  criteria <- c(object$loglik, object$criteria$AIC, object$criteria$BIC)
  criteria <- round(t(as.matrix(criteria)),digits=3)
  dimnames(criteria) <- list(c(""),c("logLik", "AIC", "BIC"))
  print(criteria)
  cat('\n')
  cat('Number of observations:',object$N,'\n')
  cat('Number of groups:',object$n,'\n')
  invisible(list(varRandom=D1,varFixed=covParam,tableFixed=tab,criteria=criteria))
}

fitted.SMSN <- function(object,...) object$fitted
ranef <- function(object) object$random.effects

predict.SMSN <- function(object,newData,...){
  if (missing(newData)) stop("newData must be a dataset containing the covariates, groupVar and timeVar (when used) from data that should be predicted")
  if (!is.data.frame(newData)) stop("newData must be a data.frame object")
  if (nrow(newData)==0) stop("newData can not be an empty dataset")
  dataFit <- object$data
  formFixed <- object$formula$formFixed
  formRandom <- object$formula$formRandom
  groupVar<-object$groupVar
  timeVar <- object$timeVar
  dataPred<- newData
  vars_used<-unique(c(all.vars(formFixed)[-1],all.vars(formRandom),groupVar,timeVar))
  vars_miss <- which(!(vars_used %in% names(newData)))
  if (length(vars_miss)>0) stop(paste(vars_used[vars_miss],"not found in newData"))
  depStruct <- object$depStruct
  if (any(!(dataPred[,groupVar] %in% dataFit[,groupVar]))) stop("subjects for which future values should be predicted must also be at fitting data")
  if (!is.factor(dataFit[,groupVar])) dataFit[,groupVar]<-as.factor(dataFit[,groupVar])
  if (!is.factor(dataPred[,groupVar])) dataPred[,groupVar]<-factor(dataPred[,groupVar],levels=levels(dataFit[,groupVar]))
  #
  if (object$distr=="ssl") object$distr<-"ss"
  #
  if (depStruct=="UNC") obj.out <- predictf.skew(formFixed,formRandom,dataFit,dataPred,groupVar,distr=object$distr,theta=object$theta)
  if (depStruct=="ARp") obj.out <- predictf.skewAR(formFixed,formRandom,dataFit,dataPred,groupVar,timeVar,distr=object$distr,
                                                  pAR=length(object$estimates$phi),theta=object$theta)
  if (depStruct=="CS") obj.out <-predictf.skewCS(formFixed,formRandom,dataFit,dataPred,groupVar,distr=object$distr,theta=object$theta)
  if (depStruct=="DEC") obj.out <-predictf.skewDEC(formFixed,formRandom,dataFit,dataPred,groupVar,timeVar,distr=object$distr,theta=object$theta)
  if (depStruct=="CAR1") obj.out <-predictf.skewCAR1(formFixed,formRandom,dataFit,dataPred,groupVar,timeVar,distr=object$distr,theta=object$theta)
  obj.out
}

errorVar<- function(times,object=NULL,sigma2=NULL,depStruct=NULL,phi=NULL) {
  if((!is.null(object))&(!inherits(object,c("SMSN","SMN")))) stop("object must inherit from class SMSN or SMN")
  if (is.null(object)&is.null(depStruct)) stop("object or depStruct must be provided")
  if (is.null(object)&is.null(sigma2)) stop("object or sigma2 must be provided")
  if (is.null(depStruct)) depStruct<-object$depStruct
  if (depStruct=="CI") depStruct = "UNC"
  if (depStruct!="UNC" & is.null(object)&is.null(phi)) stop("object or phi must be provided")
  if (!(depStruct %in% c("UNC","ARp","CS","DEC","CAR1"))) stop("accepted depStruct: UNC, ARp, CS, DEC or CAR1")
  if (is.null(sigma2)) sigma2<-object$estimates$sigma2
  if (is.null(phi)&depStruct!="UNC") phi<-object$estimates$phi
  if (depStruct=="ARp" & (any(!is.wholenumber(times))|any(times<=0))) stop("times must contain positive integer numbers when using ARp dependency")
  if (depStruct=="ARp" & any(tphitopi(phi)< -1|tphitopi(phi)>1)) stop("AR(p) non stationary, choose other phi")
  #
  if (depStruct=="UNC") var.out<- sigma2*diag(length(times))
  if (depStruct=="ARp") var.out<- sigma2*CovARp(phi,times)
  if (depStruct=="CS") var.out<- sigma2*CovCS(phi,length(times))
  if (depStruct=="DEC") var.out<- sigma2*CovDEC(phi[1],phi[2],times)
  if (depStruct=="CAR1") var.out<- sigma2*CovDEC(phi,1,times)
  var.out
}

rsmsn.lmm <- function(time1,x1,z1,sigma2,D1,beta,lambda,depStruct="UNC",phi=NULL,distr="sn",nu=NULL) {
  if (length(D1)==1 & !is.matrix(D1)) D1=as.matrix(D1)
  q1 = nrow(D1)
  p = length(beta)
  if (ncol(as.matrix(x1))!=p) stop("incompatible dimension of x1/beta")
  if (ncol(as.matrix(z1))!=q1) stop ("incompatible dimension of z1/D1")
  if (length(lambda)!=q1) stop ("incompatible dimension of lambda/D1")
  if (!is.matrix(D1)) stop("D must be a matrix")
  if ((ncol(D1)!=q1)|(nrow(D1)!=q1)) stop ("wrong dimension of D")
  if (length(sigma2)!=1) stop ("wrong dimension of sigma2")
  if (sigma2<=0) stop("sigma2 must be positive")
  Sig <- errorVar(time1,depStruct = depStruct,sigma2=sigma2,phi=phi)
  #
  if (distr=="ssl") distr<-"ss"
  if (!(distr %in% c("sn","st","ss","scn"))) stop("Invalid distribution")
  if (distr=="sn") {ui=1; c.=-sqrt(2/pi)}
  if (distr=="st") {ui=rgamma(1,nu/2,nu/2); c.=-sqrt(nu/pi)*gamma((nu-1)/2)/gamma(nu/2)}
  if (distr=="ss") {ui=rbeta(1,nu,1); c.=-sqrt(2/pi)*nu/(nu-.5)}
  if (distr=="scn") {ui=ifelse(runif(1)<nu[1],nu[2],1);
                      c.=-sqrt(2/pi)*(1+nu[1]*(nu[2]^(-.5)-1))}
  #if (all(lambda==0)) c.=0
  delta = lambda/as.numeric(sqrt(1+t(lambda)%*%(lambda)))
  Delta = matrix.sqrt(D1)%*%delta
  Gammab = D1 - Delta%*%t(Delta)
  Xi = matrix(x1,ncol=p)
  Zi = matrix(z1,ncol=q1)
  Beta = matrix(beta,ncol=1)
  ti = c.+abs(rnorm(1,0,ui^-.5))
  bi = t(rmvnorm(1,Delta*ti,sigma=ui^(-1)*Gammab))
  Yi = t(rmvnorm(1,Xi%*%Beta+Zi%*%bi,sigma=ui^(-1)*Sig))
  if (all(Xi[,1]==1)) Xi = Xi[,-1]
  if (all(Zi[,1]==1)) Zi = Zi[,-1]
  return(data.frame(time=time1,y=Yi,x=Xi,z=Zi))
}

lr.test <- function(obj1,obj2,level=0.05,quiet=FALSE) {
  if (!all(c(class(obj1)[1],class(obj2)[1])%in%c("SMN","SMSN"))) stop("obj1 and obj2 should be smsn.lmm or smn.lmm objects")
  if (level<=0 | level>=1) stop("0<level<1 needed")
  if (obj1$N!=obj2$N) stop("obj1 and obj2 should refer to the same data set")
  if (obj1$n!=obj2$n) stop("obj1 and obj2 should refer to the same data set")
  npar1 <- length(obj1$theta)
  npar2 <- length(obj2$theta)
  #
  if (!quiet) {
    cat('\nModel selection criteria:\n')
    criteria <- rbind(c(obj1$loglik, obj1$criteria$AIC, obj1$criteria$BIC),
                      c(obj2$loglik, obj2$criteria$AIC, obj2$criteria$BIC))
    criteria <- round((as.matrix(criteria)),digits=3)
    dimnames(criteria) <- list(c(deparse(substitute(obj1)),deparse(substitute(obj2))),
                               c("logLik", "AIC", "BIC"))
    print(criteria)
    cat("\n")
  }
  if (npar1==npar2) {
    warning("obj1 and obj2 do not contain nested models with different number of parameters")
    return(invisible(NULL))
  }
  if (npar1<npar2) {objB <- obj2;objS<-obj1} else {objB <- obj1;objS<-obj2}
  if (objB$depStruct=='DEC') {
    names(objB$theta)[substr(names(objB$theta), 1, 3)=='phi'] = 'phi1'
    names(objB$theta)[substr(names(objB$theta), 1, 5)=='theta'] = 'phi2'
  }
  if (objS$depStruct =="ARp" | objS$depStruct =="CAR1") names(objS$theta)[substr(names(objS$theta), 1, 3)=='phi'] = paste0('phi',1:length(objS$estimates$phi))
  if (objB$depStruct =="ARp") names(objB$theta)[substr(names(objB$theta), 1, 3)=='phi'] = paste0('phi',1:length(objB$estimates$phi))
  if (!all(names(objS$theta)%in%names(objB$theta))) {
    warning("obj1 and obj2 do not contain nested models")
    return(invisible(NULL))
  }
  if ((objB$loglik-objS$loglik)<=0) {
  stop("logLik from model with more parameters is not bigger than the one
  with less parameters. This probably indicates problems on convergence,
  try changing the initial values and/or maximum number of iteration")
  }
  lrstat <- 2*(objB$loglik-objS$loglik)
  pval <- pchisq(lrstat,df=abs(npar1-npar2),lower.tail = FALSE)
  if (!quiet) {
    cat("    Likelihood-ratio Test\n\n")
    cat("chi-square statistics = ",lrstat,"\n")
    cat("df = ",abs(npar1-npar2),"\n")
    cat("p-value = ",pval,"\n")
    if (pval<=level) cat("\nThe null hypothesis that both models represent the \ndata equally well is rejected at level ",level)
    else cat("\nThe null hypothesis that both models represent the \ndata equally well is not rejected at level ",level)
    }
  invisible(list(statistic=lrstat,p.value=pval,df=abs(npar1-npar2)))
}
