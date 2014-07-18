# benefits over SuperLearner package from gencv: arbitrary CV schemes foreach parallelization from SL
# implementation: learners that return a vector of predictions for each observation, avoiding nested CV
# (SL.glmnetall) can return fold specific SL fits for smart sequential super learner -> don't fully match SL
# object

# have to think about how to implement nested cvs
fitmods <- function(SL.library, Y, X, newX, family, obsWeights, id) {
    fits <- lapply(SL.library, function(learner) {
        do.call(learner, list(Y = Y, X = X, newX = newX, family = family, obsWeights = obsWeights, id = id))
    })
    names(fits) <- SL.library
    return(fits)
}

#' @param fold a Fold to be passed to cv_SL.
#' @export
#' @rdname origami_SuperLearner
cv_SL <- function(fold, Y, X, SL.library, family, obsWeights, 
                  id, ...) {
    # training objects
    train_Y <- training(Y)
    train_X <- training(X)
    train_obsWeights <- training(obsWeights)
    train_id <- training(id)
    
    # validation objects
    valid_X <- validation(X)
    valid_index <- validation()
    
    # fit on training and predict on validation
    fits <- fitmods(SL.library, Y = train_Y, X = train_X, newX = valid_X, family = family, obsWeights = train_obsWeights, 
        id = train_id)
    
    # extract and collapse predictions
    preds <- lapply(fits, function(fit) fit$pred)
    Z <- do.call(cbind, preds)
    
    results <- list(Z = Z, valid_index = valid_index, fits = fits)
    
    return(results)
}

#' @title origami_SuperLearner
#' @description SuperLearner implemented using orgami cross-validation. Leverages a lot of code from Eric Polley's 
#' SuperLearner package. Because of it's based on origami, we get two features for free: 
#' foreach based parallelization, and support for arbitrary cross-validation schemes. 
#' Note, while this is a working SuperLearner implementation, it is intended more as an example 
#' than production code. As such, it is subject to change in the future.
#' @param Y vector of outcomes.
#' @param X vector of covariates.
#' @param newX currently ignored.
#' @param SL.library character vector of learner names.
#' @param family Either gaussian() or binomial() depending on if Y is binary or continuous.
#' @param obsWeights vector of weights.
#' @param id vector of ids.
#' @param folds a list of Folds. See \code{\link{make_folds}}. If missing, 
#'        will be created based on Y and cluster_ids.
#' @param method a combination method. Typically either method.NNLS or method.NNloglik.
#' @param ... other arguments passed to the underlying call to \code{\link{cross_validate}}
#' 
#' @seealso \code{\link{predict.origami_SuperLearner}}
#' @example /inst/examples/SL_example.R
#' 
#' @export
origami_SuperLearner <- function(Y, X, newX = NULL, SL.library, family = gaussian(), obsWeights = rep(1, length(Y)), 
    id = NULL, folds = NULL, method = method.NNLS(), ...) {
    
    if (is.null(folds)) {
        folds <- make_folds(Y, cluster_ids = id)
    }
    
    if (is.null(newX)) {
        newX <- X
    }
    
    if (is.null(id)) {
        id <- seq_along(Y)
    }
    
    # fit algorithms to folds, get predictions
    results <- cross_validate(cv_SL, folds, Y, X, SL.library, family, obsWeights, id, ...)
    
    # unshuffle Z
    Z <- results$Z[order(results$valid_index), ]
    
    # calculate coefficients
    getCoef <- method$computeCoef(Z = Z, Y = Y, obsWeights, libraryNames = SL.library, verbose = F)
    coef <- getCoef$coef
    cvRisk <- getCoef$cvRisk
    
    # refit models on full sample
    resub <- make_folds(Y, fold_fun = "resubstitution")[[1]]
    full <- cv_SL(resub, Y, X, SL.library, family, obsWeights, id, ...)
    
    # fit object for predictions
    fitObj <- structure(list(library_fits = full$fits, coef = coef, family = family, method = method), class = "origami_SuperLearner_fit")
    
    # analogous objects but with learners fit only in a particular fold
    foldFits <- lapply(seq_along(folds), function(fold) {
        fitObj$library_fits <- results$fits[[fold]]
        fitObj
    })
    
    # results
    out <- list(coef = coef, cvRisk = cvRisk, Z = Z, SL.library = SL.library, folds = folds, fullFit = fitObj, foldFits = foldFits)
    class(out) <- "origami_SuperLearner"
    return(out)
}

#' @title predict.origami_SuperLearner
#' @description prediction function for origami_SuperLearner. Note, while this is a working SuperLearner implementation, it is intended more as an example 
#' than production code. As such, it is subject to change in the future.
#' @param object origami_SuperLearner fit.
#' @param newdata matrix or data.frame of new covariate values
#' @param ... other arguments to the learners.
#' @return A list with two elements: \code{library_pred} are the predictions from the library functions, and \code{pred} is the prediction from the SuperLearner.
#' @seealso \code{\link{origami_SuperLearner}}
#' 
#' @export
predict.origami_SuperLearner <- function(object, newdata, ...) {
    if (missing(newdata)) (stop("newdata must be specified"))
    
    predict(object$fullFit, newdata)
}

#' @export
predict.origami_SuperLearner_fit <- function(object, newdata, ...) {
    if (missing(newdata)) (stop("newdata must be specified"))
  
    library_pred <- sapply(object$library_fits, function(fitobj) {
        predict(fitobj$fit, newdata = newdata, family = object$family)
    })
    pred <- object$method$computePred(library_pred, object$coef)
    
    return(list(pred = pred, library_pred = library_pred))
} 