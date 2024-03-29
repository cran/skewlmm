\name{rsmsn.clmm}
\alias{rsmsn.clmm}
%- Also NEED an '\alias' for EACH other topic documented here.
\title{Generate data from SMSN-CLMM with censored responses
  %%  ~~function to do ... ~~
}
\description{
  It creates a simulated data set from SMSN-CLMM with several possible dependence structures, with an established censoring rate or a fixed limit of detectation (LOD).
}
\usage{
  rsmsn.clmm(time, ind, x, z, sigma2, D, beta, lambda=rep(0, nrow(D)),
             depStruct="UNC", phi=NULL, distr="norm", nu=NULL, type="left",
             pcens=0.10, LOD=NULL)
}
%- maybe also 'usage' for other objects documented here.
\arguments{
  \item{time}{Vector of length \eqn{N} containing times that should be used in data generation, where \eqn{N} indicates the total number of observations.}
  \item{ind}{Vector of length \eqn{N} containing the variable which represents the subjects or groups.}
  \item{x}{Design matrix for fixed effects of dimension \eqn{N\times p}.}
  \item{z}{Design matrix for random effects of dimension \eqn{N \times q}.}
  \item{sigma2}{Common variance parameter, such that \eqn{\Sigma=\sigma^2*R}.}
  \item{D}{Variance matrix for random effects.}
  \item{beta}{Vector of fixed effects parameter.}
  \item{lambda}{Skewness parameter of random effects.}
  \item{depStruct}{Dependence structure. \code{"UNC"} for conditionally uncorrelated (\code{"CI"} is also accepted), \code{"ARp"} for AR(p) -- p is \code{length(phi)}--, \code{"CS"} for compound symmetry, \code{"DEC"} for DEC, \code{"CAR1"} for continuous-time AR(1), and \code{"MA1"} for moving average of order 1.}
  \item{phi}{Parameter vector indexing the dependence structure.}
  \item{distr}{Distribution that should be used. \code{"norm"} for normal, \code{"t"} for Student-t, \code{"sn"} for skew-normal, and \code{"st"} for skew-t.}
  \item{nu}{Degrees of freedom for Student-t and skew-t distributions. It must be greater than 2.}
  \item{type}{\code{left} for left censoring and \code{right} for right censoring.}
  \item{pcens}{Desired censoring rate.}
  \item{LOD}{Desired limit of detectation. If \code{LOD} is provided, then \code{pcens} will be discarded.}
}
\value{
  A data frame containing time, the variable indicating groups (\code{ind}), the generated response variable (\code{y}), the censoring indicator variable (\code{ci}), the lower censoring limit (\code{lcl}), the upper censoring limit (\code{ucl}), and possible covariates.
}
\references{
Matos, L. A., Prates, M. O., Chen, M. H., and Lachos, V. H. (2013). Likelihood-based inference for mixed-effects models with censored response using the multivariate-t distribution. Statistica Sinica 23(3), 1323-1345.

Lachos, V. H., A. Matos, L., Castro, L. M., and Chen, M. H. (2019). Flexible longitudinal linear mixed models for multiple censored responses data. Statistics in medicine, 38(6), 1074-1102.
}
\author{
  Fernanda L. Schumacher, Larissa A. Matos, Victor H. Lachos and Katherine L. Valeriano
}
\seealso{
  \code{\link{smn.clmm}}
  %% ~~objects to See Also as \code{\link{help}}, ~~~
}
\examples{
library(ggplot2)

# Generating a sample for m=25 individuals with 5 times
nj1 = 5
m = 25
time = rep(1:nj1, times=m)
groups = as.factor(rep(1:m, each=nj1))

# Considering 10\% of right censoring responses and normal distribution
dat1 = rsmsn.clmm(time, groups, cbind(1,time), rep(1,m*nj1), sigma2=.25,
                  D=0.5*diag(1), beta=c(1,2), depStruct="ARp", phi=0.5,
                  type="right")
head(dat1)
ggplot(dat1, aes(x=x, y=y, group=ind)) + geom_line() +
  stat_summary(aes(group=1), geom="line", fun=mean, col="blue", size=1.5) +
  geom_line(aes(x=x,y=lcl), color="red", linetype="dashed")

# Considering LOD=4, left censoring, and Student-t distribution
dat2 = rsmsn.clmm(time, groups, cbind(1,time), rep(1,m*nj1), sigma2=.25,
                  D=0.5*diag(1), beta=c(1,2), depStruct="CS", phi=0.2,
                  distr="t", nu=4, LOD=4)
mean(dat2$ci) #censoring rate
ggplot(dat2, aes(x=x, y=y, group=ind)) + geom_line() +
  stat_summary(aes(group=1), geom="line", fun=mean, col="blue", size=1.5) +
  geom_line(aes(x=x,y=ucl), color="red", linetype="dashed")
}
% Add one or more standard keywords, see file 'KEYWORDS' in the
% R documentation directory.
\keyword{datagen}% use one of  RShowDoc("KEYWORDS")
