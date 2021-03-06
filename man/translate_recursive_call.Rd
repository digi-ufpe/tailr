% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/loop-transformation.R
\name{translate_recursive_call}
\alias{translate_recursive_call}
\title{Translate a return(<recursive-function-call>) expressions into
a block that assigns the parameters to local variables and call `continue`.}
\usage{
translate_recursive_call(recursive_call, info)
}
\arguments{
\item{recursive_call}{The call object where we get the parameters}

\item{info}{Information passed along to the transformations.}
}
\value{
The rewritten expression
}
\description{
Translate a return(<recursive-function-call>) expressions into
a block that assigns the parameters to local variables and call `continue`.
}
