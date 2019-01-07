# These functions are to draw posterior samples using MCMC for SDS likelihood in subsection 4.2 
#    and Algorithm 5.1 


# This function solves the ODE in Eq. (2.7) and step 3 in Algorithm 5.1
# inata: descrete time of an individual. This values are came from Sellke epidemic data 
# Tmax: cutoff time of epidemic
# dt: time increment of ODE 
# beta, gamma: present values of beta and gamma at the present step at MCMC
# ic: initial values of ODE set to c(1.0, rho, 0.0), rho set the 
#     present values of beta and gamma at the present step at MCMC

SIR.ODE <- function(indata = ti, Tmax = T.max, dt = 0.01, beta, gamma, ic) {
  p <- length(ic)
  n <- Tmax/dt
  xmat <- matrix(0, ncol = (p + 1), nrow = (n + 1))
  x <- ic
  xmat[1, ] <- c(0, x)
  jj <- 1
  for (i in 2:(n + 1)) {
    x <- x + c(-beta * x[1] * x[2], beta * x[1] * x[2] - gamma * x[2], 
               gamma * x[2]) * dt
    xmat[i, 2:(p + 1)] <- x
    xmat[i, 1] <- xmat[(i - 1), 1] + dt
  }
  k <- length(indata)
  SI_ti <- matrix(0, nrow = k, ncol = 2)
  for (i in 1:k) {
    for (j in jj:nrow(xmat)) {
      if (indata[i] <= xmat[j, 1]) {
        SI_ti[i, 1:2] <- xmat[j, 2:3]
        jj <- j
        break
      }
    }
  }
  return(SI_ti)
}


# Likelihood function for Eq. (4.3)
# SI_ti: return values from SIR.ODE() function. 
# p.m: values of beta, gamma, rho
# delta: duration of infectious period
# n.num: number of susecptible
# nz.num: number of removed among initially susceptible individual
# returning likelihood 


llikelihood <- function(SI_ti, p.m, delta.t = delta, n.num = n, nz.num = nz) {
  k <- nrow(SI_ti)
  n <- n.num
  delta <- delta.t
  lik.gamma <- nz.num * log(p.m[2]) - p.m[2] * sum(delta)
  lik <- sum(log(SI_ti[, 1])) + sum(log(SI_ti[, 2])) + k * log(p.m[1]) + 
    lik.gamma + (n - k) * log(SI_ti[k, 1])
  return(lik)
}


# This function generates posterior samples of beta, gamma, and rho using MCMC based 
#   on SDS likelihood in subsection 4.2
# in.data:  input data set, must be a form of sellke empidemic 
# Tmax: cutoff time of epidemic
# nrepeat: number of iteration of MCMC 
# ic: initial value of beta, gamma, and rho
# tun: tunning constant for proposal distribution of beta, gamma, rho 
# prior.a: hyper shape parameter of gamma prior for beta, gamma, rho
# prior.b: hyper rate parameter of gamma prior for beta, gamma, rho
# returning posterior samples of beta, gamma, rho 
# This function uses RAM method via adapt_S() function from ramcmc R-package


SDS.Likelihood.MCMC <- function(data = in.data, Tmax, nrepeat = 1000, 
                            tun, prior.a, prior.b, ic = c(k1, k2, k3)) {
  T.max <- Tmax
  n <- length(which(data[, 1] != 0))
  delta <- c(subset((data[, 2] - data[, 1]), ((data[, 1] < (T.max - 1e-10)) & 
            (data[, 2] < (T.max - 1e-10)))), subset((T.max - data[, 1]), 
            ((data[,1] < (T.max - 1e-10)) & (data[, 2] >= (T.max)))))
  nz <- length(subset((data[, 2] - data[, 1]), ((data[, 1] < (T.max - 1e-10)) & 
              (data[, 2] < (T.max - 1e-10)))))
  ti <- subset(data[, 1], ((data[, 1] > 0) & (data[, 1] < (T.max - 1e-10))))
  burn <- 1000
  parm.m <- ic
  parm.star <- parm.m
  
  theta <- matrix(0, nrow = nrepeat, ncol = 3)
  count <- 0
  S <- diag(3)
  for (rep in 1:nrepeat) {
    repeat {
      u <- mvrnorm(1, c(0, 0, 0), diag(c(tun[1], tun[2], tun[3])))
      parm.star <- parm.m + S %*% u
      if ((min(parm.star) > 0) & (parm.star[3] < 1)) {
        tau <- uniroot(function(x) 1 - x - exp(-parm.star[1]/parm.star[2] * 
                         (x + parm.star[3])), c(0, 1))$root
        if ((tau > 0) & (tau < 1)) 
          break
      }
    }
    sir.m <- SIR.ODE(indata = ti, Tmax = T.max, beta = parm.m[1], gamma = parm.m[2], 
                     ic = c(1, parm.m[3], 0))
    sir.star <- SIR.ODE(indata = ti, Tmax = T.max, beta = parm.star[1], 
                     gamma = parm.star[2], ic = c(1, parm.star[3], 0))
    l.lik.m <- llikelihood(SI_ti = sir.m, p.m = parm.m, n.num = n, 
                     delta.t = delta, nz.num = nz)
    l.lik.star <- llikelihood(SI_ti = sir.star, p.m = parm.star, n.num = n, 
                     delta.t = delta, nz.num = nz)
    alpha <- exp(l.lik.star - l.lik.m 
                 + dgamma(parm.star[1], prior.a[1], prior.b[1], log = T) 
                 - dgamma(parm.m[1], prior.a[1], prior.b[1], log = T)
                 + dgamma(parm.star[2], prior.a[2], prior.b[2], log = T) 
                 - dgamma(parm.m[2], prior.a[2], prior.b[2], log = T) 
                 + dgamma(parm.star[3], prior.a[3], prior.b[3], log = T) 
                 - dgamma(parm.m[3], prior.a[3], prior.b[3],   log = T))
    alpha <- min(alpha, 1)
    if (!is.nan(alpha) && runif(1) < alpha) {
      parm.m <- parm.star
      count <- count + 1
    }
    S <- ramcmc::adapt_S(S, u, alpha, rep, gamma = min(1, (3 * rep)^(-2/3)))
    theta[rep, ] <- parm.m
    if (rep%%100 == 0) 
      cat("0")   
  }
  print(count/nrepeat)
  return(theta)
}