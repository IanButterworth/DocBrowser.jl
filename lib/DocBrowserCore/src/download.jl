# Julia's releases do not ship the Markdown source of the manual, so it is downloaded from the
# Julia repository on first use, at the commit this Julia was built from, and kept in the depot.

const JULIA_RAW = "https://raw.githubusercontent.com/JuliaLang/julia"

julia_ref() = (c = Base.GIT_VERSION_INFO.commit; isempty(c) ? "v$VERSION" : c)

downloaded_manual_dir() = joinpath(first(DEPOT_PATH), "scratchspaces", string(PkgId(@__MODULE__).uuid),
                                   "manual", julia_ref())

# The page lists of `doc/make.jl`, which are literal vectors of paths, as `pages.toml` has them.
function make_page_lists(src::AbstractString)
    lists = Dict{String,Any}("manual" => String[], "base" => String[], "devdocs" => Any[])
    paths(ex) = String[p for p in (x isa String ? x : Meta.isexpr(x, :call, 3) && x.args[1] === :(=>) &&
                                   x.args[3] isa String ? x.args[3] : nothing for x in ex.args) if p !== nothing]
    for ex in Meta.parseall(src).args
        Meta.isexpr(ex, :(=), 2) && Meta.isexpr(ex.args[2], :vect) || continue
        name, v = ex.args[1], ex.args[2]
        if name === :Manual
            lists["manual"] = paths(v)
        elseif name === :BaseDocs
            lists["base"] = paths(v)
        elseif name === :DevDocs
            for g in v.args
                Meta.isexpr(g, :call, 3) && g.args[1] === :(=>) && g.args[2] isa String &&
                    Meta.isexpr(g.args[3], :vect) || continue
                push!(lists["devdocs"], Dict{String,Any}("title" => g.args[2], "pages" => paths(g.args[3])))
            end
        end
    end
    return lists
end

function write_pages_toml(io::IO, lists)
    printlist(ps) = join(("    " * repr(p) for p in ps), ",\n")
    println(io, "manual = [\n", printlist(lists["manual"]), "\n]\n")
    println(io, "base = [\n", printlist(lists["base"]), "\n]\n")
    for g in lists["devdocs"]
        println(io, "[[devdocs]]\ntitle = ", repr(g["title"]), "\npages = [\n", printlist(g["pages"]), "\n]\n")
    end
end

"""
    DocBrowserCore.download_manual(; force=false) -> String

Download the Markdown source of Julia's manual for this version of Julia, and return the
directory it is kept in. The browser does this by itself the first time it opens.
"""
function download_manual(; force::Bool=false)
    dir = downloaded_manual_dir()
    isfile(joinpath(dir, "pages.toml")) && !force && return dir
    base = "$JULIA_RAW/$(julia_ref())"
    fetch(rel) = String(take!(Downloads.download("$base/$rel", IOBuffer())))
    lists = make_page_lists(fetch("doc/make.jl"))
    rels = [lists["manual"]; lists["base"]; (p for g in lists["devdocs"] for p in g["pages"])...]
    tmp = mktempdir(mkpath(dirname(dir)))
    try
        asyncmap(rels; ntasks=16) do rel
            path = joinpath(tmp, rel)
            mkpath(dirname(path))
            # a page that is missing is left out, as when it is not installed
            try
                Downloads.download("$base/doc/src/$rel", path)
            catch
                rm(path; force=true)
            end
        end
        # The release notes are at the top of the repository; the docs build copies them in.
        write(joinpath(tmp, "NEWS.md"), fetch("NEWS.md"))
        open(io -> write_pages_toml(io, lists), joinpath(tmp, "pages.toml"), "w")
        force && rm(dir; force=true, recursive=true)
        mv(tmp, dir; force=true)
    catch
        rm(tmp; force=true, recursive=true)
        rethrow()
    end
    return dir
end

# The download that a browser started, so that only one runs at a time.
const MANUAL_DOWNLOAD = Ref{Union{Nothing,Task}}(nothing)

# Start downloading the manual in the background, unless it is there or being downloaded.
# A download that fails is tried again the next time the browser opens.
function start_manual_download(on_done)
    MANUAL_DOWNLOAD[] === nothing || return nothing
    MANUAL_DOWNLOAD[] = @async try
        download_manual()
        Base.invokelatest(on_done)
    catch err
        @debug "Downloading the manual failed" exception=(err, catch_backtrace())
        MANUAL_DOWNLOAD[] = nothing
    end
    return nothing
end
