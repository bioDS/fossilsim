#' Remove fossil lineages from a tree
#'
#' @param tree an object of class "Phylo".
#'
#' @return an object of class "Phylo". If fossil lineages were found in the tree
#'   these will be pruned, if not then the original tree is returned.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' prune.fossil.tips(t)
#' @export
#'
prune.fossil.tips <- function(tree) {
  if (ape::is.ultrametric(tree)) {
    warning("Tree is ultrametric and no fossil tips can be pruned")
    return(tree)
  }

  # avoids geiger::is.extinct()
  tol <- min(tree$edge.length) / 100
  tipHeight <- diag(ape::vcv.phylo(tree))

  foss <- names(which(tipHeight < max(tipHeight) - tol))
  newTree <- ape::drop.tip(tree, foss)
  return(newTree)
}

#' Obtain the tips that define each node in a tree
#'
#' @param tree an object of class "Phylo".
#'
#' @return A list of vectors, with one entry for each node consisting of the tip labels
#'   that define that node.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' get.tip.descs(t)
#' @export
#'
get.tip.descs <- function(tree) {
  ntips <- length(tree$tip.label)
  all_descs <- vector("list", ntips + tree$Nnode)

  descs <- function(tree, node, all_descs) {
    descendants <- tree$edge[which(tree$edge[, 1] == node), 2]
    if (length(descendants) == 0) all_descs[[node]] <- tree$tip.label[node]

    for (d in descendants) {
      all_descs <- descs(tree, d, all_descs)
      all_descs[[node]] <- c(all_descs[[node]], all_descs[[d]])
    }

    all_descs
  }

  all_descs <- descs(tree, ntips + 1, all_descs)
  all_descs <- all_descs[(ntips + 1):(ntips + tree$Nnode)]
  names(all_descs) <- (ntips + 1):(ntips + tree$Nnode)
  return(all_descs)
}

#' Remove fossil samples that occur in the stem
#'
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences for "tree".
#' @param tree an object of class "Phylo".
#'
#' @return an object of class "fossils", containing only the fossil samples that
#'   occur in the crown.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' f <- sim.fossils.poisson(0.1, t)
#' remove.stem.fossils(f, t)
#' @export
#'
remove.stem.fossils <- function(fossils, tree) {
  crown <- prune.fossil.tips(tree)
  crown <- crown$tip.label

  crownNode <- ape::getMRCA(tree, crown)
  crownTax <- fetch.descendants(crownNode, tree)
  stemTax <- setdiff(fetch.descendants(min(tree$edge[, 1]), tree), crownTax)
  if (length(stemTax) == 0) {
    # warning("No stem-group found in user supplied tree")
    return(fossils)
  }
  stem <- setdiff(fetch.descendants(tree$edge[, 1], tree, TRUE), fetch.descendants(crownNode, tree, TRUE))

  remove <- which(fossils$sp %in% stem)
  if (length(remove > 0)) {
    fossils <- fossils[-remove, ]
    if (length(fossils$sp) > 0) row.names(fossils) <- as.character(c(1:length(fossils$sp)))
  }

  return(fossils)
}

#' Remove stem lineages from a tree.
#'
#' @param tree an object of class "Phylo".
#'
#' @return an object of class "Phylo", if stem lineages were found in the tree
#'   these will be pruned; if not then the original tree is returned.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' remove.stem.lineages(t)
#' @export
#'
remove.stem.lineages <- function(tree) {
  crown <- prune.fossil.tips(tree)
  crown <- crown$tip.label
  crownNode <- ape::getMRCA(tree, crown)
  # crownTips <-
  #  tree$tip.label[phangorn::Descendants(tree, crownNode)[[1]]]
  crownTips <- fetch.descendants(crownNode, tree)
  if (length(crownTips) == length(tree$tip.label)) {
    warning("No stem lineages found, returning original tree")
    return(tree)
  }
  remove <- setdiff(tree$tip.label, crownTips)
  tree <- ape::drop.tip(tree, remove)
  return(tree)
}

#' Place fossil samples from one tree in another tree, or find the ancestral
#' node for each fossil sample in one tree.
#'
#' If "ext.tree" is not supplied, this function will find the direct ancestral
#' node for each of the supplied fossil samples. If "ext.tree" is supplied, this
#' function will find the direct ancestral node for each fossil in "ext.tree".
#' This second behaviour is used for placing fossils simulated on a complete
#' Birth-Death tree in the extant-only counterpart tree. This results in fossil
#' samples being placed in the crown clades of the tree upon which they were
#' simulated. When "ext.tree" is supplied, any fossil samples appearing before
#' the MRCA of the crown group are discarded.
#'
#' @param tree an object of class "Phylo".
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences for the "tree" argument.
#' @param ext.tree an object of class "Phylo" representing the extant
#'   counterpart to "tree", this can be obtained with prune.fossil.tips(tree).
#' @return a vector of node numbers corresponding to the direct ancestor of each
#'   fossil sample in "fossils".
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' f <- sim.fossils.poisson(0.1, t, root.edge = FALSE)
#' place.fossils(t, f)
#' @export
#'
place.fossils <- function(tree, fossils, ext.tree) {
  if (any(fossils$sp == min(tree$edge[, 1]))) {
    stop("Can't handle fossil samples on the root.edge")
  }

  # if placing in the extant tree is not required, then set it to be tree
  if (missing(ext.tree)) {
    ext.tree <- tree
  } else {
    # cant place stem group fossils in an extant tree
    fossils <- remove.stem.fossils(fossils, tree)

    if (!ape::is.ultrametric(ext.tree)) {
      stop("User supplied extant tree is not ultrametric")
    }
  }

  if (!ape::is.binary.phylo(tree) |
    !ape::is.binary.phylo(ext.tree)) {
    stop("Both trees must be strictly bifurcating")
  }

  # Get the nodes that are suitable to fit fossils to
  d <- get.tip.descs(ext.tree)
  nodes <- c()
  for (i in 1:length(d)) {
    nodes[i] <- ape::getMRCA(tree, d[[i]])
  }

  output_nodes <- c()

  # for each fossil, go backwards in the tree until we hit one of the suitable nodes
  for (i in 1:length(fossils$sp)) {
    # a <- phangorn::Ancestors(tree, node = fossils$sp[i], type = "all")
    a <- find.edges.inbetween(j = min(tree$edge[, 1]), i = fossils$sp[i], tree = tree)[-1]
    if (length(a) == 1 && a[1] < min(nodes)) {
      # this error should not be met
      stop(paste0("fossil number ", i, " does not belong to the crown group"))
    }
    hit <- min(which(a %in% nodes))
    output_nodes[i] <- a[hit]
  }

  # Now find the comparable node in the second tree
  descs <- get.tip.descs(tree)
  for (i in 1:length(output_nodes)) {
    # tmp <- tree$tip.label[phangorn::Descendants(tree,
    #        output_nodes[i])[[1]]][tree$tip.label[phangorn::Descendants(tree,
    #          output_nodes[i])[[1]]] %in% ext.tree$tip.label]
    tmp_tips <- which(tree$tip.label %in% descs[[as.character(output_nodes[i])]])
    tmp <- tree$tip.label[tmp_tips][tree$tip.label[tmp_tips] %in% ext.tree$tip.label]

    output_nodes[i] <- ape::getMRCA(ext.tree, tmp)
  }
  return(output_nodes)
}


#' Obtain a uniform random sample of fossil occurrences.
#'
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences.
#' @param proportion the proportion of all fossil samples to return in the
#'   subsample.
#' @return an object of class "fossils" containing the subsampled fossil
#'   occurrences.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' f <- sim.fossils.poisson(0.1, t, root.edge = FALSE)
#' subsample.fossils.uniform(f, 0.5)
#' @export
#'
subsample.fossils.uniform <- function(fossils, proportion) {
  if (proportion > 1 | proportion < 0) {
    stop("proportion must be between 0 and 1")
  }
  smp <-
    sample(
      x = c(1:length(fossils$sp)),
      size = length(fossils$sp) * proportion,
      replace = FALSE
    )
  return(fossils[smp, ])
}

#' Obtain a random sample of fossil occurrences which is uniform on each sampling interval.
#'
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences.
#' @param proportion a vector of proportions of all fossil samples to return in the
#'   subsample. The rate in entry i is the proportion rate ancestral to time times[i]
#' @param times Vector of sampling proportion rate shift times. Time is 0 today and increasing going backwards in time.
#' Specify the vector as times[i] < times[i+1]. times[1] = 0 (today). Do not specify the origin time (a maximum time is not required).
#' @return an object of class "fossils" containing the subsampled fossil
#'   occurrences.
#' @examples
#' t <- TreeSim::sim.bd.age(3, 1, 2, 0.5)[[1]]
#' f <- sim.fossils.poisson(0.9, t, root.edge = FALSE)
#' subsample.fossils.uniform.intervals(f, c(0.5, 0.1), c(0, 1))
#' @export
#'
subsample.fossils.uniform.intervals <- function(fossils, proportions, times) {
  if (length(proportions) != length(times)) {
    stop("Length mismatch between rate shift times and sampling rates")
  }
  for (i in 1:length(proportions)) {
    if (proportions[i] > 1 | proportions[i] < 0) {
      stop("proportions must be between 0 and 1")
    }
  }
  smp <- c()
  indices <- c()
  ages <- fossils$hmax
  indices <- 1:length(ages)
  for (i in 1:length(times)) {
    if (i == length(times)) {
      sel_f <- indices[ages > times[i]]
    } else {
      sel_f <- indices[ages < times[i + 1] & ages >= times[i]]
    }
    s <- sample(sel_f, length(sel_f) * proportions[i], replace = FALSE)
    smp <- c(smp, s)
  }
  return(fossils[smp, ])
}

#' Obtain a subsample of fossil occurrences containing the oldest fossil sample
#' in each node of the tree.
#'
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences.
#' @param tree an object of class "Phylo", representing the tree upon which the
#'   fossil occurrences were simulated.
#' @param complete logical, if TRUE the oldest sample from each clade in the
#'   complete tree is returned, if FALSE the oldest sample from each clade in
#'   the extant only counterpart tree is returned.
#' @return an object of class "fossils" containing the subsampled fossil
#'   occurrences.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' f <- sim.fossils.poisson(0.1, t, root.edge = FALSE)
#' subsample.fossils.oldest(f, t, complete = FALSE)
#' @export
#'
subsample.fossils.oldest <- function(fossils, tree, complete = TRUE) {
  if (!complete) {
    ext <- prune.fossil.tips(tree)
    fossils <- remove.stem.fossils(fossils, tree)
    ancs <- place.fossils(tree, fossils, ext)
  } else {
    ancs <- place.fossils(tree, fossils)
  }

  smp <- c()
  for (i in 1:length(unique(ancs))) {
    x <- which(ancs == unique(ancs)[i])
    smp <- c(smp, which(fossils$hmax == max(fossils$hmax[x])))
  }
  out <- fossils[smp, ]
  row.names(out) <- as.character(c(1:length(out$hmax)))
  return(out)
}

#' Obtain a subsample of fossil occurrences containing the youngest fossil
#' sample in each node of the tree.
#'
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences.
#' @param tree an object of class "Phylo", representing the tree upon which the
#'   fossil occurrences were simulated.
#' @param complete logical, if TRUE the youngest sample from each clade in the
#'   complete tree is returned, if FALSE the youngest sample from each clade in
#'   the extant only counterpart tree is returned.
#' @return an object of class "fossils" containing the subsampled fossil
#'   occurrences.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' f <- sim.fossils.poisson(0.1, t, root.edge = FALSE)
#' subsample.fossils.youngest(f, t, complete = FALSE)
#' @export
#'
subsample.fossils.youngest <- function(fossils, tree, complete = TRUE) {
  if (!complete) {
    ext <- prune.fossil.tips(tree)
    fossils <- remove.stem.fossils(fossils, tree)
    ancs <- place.fossils(tree, fossils, ext)
  } else {
    ancs <- place.fossils(tree, fossils)
  }

  smp <- c()
  for (i in 1:length(unique(ancs))) {
    x <- which(ancs == unique(ancs)[i])
    smp <- c(smp, which(fossils$hmin == min(fossils$hmin[x])))
  }
  out <- fossils[smp, ]
  row.names(out) <- as.character(c(1:length(out$hmin)))
  return(out)
}

#' Obtain a subsample of fossil occurrences containing the oldest and youngest
#' fossil sample found at each node of the tree.
#'
#' @param fossils an object of class "fossils" that corresponds to fossil
#'   occurrences.
#' @param tree an object of class "Phylo", representing the tree upon which the
#'   fossil occurrences were simulated.
#' @param complete logical, if TRUE the oldest and youngest sample from each
#'   clade in the complete tree is returned, if FALSE the oldest and youngest
#'   sample from each clade in the extant only counterpart tree is returned.
#' @return an object of class "fossils" containing the subsampled fossil
#'   occurrences.
#' @examples
#' t <- TreeSim::sim.bd.taxa(10, 1, 0.1, 0.05)[[1]]
#' f <- sim.fossils.poisson(0.1, t, root.edge = FALSE)
#' subsample.fossils.oldest.and.youngest(f, t, complete = FALSE)
#' @export
subsample.fossils.oldest.and.youngest <- function(fossils, tree, complete = TRUE) {
  if (!complete) {
    ext <- prune.fossil.tips(tree)
    fossils <- remove.stem.fossils(fossils, tree)
    ancs <- place.fossils(tree, fossils, ext)
  } else {
    ancs <- place.fossils(tree, fossils)
  }

  smp_1 <- c()
  smp_2 <- c()
  for (i in 1:length(unique(ancs))) {
    x <- which(ancs == unique(ancs)[i])
    smp_1 <- c(smp_1, which(fossils$hmax == max(fossils$hmax[x])))
    smp_2 <- c(smp_2, which(fossils$hmin == min(fossils$hmin[x])))
  }

  smp <- unique(c(smp_1, smp_2))
  out <- fossils[smp, ]
  row.names(out) <- as.character(c(1:length(out$hmin)))
  return(out)
}

# mimics the performance of phangorn::Descendents(type="children")
get.dec.nodes <- function(tree, node) {
  if (node <= length(tree$tip.label)) {
    stop("node must be an internal node, not a tip")
  }

  return(tree$edge[tree$edge[, 1] == node, 2])
}

# Bind a new tip into an existing tree with a given label
# the new tip will appear as the sister taxon to the chosen tip
# "Where" is the node number of a tip
bind.to.tip <- function(tree, where, label = "Foss_1") {
  if (where > length(tree$tip.label)) {
    stop("'where' must be the node number of a tip only")
  }

  tip <- ape::rtree(2)
  tip$tip.label <- c("=^%", label)
  tip <- ape::drop.tip(tip, "=^%")

  len <- which(tree$edge[, 2] == where)
  len <- tree$edge.length[len] / 2

  x <- ape::bind.tree(tree, tip, where = where, position = len)

  return(x)
}
