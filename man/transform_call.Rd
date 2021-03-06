% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/user-defined-transformations.R
\name{transform_call}
\alias{transform_call}
\alias{transform_call.default}
\title{Transform a call before the tail-recursion transformation.}
\usage{
transform_call(fun, expr)

\method{transform_call}{default}(fun, expr)
}
\arguments{
\item{fun}{The actual function. Used for dynamic dispatching.}

\item{expr}{The expression to rewrite.}
}
\value{
The rewritten expression.
}
\description{
This generic function is a hook by which you can modify how the
tail-recursion transformations should handle special functions.
It gives you a way to rewrite function calls to make them tail-recursive
before we do any other manipulation.
}
\section{Methods (by class)}{
\itemize{
\item \code{default}: The default is to just return the unchanged expression.
}}

\examples{
my_if_else <- function(test, if_true, if_false) {
    if (test) if_true else if_false
}
f <- function(x, y) my_if_else(x == y, x, f(y, y))
f(1, 2)
f(3, 3)

can_loop_transform(f) # No, we can't, and we get a warning

class(my_if_else) <- c("my_if_else", class(my_if_else))
class(my_if_else)

transform_call.my_if_else <- function(fun, expr) {
    test <- expr[[2]]; if_true <- expr[[3]]; if_false <- expr[[4]]
    rlang::expr(if (rlang::UQ(test)) rlang::UQ(if_true) else rlang::UQ(if_false))
}
transform_call(my_if_else, quote(my_if_else(x == y, x, f(y, y))))

can_loop_transform(f) # Now we can, because my_if_else gets transformed

}
