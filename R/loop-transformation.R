
## Test for possibility of transformation #########################################

# I need to import the Depends packagefor CHECK to work, so I might as well do it here...
# Other than satisfying CHECK, I'm not using these imports since I qualify the functions
# by their namespace.

#' Tests if a call object can be transformed.
#'
#' @param call_name Name (function) of the call.
#' @param call_arguments The call's arguments
#' @param fun_name The name of the recursive function we want to transform
#' @param fun_call_allowed Whether a recursive call is allowed at this point
#' @param cc Current continuation to abort if a transformation is not possible
#'
#' @return TRUE, if the expression can be transformed. Invokes \code{cc} otherwise.
can_call_be_transformed <- function(call_name, call_arguments,
                                    fun_name, fun_call_allowed, cc) {
    switch(call_name,
        # Code blocks -- don't consider those calls.
        "{" = {
            for (arg in call_arguments) {
                can_transform_rec(arg, fun_name, fun_call_allowed, cc)
            }
        },

        # Eval is really just evaluation of an expression in the calling scope,
        # so we shouldn't consider those function calls either... I'm not sure how to
        # handle them when it comes to what they return, though, since it depends
        # on the expression they will evaluate
        "eval" = {
            warning("We can't yet handle eval expressions.")
            cc(FALSE)
        },

        # With expressions are a bit like eval, I guess... don't consider them
        # function calls.
        "with" = {
            for (arg in call_arguments) {
                can_transform_rec(arg, fun_name, fun_call_allowed, cc)
            }
        },

        # Selection
        "if" = {
            can_transform_rec(call_arguments[[1]], fun_name, fun_call_allowed, cc)
            can_transform_rec(call_arguments[[2]], fun_name, TRUE, cc)
            if (length(call_arguments) == 3) {
                can_transform_rec(call_arguments[[3]], fun_name, TRUE, cc)
            }
        },

        # Loops
        "for" = {
            warning("We can't yet handle loops.")
            cc(FALSE)
        },
        "while" = {
            warning("We can't yet handle loops.")
            cc(FALSE)
        },
        "repeat" = {
            warning("We can't yet handle loops.")
            cc(FALSE)
        },

        # All other calls
        {
            if (call_name == fun_name && !fun_call_allowed) {
                warn_msg <- simpleWarning(
                    "The function cannot be transformed since it contains a recursive call inside a call.",
                    call = NULL
                )
                warning(warn_msg)
                cc(FALSE)
            }
            fun_call_allowed <- FALSE
            for (arg in call_arguments) {
                can_transform_rec(arg, fun_name, fun_call_allowed, cc)
            }
        }
    )
    return(TRUE)
}

#' Recursive call for testing if an expression can be transformed into a looping tail-recursion.
#'
#' @param expr The expression to test
#' @param fun_name The name of the recursive function we want to transform
#' @param fun_call_allowed Whether a recursive call is allowed at this point
#' @param cc Current continuation, used to escape if the expression cannot be transformed.
#'
#' @return TRUE, if the expression can be transformed. Invokes \code{cc} otherwise.
can_transform_rec <- function(expr, fun_name, fun_call_allowed, cc) {
    if (rlang::is_atomic(expr) || rlang::is_pairlist(expr) ||
        rlang::is_symbol(expr) || rlang::is_primitive(expr)) {
        return(TRUE)
    } else {
        stopifnot(rlang::is_lang(expr))
        call_name <- rlang::call_name(expr)
        call_arguments <- rlang::call_args(expr)
        can_call_be_transformed(call_name, call_arguments, fun_name, fun_call_allowed, cc)
    }
}


check_function_argument <- function(fun) {
    fun_name <- rlang::get_expr(fun)
    if (!rlang::is_symbol(fun_name)) {
        error <- simpleError(
            glue::glue(
                "Since we need to recognise recursion, we can only manipulate ",
                "functions provided to can_loop_transform by name.\n",
                "Use a bare symbol."
            ),
            call = match.call()
        )
        stop(error)
    }

    fun <- rlang::eval_tidy(fun)
    if (!rlang::is_closure(fun)) {
        error <- simpleError(
            glue::glue(
                "The function provided to can_loop_transform must be a user-defined function.\n",
                "Instead, it is {fun_name} == {deparse(fun)}."
            ),
            call = match.call()
        )
        stop(error)
    }
}

#' @describeIn can_loop_transform This version expects \code{fun_body} to be qboth tested
#'                                and user-transformed.
#'
#' @param fun_name Name of the recursive function.
#' @param fun_body The user-transformed function body.
#' @param env      Environment used to look up variables used in \code{fun_body}.
#'
#' @export
can_loop_transform_body <- function(fun_name, fun_body, env) {
    fun_body <- user_transform(fun_body, env)
    callCC(function(cc) can_transform_rec(fun_body, fun_name, TRUE, cc))
}

#' @describeIn can_loop_transform This version expects \code{fun} to be quosure.
#' @export
can_loop_transform_ <- function(fun) {
    check_function_argument(fun)

    fun_name <- rlang::get_expr(fun)
    fun_env <- rlang::get_env(fun)
    fun_body <- user_transform(body(rlang::eval_tidy(fun)), fun_env)

    can_loop_transform_body(fun_name, fun_body, fun_env)
}


#' Tests if a function, provided by its name, can be transformed.
#'
#' This function analyses a recursive function to check if we can transform it into
#' a loop or trampoline version with \code{\link{transform}}. Since this function needs to handle
#' recursive functions, it needs to know the name of its input function, so this must be
#' provided as a bare symbol.
#'
#' @param fun The function to check. Must be provided by its (bare symbol) name.
#'
#' @examples
#' factorial <- function(n)
#'     if (n <= 1) 1 else n * factorial(n - 1)
#' factorial_acc <- function(n, acc = 1)
#'     if (n <= 1) acc else factorial_acc(n - 1, n * acc)
#'
#' can_loop_transform(factorial)     # FALSE -- and prints a warning
#' can_loop_transform(factorial_acc) # TRUE
#'
#' can_loop_transform_(rlang::quo(factorial))     # FALSE -- and prints a warning
#' can_loop_transform_(rlang::quo(factorial_acc)) # TRUE
#'
#' @describeIn can_loop_transform This version quotes \code{fun} itself.
#' @export
can_loop_transform <- function(fun) {
    fun <- rlang::enquo(fun)
    can_loop_transform_(fun)
}

## Function transformation ###################################################

#' Translate a return(<recursive-function-call>) expressions into
#' a block that assigns the parameters to local variables and call `continue`.
#'
#' @param recursive_call The call object where we get the parameters
#' @param info           Information passed along to the transformations.
#' @return The rewritten expression
translate_recursive_call <- function(recursive_call, info) {
    expanded_call <- match.call(definition = info$fun, call = recursive_call)
    arguments <- as.list(expanded_call)[-1]
    assignments <- rlang::expr(rlang::env_bind(.tailr_env, !!! arguments))
    as.call(c(
        rlang::sym("{"),
        assignments,
        rlang::expr(rlang::return_to(.tailr_frame))
    ))
}


#' Make exit points into explicit calls to return.
#'
#' This function dispatches on a call object to set the context of recursive
#' expression modifications.
#'
#' @param call_expr The call to modify.
#' @param in_function_parameter Is the expression part of a parameter to a function call?
#' @param info  Information passed along with transformations.
#' @return A modified expression.
make_returns_explicit_call <- function(call_expr, in_function_parameter, info) {
    call_name <- rlang::call_name(call_expr)
    call_args <- rlang::call_args(call_expr)

    switch(call_name,
        # For if-statments we need to treat the condition as in a call
        # but the two branches will have the same context as the enclosing call.
        "if" = {
            call_expr[[2]] <- make_returns_explicit(call_args[[1]], TRUE, info)
            call_expr[[3]] <- make_returns_explicit(call_args[[2]], in_function_parameter, info)
            if (length(call_args) == 3) {
                call_expr[[4]] <- make_returns_explicit(call_args[[3]], in_function_parameter, info)
            }
        },

        # We don't treat blocks as calls and we only transform the last argument
        # of the block. Explicit returns are the only way to exit the block in earlier
        # statements, anyway
        "{" = {
            n <- length(call_expr)
            call_expr[[n]] <- make_returns_explicit(call_expr[[n]], in_function_parameter, info)
        },

        # Not sure how to handle eval, exactly...
        # The problem here is that I need to return the expression if it is not a recursive call
        # but not if it is...
        "eval" = {
            stop("FIXME")
        },

        # With should just be left alone and we can deal with the expression it evaluates
        "with" = {
            call_expr[[3]] <- make_returns_explicit(call_expr[[3]], in_function_parameter, info)
        },

        # For all other calls we transform the arguments inside a call context.
        {
            if (rlang::call_name(call_expr) == info$fun_name) {
                call_expr <- translate_recursive_call(call_expr, info)
            } else {
                for (i in seq_along(call_args)) {
                    call_expr[[i + 1]] <- make_returns_explicit(call_args[[i]], TRUE, info)
                }
                if (!in_function_parameter) { # if we weren't parameters, we are a value to be returned
                    call_expr <- rlang::expr(rlang::return_from(.tailr_frame, !! call_expr))
                }
            }
        }
    )

    call_expr
}

#' Make exit points into explicit calls to return.
#'
#' @param expr An expression to transform
#' @param in_function_parameter Is the expression part of a parameter to a function call?
#' @param info Information passed along the transformations.
#' @return A modified expression.
make_returns_explicit <- function(expr, in_function_parameter, info) {
    if (rlang::is_atomic(expr) || rlang::is_pairlist(expr) ||
        rlang::is_symbol(expr) || rlang::is_primitive(expr)) {
        if (in_function_parameter) {
            expr
        } else {
            rlang::expr(rlang::return_from(.tailr_frame, !! expr))
        }
    } else {
        stopifnot(rlang::is_lang(expr))
        make_returns_explicit_call(expr, in_function_parameter, info)
    }
}


#' Simplify nested code-blocks.
#'
#' If a call is \code{\{} and has a single expression inside it, replace it with that expression.
#'
#' @param expr The expression to rewrite
#' @return The new expression
simplify_nested_blocks <- function(expr) {
    if (rlang::is_atomic(expr) || rlang::is_pairlist(expr) ||
        rlang::is_symbol(expr) || rlang::is_primitive(expr)) {
        expr
    } else {
        stopifnot(rlang::is_lang(expr))
        call_name <- rlang::call_name(expr)
        if (call_name == "{" && length(expr) == 2) {
            simplify_nested_blocks(expr[[2]])
        } else {
            args <- rlang::call_args(expr)
            for (i in seq_along(args)) {
                expr[[i + 1]] <- simplify_nested_blocks(args[[i]])
            }
            expr
        }
    }
}

#' Construct the expression for a transformed function body.
#'
#' This is where the loop-transformation is done. This function translates
#' the body of a recursive function into a looping function.
#'
#' @param fun_expr The original function body.
#' @param info Information passed along the transformations.
#' @return The body of the transformed function.
build_transformed_function <- function(fun_expr, info) {
    fun_expr <- make_returns_explicit(fun_expr, FALSE, info)
    fun_expr <- simplify_nested_blocks(fun_expr)
    rlang::expr({
        .tailr_env <- rlang::get_env()
        .tailr_frame <- rlang::current_frame()
        repeat {
            !! fun_expr
        }
    })
}

#' Transform a function from recursive to looping.
#'
#' Since this function needs to handle recursive functions, it needs to know the
#' name of its input function, so this must be provided as a bare symbol.
#'
#' @param fun The function to transform. Must be provided as a bare name.
#'
#' @export
loop_transform <- function(fun) {
    fun_q <- rlang::enquo(fun)
    check_function_argument(fun_q)

    fun <- rlang::eval_tidy(fun)
    fun_name <- rlang::get_expr(fun_q)
    fun_env <- rlang::get_env(fun_q)
    fun_body <- user_transform(body(fun), fun_env)

    if (!can_loop_transform_body(fun_name, fun_body, fun_env)) {
        warning("Could not build a transformed function")
        return(fun)
    }
    info <- list(fun = fun, fun_name = fun_name)

    new_fun_body <- build_transformed_function(fun_body, info)
    rlang::new_function(
        args = formals(fun),
        body = new_fun_body,
        env = rlang::get_env(fun_q)
    )
}
