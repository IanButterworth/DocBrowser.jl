"""
    DocBrowser

Opens a full-window browser of Julia's manual and the documentation of every loaded module
from the REPL's help mode: press Enter at an empty `help?>` prompt.

Loading this package only sets up help mode. The browser itself, in DocBrowserCore, is loaded
the first time it is opened.
"""
module DocBrowser

import REPL

export browse

# Loaded on first use, so that having this package in `startup.jl` costs next to nothing.
core() = Base.require(@__MODULE__, :DocBrowserCore)

"""
    browse([term]; query=nothing, context=Main)
    browse([term,] x; context=Main)

Open the documentation browser, at `query` (a name, a search or a place in the docs) or at the
object `x`. Return the name that was being viewed when it was closed with `y`, or `nothing`.
"""
browse(args...; kwargs...) = Base.invokelatest(core().browse, args...; kwargs...)

"""
    DocBrowser.download_manual(; force=false) -> String

Download the Markdown source of Julia's manual for this version of Julia, and return the
directory it is kept in. The browser does this by itself the first time it opens.
"""
download_manual(; kwargs...) = Base.invokelatest(core().download_manual; kwargs...)

include("repl.jl")

__init__() = install_when_ready()

end
