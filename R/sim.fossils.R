#' Simulate fossils under a Poisson sampling model
#'
#' @description
#' Fossils can be simulated for a phylo (\code{tree}) or taxonomy (\code{taxonomy}) object.
#' If both are specified, the function uses taxonomy.
#' If no taxonomic information is provided, the function assumes all speciation is symmetric (i.e. bifurcating, \code{beta = 1}).
#' A vector of rates can be specified to allow for rate variation across lineages.
#' If a vector is provided, each entry will apply to each unique species in the order in which they appear in the taxonomy object (if taxonomy is provided),
#' or to each unique edge in the order in which they appear in the tree object.
#' If the tree object has a root edge (\code{root.edge}), the first entry in the rates vector should correspond to this edge.
#'
#' @param rate A single Poisson sampling rate or a vector of rates.
#' @param tree Phylo object.
#' @param taxonomy Taxonomy object.
#' @param fossils Append fossils to to an existing fossils object.
#' @param ignore.taxonomy Ignore species taxonomy (returns sp = NA). Default = FALSE.
#' @param root.edge If TRUE include the root edge. Default = TRUE.
#'
#' @return An object of class fossils.
#'
#' @examples
#' # simulate tree
#' t <- ape::rtree(6)
#'
#' # simulate fossils using the tree
#' rate <- 2
#' f <- sim.fossils.poisson(rate, tree = t)
#' plot(f, t)
#'
#' # simulate fossils using taxonomy
#' s <- sim.taxonomy(t, 0.5, 1, 0.5)
#' f <- sim.fossils.poisson(rate, taxonomy = s)
#' plot(f, t)
#'
#' # simulate fossils with autocorrelated rate variation across lineages
#' rates <- sim.trait.values(init = rate, taxonomy = s, v = 1)
#' f <- sim.fossils.poisson(rates, taxonomy = s)
#' plot(f, t)
#'
#' # append fossils to an existing fossils object
#' rate <- 1
#' f1 <- sim.fossils.poisson(rate, tree = t)
#' plot(f1, t)
#' rate <- 2
#' f2 <- sim.fossils.poisson(rate, tree = t, fossils = f1)
#' plot(f2, t)
#' f3 <- sim.fossils.poisson(rate, tree = t, fossils = f2, ignore.taxonomy = TRUE)
#' plot(f3, t, show.unknown = TRUE)
#'
#' @keywords Poisson sampling
#' @seealso \code{\link{sim.fossils.intervals}}, \code{\link{sim.fossils.environment}}, \code{\link{sim.trait.values}}
#' @export
#'
#' @importFrom stats rpois runif rlnorm na.omit
sim.fossils.poisson <- function(rate, tree = NULL, taxonomy = NULL, fossils = NULL, ignore.taxonomy = FALSE,
                                root.edge = TRUE) {
  if (is.null(tree) && is.null(taxonomy)) {
    stop("Specify phylo or taxonomy object")
  }

  if (!is.null(tree) && !"phylo" %in% class(tree)) {
    stop("tree must be an object of class \"phylo\"")
  }

  if (!is.null(taxonomy) && !"taxonomy" %in% class(taxonomy)) {
    stop("taxonomy must be an object of class \"taxonomy\"")
  }

  if (!is.null(fossils) && !"fossils" %in% class(fossils)) {
    stop("fossils must be an object of class \"fossils\"")
  }

  if (!is.null(tree) && !is.null(taxonomy)) {
    warning("tree and taxonomy both defined, using taxonomy")
  }

  if (!is.null(attr(rate, "from.taxonomy"))) {
    if (attr(rate, "from.taxonomy") && is.null(taxonomy)) {
      stop("rates simulated from taxonomy, matching \"taxonomy\" object also required")
    }
    if (!attr(rate, "from.taxonomy") && is.null(tree)) {
      stop("rates simulated from tree, matching \"tree\" object also required")
    }
  }

  if (is.null(taxonomy) && is.null(tree$edge.length)) {
    stop("tree must have edge lengths")
  }

  if (is.null(taxonomy) && !ape::is.rooted(tree)) {
    stop("tree must be rooted")
  }

  if (is.null(taxonomy)) {
    taxonomy <- sim.taxonomy(tree, beta = 1, root.edge = root.edge)
    if (length(rate) > 1) {
      if (is.null(tree$root.edge)) rate <- c(0, rate) # no root.edge = no rate provided for it
      rate <- rate[order(c(root(tree), tree$edge[, 2]))] # sort rates by node 1, node 2, etc
      rate <- rate[as.numeric(taxonomy$sp)] # sort rates by taxonomy
    }
    from.taxonomy <- FALSE
  } else {
    from.taxonomy <- TRUE
  }

  if (!all(as.vector(na.omit(fossils$edge)) %in% taxonomy$edge)) {
    stop("Mismatch between fossils and taxonomy objects")
  }

  if (length(rate) > 1 && length(rate) != length(unique(taxonomy$sp))) {
    stop("The vector of rates provided doesn't correspond to the number of species")
  } else if (length(rate) == 1) {
    rate <- rep(rate, length(unique(taxonomy$sp)))
  }

  if (any(rate < 0)) stop("Rates must be positive numbers")

  # If TRUE use exact sampling times.
  # If FALSE hmin and hmax will equal the start and end times of the corresponding edge.
  use.exact.times <- TRUE

  if (is.null(fossils)) {
    fdf <- fossils()
  } else {
    fdf <- fossils
  }

  lineages <- unique(taxonomy$sp)

  for (i in 1:length(lineages)) {
    sp <- lineages[i]
    start <- max(taxonomy$start[which(taxonomy$sp == sp)])
    end <- min(taxonomy$end[which(taxonomy$sp == sp)])

    edges <- taxonomy[which(taxonomy$sp == sp), ]

    blength <- start - end

    # sample fossil numbers from the Poisson distribution
    rand <- rpois(1, blength * rate[i])

    if (rand > 0) {
      if (ignore.taxonomy) sp <- NA
      h <- runif(rand, min = end, max = start)
      edge <- sapply(h, function(x) edges$edge[which(edges$start > x & edges$end < x)])
      if (use.exact.times) {
        fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = h, hmax = h, stringsAsFactors = F))
      } else {
        fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = rep(end, rand), hmax = rep(start, rand), stringsAsFactors = F))
      }
    }
  }
  fdf <- as.fossils(fdf, from.taxonomy)
  return(fdf)
}

#' Simulate fossils under a non-uniform model of preservation for a given set of consecutive time intervals
#'
#' Intervals can be specified by specifying the interval boundaries using \code{interval.ages} or specifying both \code{max.age} and \code{strata}.
#' In the second scenario all intervals will be of equal length.
#' Preservation can be specified using \code{rates}, which represent the rates of a Poisson process in each interval,
#' or \code{probabilities}, which represent the probabilities of sampling per interval.
#' When using \code{probabilities}, at most one fossil per species will be sampled per interval. \cr \cr
#' Fossils can be simulated for a phylo (\code{tree}) or taxonomy (\code{taxonomy}) object.
#' If both are specified, the function uses taxonomy.
#' If no taxonomic information is provided, the function assumes all speciation is symmetric (i.e. bifurcating, \code{beta = 1}).
#'
#' @param tree Phylo object.
#' @param taxonomy Taxonomy object.
#' @param fossils Append fossils to to an existing fossils object.
#' @param interval.ages Vector of stratigraphic interval ages, starting with the minimum age of the youngest interval and ending with the maximum age of the oldest interval.
#' @param max.age Maximum age of the oldest stratigraphic interval.
#' @param strata Number of stratigraphic intervals.
#' @param rates Poisson sampling rate for each interval. The number of rates should match the number of intervals and the first entry should correspond to youngest interval.
#' @param probabilities Probability of sampling/preservation in each interval. The number of probabilities should match the number of intervals and the first entry should correspond to youngest interval.
#' @param ignore.taxonomy Ignore species taxonomy (returns sp = NA). Default = FALSE.
#' @param root.edge If TRUE include the root edge. Default = TRUE.
#' @param use.exact.times If TRUE use exact sampling times. If FALSE \code{hmin} and \code{hmax} will equal the start and end times of the corresponding interval. Default = TRUE.
#' @return An object of class fossils.
#'
#' @examples
#' # simulate tree
#' t <- ape::rtree(6)
#'
#' # assign a max age based on tree height
#' max.age <- tree.max(t)
#'
#' # simulate fossils using max.age and strata & probabilities
#' strata <- 4
#' probability <- rep(0.7, 4)
#' f <- sim.fossils.intervals(t, max.age = max.age, strata = strata, probabilities = probability)
#' plot(f, t, strata = strata, show.strata = TRUE)
#'
#' # simulate fossils using interval.ages & rates
#' times <- c(0, sort(runif(3, min = 0, max = max.age)), max.age)
#' rates <- c(5, 0, 5, 0)
#' f <- sim.fossils.intervals(t, interval.ages = times, rates = rates)
#' plot(f, t, interval.ages = times, show.strata = TRUE)
#'
#' # simulate fossils using taxonomy
#' s <- sim.taxonomy(t, 0.1, 0.1, 1)
#' f <- sim.fossils.intervals(taxonomy = s, interval.ages = times, rates = rates)
#' plot(f, t, interval.ages = times, show.strata = TRUE)
#'
#' # append fossils to an existing fossils object
#' new.rates <- rates * 2
#' f2 <- sim.fossils.intervals(taxonomy = s, fossils = f, interval.ages = times, rates = new.rates)
#'
#' @keywords uniform fossil preservation
#' @keywords non-uniform fossil preservation
#' @seealso \code{\link{sim.fossils.poisson}}, \code{\link{sim.fossils.environment}}
#' @export
sim.fossils.intervals <- function(tree = NULL, taxonomy = NULL, fossils = NULL,
                                  interval.ages = NULL, max.age = NULL, strata = NULL,
                                  probabilities = NULL, rates = NULL, ignore.taxonomy = FALSE,
                                  root.edge = TRUE, use.exact.times = TRUE) {
  if (is.null(tree) && is.null(taxonomy)) {
    stop("Specify phylo or taxonomy object")
  }

  if (!is.null(tree) && !"phylo" %in% class(tree)) {
    stop("tree must be an object of class \"phylo\"")
  }

  if (!is.null(taxonomy) && !"taxonomy" %in% class(taxonomy)) {
    stop("taxonomy must be an object of class \"taxonomy\"")
  }

  if (!is.null(fossils) && !"fossils" %in% class(fossils)) {
    stop("fossils must be an object of class \"fossils\"")
  }

  if (!is.null(tree) && !is.null(taxonomy)) {
    warning("tree and taxonomy both defined, using taxonomy")
  }

  if (is.null(taxonomy) && is.null(tree$edge.length)) {
    stop("tree must have edge lengths")
  }

  if (is.null(taxonomy) && !ape::is.rooted(tree)) {
    stop("tree must be rooted")
  }

  if (is.null(interval.ages) && (is.null(max) || is.null(strata))) {
    stop("Intervals need to be defined by specifying either interval.ages or max.age and strata")
  }
  if (!is.null(max.age) && !is.null(strata)) {
    if (!is.null(interval.ages)) {
      warning("Two interval definitions found, using interval.ages")
    } else {
      interval.ages <- seq(0, max.age, length = strata + 1)
    }
  }

  if (is.null(probabilities) && is.null(rates)) stop("Either rates or probabilities need to be specified")

  if (is.null(taxonomy)) {
    taxonomy <- sim.taxonomy(tree, beta = 1, root.edge = root.edge)
    from.taxonomy <- FALSE
  } else {
    from.taxonomy <- TRUE
  }

  if (!all(as.vector(na.omit(fossils$edge)) %in% taxonomy$edge)) {
    stop("Mismatch between fossils and taxonomy objects")
  }

  use.rates <- FALSE
  if (!is.null(probabilities) && !is.null(rates)) {
    rates <- NULL
    warning("Both probabilities and rates found, using probabilities")
  }
  if (!is.null(rates)) {
    use.rates <- TRUE
    if (length(rates) != (length(interval.ages) - 1)) stop("Length mismatch between interval ages and sampling rates")
  } else {
    if (length(probabilities) != (length(interval.ages) - 1)) stop("Length mismatch between interval ages and sampling probabilities")
    if (any(probabilities < 0) || any(probabilities > 1)) stop("Sampling probabilities must be between 0 and 1")
  }

  if (is.null(taxonomy)) {
    taxonomy <- sim.taxonomy(tree, beta = 1, root.edge = root.edge)
  }

  if (is.null(fossils)) {
    fdf <- fossils()
  } else {
    fdf <- fossils
  }

  lineages <- unique(taxonomy$sp)

  for (sp in lineages) {
    start <- max(taxonomy$start[which(taxonomy$sp == sp)])
    end <- min(taxonomy$end[which(taxonomy$sp == sp)])
    edges <- taxonomy[which(taxonomy$sp == sp), ]

    blength <- start - end

    # possible intervals covered by species
    for (i in 1:(length(interval.ages) - 1)) {
      if (interval.ages[i + 1] < end) next
      if (interval.ages[i] > start) break

      min.time <- max(end, interval.ages[i])
      max.time <- min(start, interval.ages[i + 1])

      if (use.rates) {
        if (ignore.taxonomy) sp <- NA
        # generate k fossils from a poisson distribution
        k <- rpois(1, rates[i] * (max.time - min.time))
        ages <- runif(k, min.time, max.time)
        edge <- sapply(ages, function(x) edges$edge[which(edges$start > x & edges$end < x)])
        if (k > 0) {
          if (use.exact.times) {
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = ages, hmax = ages, stringsAsFactors = F))
          } else {
            min.time <- rep(interval.ages[i], k)
            max.time <- rep(interval.ages[i + 1], k) # this is kind of redundant
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = min.time, hmax = max.time, stringsAsFactors = F))
          }
        }
      } else {
        # scale the probability
        pr <- probabilities[i] * (max.time - min.time) / (interval.ages[i + 1] - interval.ages[i])
        ages <- runif(1, min.time, max.time)
        edge <- sapply(ages, function(x) edges$edge[which(edges$start > x & edges$end < x)])
        # if random.number < pr { record fossil as collected during interval }
        if (runif(1) <= pr) {
          if (use.exact.times) {
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = ages, hmax = ages, stringsAsFactors = F))
          } else { # use interval ages
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = interval.ages[i], hmax = interval.ages[i + 1], stringsAsFactors = F))
          }
        }
      }
    }
  }
  fdf <- as.fossils(fdf, from.taxonomy)
  return(fdf)
}

#' Simulate fossils under an environment-dependent model of preservation (Holland, 1995)
#'
#' @description
#' This function uses a three parameter Gaussian model to simulate non-uniform fossil recovery along a specified phylogeny.
#' Preservation varies with respect to water depth, which is a useful for proxy for changes in the depositional environment.
#' The per interval probability of sampling is \deqn{P(collection) = PA e ^ (-(d - PD)^2 / 2*DT^2 ) }
#' where \emph{PA} is species peak abundance, \emph{PD} is preferred depth, \emph{DT} is depth tolerance and \emph{d} is current water depth.
#' \emph{PD} is the depth at which the species is most likely to be found and is equivalent to the mean of the distribution.
#' \emph{PA} is the probability of sampling an occurrence at this depth.
#' \emph{DT} is the potential of a species to be found at a range of depths and is equivalent to the standard deviation.
#' Although here fossil recovery is described with respect to water depth, the model could be applied in the context of any environmental gradient. \cr \cr
#' The model uses a probability of collecting a fossil within a given interval, rather than a rate.
#'
#' To simulate discrete fossil sampling events and times within each interval we need to convert the probability into a rate
#' (\code{use.rates = TRUE}). This is done using the formula \deqn{rate = -ln(1 - P(collection)/t) } where \emph{t} is the interval length.
#' One caveat of this approach is that the model cannot use a probability of 1, as it would correspond to rate = infinity.
#' In this instance we use an approximation for probabilities = 1 (e.g. \code{pr.1.approx = 0.999}). \cr \cr
#'
#' Non-uniform interval ages can be specified as a vector (\code{interval.ages}) or a uniform set of interval ages can be specified using
#' maximum interval age (\code{max.age}) and the number of intervals (\code{strata}), where interval length \eqn{= max.age/strata}. \cr \cr
#' A vector of values can be specified for the model parameters \emph{PA}, \emph{PD} and \emph{DT} to allow for variation across lineages.
#' If a vector is provided, each entry will apply to each unique species in the order in which they appear in the taxonomy object (if taxonomy is provided),
#' or to each unique edge in the order in which they appear in the tree object.
#' If the tree object has a root edge (\code{root.edge}), the first entry in the vector will apply to this edge. \cr \cr
#' Fossils can be simulated for a phylo (\code{tree}) or taxonomy (\code{taxonomy}) object.
#' If both are specified, the function uses taxonomy.
#' If no taxonomic information is provided, the function assumes all speciation is symmetric (i.e. bifurcating, \code{beta = 1}).
#'
#' @param tree Phylo object.
#' @param taxonomy Taxonomy object.
#' @param interval.ages Vector of stratigraphic interval ages, starting with the minimum age of the youngest interval and ending with the maximum age of the oldest interval.
#' @param max.age Maximum age of the oldest stratigraphic interval or age at the base of the basin.
#' @param strata Number of stratigraphic intervals.
#' @param proxy.data Vector of relative water depth or other proxy data. The first number corresponds to the youngest interval. The length of the vector should be 1 less than the length of interval.ages.
#' @param PD Preferred depth parameter value or a vector of values.
#' @param DT Depth tolerance parameter value or a vector of values.
#' @param PA Peak abundance parameter value or a vector of values.
#' @param root.edge If TRUE include the root edge. Default = TRUE.
#' @param use.rates If TRUE convert per interval sampling probability into a per interval Poisson rate. Default = FALSE.
#' @param pr.1.approx Value used to approximate sampling probabilities = 1 when use.rates = TRUE.
#' @param use.exact.times If TRUE use exact sampling times. If FALSE \code{hmin} and \code{hmax} will equal the start and end times of the corresponding interval. Default = TRUE.
#'
#' @return An object of class fossils.
#'
#' @references
#' Holland, S.M. 1995. The stratigraphic distribution of fossils. Paleobiology 21: 92-109.
#'
#' @examples
#' # simulate tree
#' t <- ape::rtree(6)
#'
#' # assign a max age based on tree height
#' max.age <- tree.max(t)
#'
#' # generate water depth profile
#' strata <- 7
#' wd <- sim.gradient(strata)
#'
#' # simulate fossils using tree & max.age and strata
#' f <- sim.fossils.environment(t,
#'   max.age = max.age, strata = strata,
#'   proxy.data = wd, PD = 0.5, DT = 1, PA = 1
#' )
#' plot(f, t, show.proxy = TRUE, proxy.data = wd, strata = strata, show.strata = TRUE)
#'
#' # simulate fossils using taxonomy & interval.ages
#' s <- sim.taxonomy(t, 0.1, 0.1, 1)
#' times <- seq(0, max.age, length.out = strata + 1)
#' f <- sim.fossils.environment(
#'   taxonomy = s, interval.ages = times,
#'   proxy.data = wd, PD = 0.5, DT = 1, PA = 1
#' )
#' plot(f, t, strata = strata, binned = TRUE)
#'
#' # simulate fossils with variable preservation across lineages
#' dist <- function() {
#'   runif(1)
#' }
#' PD <- sim.trait.values(1,
#'   taxonomy = s, model = "independent", dist = dist,
#'   change.pr = 0.1
#' )
#' f <- sim.fossils.environment(
#'   taxonomy = s, interval.ages = times,
#'   proxy.data = wd, PD = PD, DT = 1, PA = 1
#' )
#' plot(f, t, strata = strata, binned = TRUE)
#'
#' @keywords non-uniform fossil preseravtion
#' @seealso \code{\link{sim.fossils.poisson}}, \code{\link{sim.fossils.intervals}}, \code{\link{sim.trait.values}}
#' @export
sim.fossils.environment <- function(tree = NULL, taxonomy = NULL,
                                    interval.ages = NULL, max.age = NULL, strata = NULL,
                                    proxy.data = NULL, PD = 0.5, DT = 0.5, PA = 0.5,
                                    root.edge = TRUE, use.rates = FALSE, pr.1.approx = 0.999, use.exact.times = TRUE) {
  if (is.null(tree) && is.null(taxonomy)) {
    stop("Specify phylo or taxonomy object")
  }

  if (!is.null(tree) && !"phylo" %in% class(tree)) {
    stop("tree must be an object of class \"phylo\"")
  }

  if (!is.null(taxonomy) && !"taxonomy" %in% class(taxonomy)) {
    stop("taxonomy must be an object of class \"taxonomy\"")
  }

  if (!is.null(tree) && !is.null(taxonomy)) {
    warning("tree and taxonomy both defined, using taxonomy")
  }

  if (is.null(taxonomy) && is.null(tree$edge.length)) {
    stop("tree must have edge lengths")
  }

  if (is.null(taxonomy) && !ape::is.rooted(tree)) {
    stop("tree must be rooted")
  }

  if (is.null(interval.ages) && (is.null(max.age) || is.null(strata))) {
    stop("Intervals need to be defined by specifying either interval.ages or max.age and strata")
  }
  if (!is.null(max.age) && !is.null(strata)) {
    if (!is.null(interval.ages)) {
      warning("Two interval definitions found, using interval.ages")
    } else {
      interval.ages <- seq(0, max.age, length = strata + 1)
    }
  }

  if (is.null(proxy.data)) stop("No proxy data specified")
  if (length(proxy.data) != (length(interval.ages) - 1)) {
    stop("Mismatch between the number of intervals and proxy data values")
  }

  if (is.null(taxonomy)) {
    taxonomy <- sim.taxonomy(tree, beta = 1, root.edge = root.edge)
    if (length(PA) > 1) {
      if (is.null(tree$root.edge)) PA <- c(0, PA) # no root.edge = no value provided for it
      PA <- PA[order(c(root(tree), tree$edge[, 2]))] # sort value by node 1, node 2, etc
      PA <- PA[as.numeric(taxonomy$sp)] # sort value by taxonomy
    }
    if (length(PD) > 1) {
      if (is.null(tree$root.edge)) PD <- c(0, PD) # no root.edge = no value provided for it
      PD <- PD[order(c(root(tree), tree$edge[, 2]))] # sort values by node 1, node 2, etc
      PD <- PD[as.numeric(taxonomy$sp)] # sort values by taxonomy
    }
    if (length(DT) > 1) {
      if (is.null(tree$root.edge)) DT <- c(0, DT) # no root.edge = no value provided for it
      DT <- DT[order(c(root(tree), tree$edge[, 2]))] # sort values by node 1, node 2, etc
      DT <- DT[as.numeric(taxonomy$sp)] # sort values by taxonomy
    }
    from.taxonomy <- FALSE
  } else {
    from.taxonomy <- TRUE
  }

  if (length(PA) > 1 && length(PA) != length(unique(taxonomy$sp))) {
    stop("vector of PA values provided that doesn't correspond to the number of species")
  } else if (length(PA) == 1) {
    PA <- rep(PA, length(unique(taxonomy$sp)))
  }

  if (length(PD) > 1 && length(PD) != length(unique(taxonomy$sp))) {
    stop("vector of PD values provided that doesn't correspond to the number of species")
  } else if (length(PD) == 1) {
    PD <- rep(PD, length(unique(taxonomy$sp)))
  }

  if (length(DT) > 1 && length(DT) != length(unique(taxonomy$sp))) {
    stop("vector of DT values provided that doesn't correspond to the number of species")
  } else if (length(DT) == 1) {
    DT <- rep(DT, length(unique(taxonomy$sp)))
  }

  # calculate per interval per species probabilities
  probabilities <- sapply(proxy.data, function(x) {
    PA * exp((-(x - PD)**2) / (2 * (DT**2)))
  })

  # calculate per interval per species rates
  if (use.rates) {
    s <- sapply(1:length(interval.ages[-1]), function(x) {
      interval.ages[x + 1] - interval.ages[x]
    })
    if (any(probabilities >= 1)) {
      probabilities[which(probabilities >= 1)] <- pr.1.approx
    }
    rates <- -log(1 - probabilities) / s
  }

  fdf <- fossils()

  lineages <- unique(taxonomy$sp)

  for (i in 1:length(lineages)) {
    sp <- lineages[i]
    start <- max(taxonomy$start[which(taxonomy$sp == sp)])
    end <- min(taxonomy$end[which(taxonomy$sp == sp)])
    edges <- taxonomy[which(taxonomy$sp == sp), ]

    blength <- start - end

    # possible intervals covered by taxonomy
    for (j in 1:(length(interval.ages) - 1)) {
      if (interval.ages[j + 1] < end) next
      if (interval.ages[j] > start) break

      min.time <- max(end, interval.ages[j])
      max.time <- min(start, interval.ages[j + 1])

      if (use.rates) {
        # generate k fossils from a poisson distribution
        k <- rpois(1, rates[i, j] * (max.time - min.time))
        ages <- runif(k, min.time, max.time)
        edge <- sapply(ages, function(x) edges$edge[which(edges$start > x & edges$end < x)])
        if (k > 0) {
          if (use.exact.times) {
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = ages, hmax = ages, stringsAsFactors = F))
          } else {
            min.time <- rep(interval.ages[j], k)
            max.time <- rep(interval.ages[j + 1], k) # this is kind of redundant
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = min.time, hmax = max.time, stringsAsFactors = F))
          }
        }
      } else {
        # scale the probability
        pr <- probabilities[i, j] * (max.time - min.time) / (interval.ages[j + 1] - interval.ages[j])
        # assign fossils to edges
        ages <- runif(1, min.time, max.time)
        edge <- sapply(ages, function(x) edges$edge[which(edges$start > x & edges$end < x)])
        # if random.number < pr { record fossil as collected during interval }
        if (runif(1) <= pr) {
          if (use.exact.times) {
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = ages, hmax = ages, stringsAsFactors = F))
          } else { # use interval ages
            fdf <- rbind(fdf, data.frame(sp = sp, edge = edge, hmin = interval.ages[j], hmax = interval.ages[j + 1], stringsAsFactors = F))
          }
        }
      }
    }
  }
  fdf <- as.fossils(fdf, from.taxonomy)
  return(fdf)
}

# Debugging code:
# Simulate fossils under an exponential sampling model
#
# @param tree Phylo object.
# @param rate Exponential sampling rate.
# @param root.edge If TRUE include the root edge (default = TRUE).
# @return An object of class fossils.
# sp = node labels. h = ages.
# The label is for the node just below the sampled fossil.
# @examples
# # simulate tree
# t = ape::rtree(4)
# # simulate fossils
# rate = 2
# f = sim.fossils.exponential(t, rate)
# plot(f, t)
# @keywords uniform preservation
#
#' @importFrom stats rexp
sim.fossils.exponential <- function(tree, rate, root.edge = TRUE) {
  node.ages <- n.ages(tree)

  fossils <- data.frame(h = numeric(), sp = numeric())

  root <- length(tree$tip.label) + 1

  if (root.edge && exists("root.edge", tree)) {
    lineages <- c(tree$edge[, 2], root)
  } else {
    lineages <- tree$edge[, 2]
  }

  for (i in lineages) { # internal nodes + tips

    if (i == root) {
      # root age
      a <- which(names(node.ages) == root)
      lineage.end <- node.ages[[a]]

      # origin time
      b <- tree$root.edge
      lineage.start <- lineage.end + b
    } else {
      # work out the max age of the lineage (e.g. when that lineage became extant)
      # & get ancestor
      row <- which(tree$edge[, 2] == i)
      ancestor <- tree$edge[, 1][row]

      # get the age of the ancestor
      a <- which(names(node.ages) == ancestor)
      lineage.start <- node.ages[[a]]

      # work out the min age of the lineage (e.g. when that lineage became extinct)
      # & get the branch length
      b <- tree$edge.length[row]
      lineage.end <- lineage.start - b # branch length
    }

    t <- 0
    while (TRUE) {
      t <- t + rexp(1, rate)
      if (t < b) { # make fossil
        fossils <- rbind(fossils, data.frame(h = (lineage.start - t), sp = i))
      } else {
        break
      }
    }
  }

  fossils <- as.fossils(fossils, FALSE)
  return(fossils) # in this data frame h=fossil age and sp=lineage
}
