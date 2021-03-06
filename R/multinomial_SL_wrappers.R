############ mnSL wrapper for randomForest
#' @export
mnSL.randomForest <- function(Y, X, newX, family, mtry = max(floor(ncol(X)/3), 1), ntree = 1000, nodesize = 1, ...) {
    require("randomForest")
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    
    fit.rf <- randomForest(y = as.factor(Y), x = X, ntree = ntree, xtest = newX, keep.forest = TRUE, mtry = mtry, nodesize = nodesize)
    pred <- fit.rf$test$votes
    fit <- list(object = fit.rf)
    
    out <- list(pred = pred, fit = fit)
    class(out$fit) <- c("mnSL.randomForest")
    return(out)
}

#' @export
predict.mnSL.randomForest <- function(object, newdata, family, ...) {
    require("randomForest")
    
    pred <- predict(object$object, newdata = newdata, type = "vote")
    
    pred
}

############ mnSL wrapper for mean
#' @export
mnSL.mean <- function(Y, X, newX, family, obsWeights, id, ...) {
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    
    meanY <- aggregate(list(weight = obsWeights), list(cat = Y), sum)$weight/sum(obsWeights)
    pred <- matrix(rep.int(meanY, times = nrow(newX)), nrow = nrow(newX), byrow = T)
    fit <- list(object = meanY)
    out <- list(pred = pred, fit = fit)
    class(out$fit) <- c("mnSL.mean")
    return(out)
}

#' @export
predict.mnSL.mean <- function(object, newdata, family, X = NULL, Y = NULL, ...) {
    pred <- matrix(rep.int(object$object, times = nrow(newdata)), nrow = nrow(newdata), byrow = T)
    return(pred)
}


############ mnSL wrapper for multinom

#' @export
mnSL.multinom <- function(Y, X, newX, family, obsWeights, id, ...) {
    require(nnet)
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    
    df <- data.frame(X, Y = Y)
    fit.mn <- multinom(Y ~ ., df, weights = obsWeights, trace = FALSE)
    pred <- predict(fit.mn, newX, type = "prob")
    fit <- list(object = fit.mn)
    out <- list(pred = pred, fit = fit)
    class(out$fit) <- c("mnSL.multinom")
    return(out)
}

#' @export
predict.mnSL.multinom <- function(object, newdata, family, X = NULL, Y = NULL, ...) {
    pred <- predict(object$object, newdata, type = "prob")
    return(pred)
}


############ mnSL wrapper for glmnet

#' @export
mnSL.glmnet <- function(Y, X, newX, family, obsWeights, id, alpha = 1, nfolds = 10, nlambda = 100, useMin = TRUE, ...) {
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    
    require("glmnet")
    if (!is.matrix(X)) {
        X <- model.matrix(~-1 + ., X)
        newX <- model.matrix(~-1 + ., newX)
    }
    fitCV <- cv.glmnet(x = X, y = Y, weights = obsWeights, lambda = NULL, type.measure = "deviance", nfolds = nfolds, family = "multinomial", 
        alpha = alpha, nlambda = nlambda)
    pred <- predict(fitCV$glmnet.fit, newx = newX, s = ifelse(useMin, fitCV$lambda.min, fitCV$lambda.1se), type = "response")
    fit <- list(object = fitCV, useMin = useMin)
    class(fit) <- "mnSL.glmnet"
    out <- list(pred = pred, fit = fit)
    return(out)
}

#' @export
predict.mnSL.glmnet <- function(object, newdata, ...) {
    if (!is.matrix(newdata)) {
        newdata <- model.matrix(~-1 + ., newdata)
    }
    pred <- predict(object$object$glmnet.fit, newx = newdata, s = ifelse(object$useMin, object$object$lambda.min, object$object$lambda.1se), 
        type = "response")
    return(pred)
}


############ mnSL wrapper for polymars

#' @export
mnSL.polymars <- function(Y, X, newX, family, obsWeights, ...) {
    
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    
    require("polspline")
    
    fit.mars <- polyclass(Y, X, cv = 5, weight = obsWeights)
    pred <- ppolyclass(cov = newX, fit = fit.mars)
    fit <- list(fit = fit.mars)
    
    out <- list(pred = pred, fit = fit)
    class(out$fit) <- c("mnSL.polymars")
    return(out)
}

#' @export
predict.mnSL.polymars <- function(object, newdata, family, ...) {
    pred <- ppolyclass(cov = newdata, fit = object$fit)
    return(pred)
}



############ mnSL wrapper for boosting (gbm)
#' @export
mnSL.gbm <- function(Y, X, newX, family, obsWeights, n.trees = 100, interaction.depth = 1, n.minobsinnode = 10, shrinkage = 0.001, 
    bag.fraction = 0.5, ...) {
    require("gbm")
    
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    # Create a dataframe for gbm method
    data <- as.data.frame(X)
    
    fit.gbm <- gbm::gbm(as.factor(Y) ~ ., data = data, n.trees = n.trees, interaction.depth = interaction.depth, n.minobsinnode = n.minobsinnode, 
        shrinkage = shrinkage, bag.fraction = bag.fraction, distribution = family$family, cv.folds = 5, keep.data = TRUE, weights = obsWeights, 
        verbose = FALSE)
    
    best.iter <- gbm::gbm.perf(fit.gbm, method = "cv", plot.it = FALSE)
    # Return the prob matrix for testing set
    pred <- predict(fit.gbm, newdata = as.data.frame(newX), best.iter, type = "response")
    # Make a list
    fit <- list(object = fit.gbm)
    
    out <- list(pred = pred, fit = fit)
    class(out$fit) <- c("mnSL.gbm")
    return(out)
}


#' @export
predict.mnSL.gbm <- function(object, newdata, family, ...) {
    require("gbm")
    
    pred <- predict(object$object, newdata = as.data.frame(newdata), type = "response")
    
    return(pred)
}





############ mnSL wrapper for Multivariate Adaptive Regression Splines
#' @export
mnSL.earth <- function(Y, X, newX, family, obsWeights, degree = 1, nfold = 0, ...) {
    require("earth")
    if (family$family != "multinomial") {
        stop("mnSL functions are for multinomial family only")
    }
    # Create a dataframe for earth method
    data <- as.data.frame(X)
    
    fit.earth <- earth::earth(as.factor(Y) ~ ., data = data, weights = obsWeights, nfold = nfold)
    
    
    # Return the prob matrix for testing set
    pred <- predict(fit.earth, newdata = as.data.frame(newX), type = "response")
    # Make a list
    fit <- list(object = fit.earth)
    
    
    out <- list(pred = pred, fit = fit)
    class(out$fit) <- c("mnSL.earth")
    return(out)
}

#' @export
predict.mnSL.earth <- function(object, newdata, family, ...) {
    require("earth")
    
    pred <- predict(object$object, newdata = newdata, type = "response")
    
    pred
}
