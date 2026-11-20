# The manual of a package that is installed without it, as a package in a subdirectory of a
# repository is when the manual is elsewhere in the repository. It is downloaded on request from
# the repository, at the release whose package directory has the tree hash of the installed one.

const PKG = PkgId(UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"), "Pkg")

# Where the downloaded manual of the package installed at `dir` is kept, by the name of the
# package and of its directory, which differs between versions.
fetched_docs_rel(dir::String) = joinpath("scratchspaces", string(PkgId(@__MODULE__).uuid), "pkgdocs",
                                         basename(dirname(dir)), basename(dir))

function fetched_docs_dir(dir::String)
    for depot in DEPOT_PATH
        d = joinpath(depot, fetched_docs_rel(dir))
        isdir(joinpath(d, "docs")) && return d
    end
    return nothing
end

# The manual of the package at `dir`: its own, or else the one downloaded for it.
function own_or_fetched_docs(dir::String)
    docs = package_docs(dir)
    isempty(docs.pages) || return docs
    f = fetched_docs_dir(dir)
    return f === nothing ? docs : package_docs(f)
end

"""
    DocBrowser.fetch_package_docs(pkg) -> String

Download the manual of package `pkg` (a module, or the name of a package of the active project)
when it is not installed with the package, as when the package is in a subdirectory of a
repository whose manual is elsewhere in it, like GLMakie's in Makie.jl. The manual is taken
from the release of the installed version: the tag at which the package's directory has the
tree hash of the installed one. Returns where it is kept. Only GitHub repositories are
supported; a `GITHUB_TOKEN` in the environment raises GitHub's limit on requests.
"""
function fetch_package_docs(pkg::Union{Module,AbstractString})
    id = pkg isa Module ? PkgId(pkg) : Base.identify_package(String(pkg))
    id === nothing && error("$pkg is not a package of the active project")
    dir = pkg isa Module ? pkgdir(pkg) : unloaded_dir(id)
    dir === nothing && error("$(id.name) is not installed")
    return fetch_package_docs(id, dir)
end

function fetch_package_docs(id::PkgId, dir::String)
    pkg = dynamic(Base.require_stdlib)(PKG)
    repo, subdir = registry_place(pkg, id)
    m = match(r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?$", repo)
    m === nothing && error("only manuals in GitHub repositories can be downloaded, and $(id.name)'s is at $repo")
    owner, name = String(m[1]), String(m[2])
    isempty(subdir) && error("$(id.name) is at the top of its repository, so its manual would be installed with it")
    hash = bytes2hex(Base.invokelatest(pkg.GitTools.tree_hash, dir)::Vector{UInt8})
    tag = release_tag(owner, name, subdir, hash, dir)
    tag === nothing && error("no release of $owner/$name has $(id.name) as installed")
    # The manual is in `docs`, at the top of the repository, unless the package says where.
    source = docs_source(dir)
    src = source === nothing ? "docs/src" : normpath(joinpath(subdir, source))
    startswith(src, "..") && error("$(id.name) names a manual outside its repository")
    docs = dirname(src)
    files = [f for f in repo_tree(owner, name, tag, docs) if
             startswith(f, relpath(src, docs) * "/") && endswith(f, ".md") || !occursin('/', f) && endswith(f, ".jl")]
    isempty(files) && error("$owner/$name has no manual at $src in $tag")
    target = joinpath(first(DEPOT_PATH), fetched_docs_rel(dir))
    tmp = mktempdir(mkpath(dirname(target)))
    try
        asyncmap(files; ntasks=16) do f
            path = joinpath(tmp, "docs", f)
            mkpath(dirname(path))
            download_url("https://raw.githubusercontent.com/$owner/$name/$tag/$docs/$f", path)
        end
        write(joinpath(tmp, "source.txt"), "$owner/$name $tag $docs\n")
        mv(tmp, target; force=true)
    catch
        rm(tmp; force=true, recursive=true)
        rethrow()
    end
    return target
end

# For a package installed without a manual: a button that downloads it, if there is one.
add_fetch_line!(pb::PageBuilder) =
    addline!(pb, "  ", ("manual ", :REPL_DocBrowser_dim), ("not installed", :REPL_DocBrowser_dim), ("  ", nothing),
             ("↓ download it from the repository", nothing, ToggleTarget(:fetch_docs)))

# The repository and subdirectory of package `id`, from the registries Pkg can reach.
function registry_place(pkg::Module, id::PkgId)
    reg = pkg.Registry
    for r in Base.invokelatest(reg.reachable_registries)
        Base.invokelatest(haskey, r, id.uuid)::Bool || continue
        entry = Base.invokelatest(getindex, r, id.uuid)
        # Pkg 1.13 reads the entry through its registry; older versions read it alone.
        info = Base.invokelatest(applicable, reg.registry_info, r, entry)::Bool ?
            Base.invokelatest(reg.registry_info, r, entry) : Base.invokelatest(reg.registry_info, entry)
        repo = info.repo
        repo isa AbstractString || continue
        subdir = info.subdir
        return String(repo), subdir isa AbstractString ? String(subdir) : ""
    end
    error("$(id.name) is not in any registry")
end

# Where the package says its manual is, as `source` in the `[docs]` section of its project file.
function docs_source(dir::String)
    file = joinpath(dir, "Project.toml")
    isfile(file) || return nothing
    docs = get(Base.parsed_toml(file), "docs", nothing)
    docs isa AbstractDict || return nothing
    s = get(docs, "source", nothing)
    return s isa String ? s : nothing
end

# The tag or commit at which the package's directory has tree hash `hash`. A package that pins
# the exact version of a package of the same repository, as Makie's backends do, is released
# with it, so that version's tag is tried first.
function release_tag(owner, name, subdir, hash, dir)
    refs = String[]
    project = Base.parsed_toml(joinpath(dir, "Project.toml"))
    v = get(project, "version", nothing)
    for (_, c) in get(project, "compat", Dict())
        c isa String && (m = match(r"^=\s*(\d+\.\d+\.\d+)$", c)) !== nothing && push!(refs, "v" * m[1])
    end
    v isa String && push!(refs, "$(basename(subdir))-v$v", "v$v")
    # A package released on its own, as SciML's are, is often at a commit with no tag: one of
    # the latest that changed its directory.
    commits = github_get("repos/$owner/$name/commits?path=$subdir&per_page=15")
    append!(refs, (m[1] for m in eachmatch(r"\"sha\":\s*\"([0-9a-f]{40})\",\s*\"node_id\"", commits)))
    tags = github_get("repos/$owner/$name/tags?per_page=10")
    append!(refs, (m[1] for m in eachmatch(r"\"name\":\s*\"([^\"]+)\"", tags)))
    parent, base = dirname(subdir), basename(subdir)
    for ref in unique!(refs)[1:min(end, 30)]
        sha = try
            entry_sha(github_get("repos/$owner/$name/contents/$parent?ref=$ref"), base)
        catch err
            is_not_found(err) || rethrow()
            nothing
        end
        sha == hash && return ref
    end
    return nothing
end

# The paths of the files under `path` in the repository at `ref`.
function repo_tree(owner, name, ref, path)
    sha = entry_sha(github_get("repos/$owner/$name/contents/$(dirname(path))?ref=$ref"), basename(path))
    sha === nothing && return String[]
    tree = github_get("repos/$owner/$name/git/trees/$sha?recursive=1")
    return [String(m[1]) for m in eachmatch(r"\"path\":\s*\"([^\"]+)\",\s*\"mode\":\s*\"\d+\",\s*\"type\":\s*\"blob\"", tree)]
end

# The tree hash of the entry `base` in a listing of a directory from GitHub's contents API.
function entry_sha(listing::String, base::AbstractString)
    for m in eachmatch(r"\{[^{}]*\"name\":\s*\"([^\"]+)\"[^{}]*\"sha\":\s*\"([0-9a-f]{40})\"", listing)
        m[1] == base && return String(m[2])
    end
    return nothing
end

"""
    DocBrowser.explain_docs(pkg; online=false, io=stdout)

Say where the browser looked for the documentation of package `pkg` (a module, or the name of
a package of the active project), what it found, and why it did not find more: the manual in
the package's source, its list of pages, a downloaded manual, the `[docs]` section of its
project file, its repository, and the link to its hosted documentation. With `online`, it also
looks for the release of the installed version in the repository, as downloading the manual
does. For package authors, it says what would let the browser find more.
"""
function explain_docs(pkg::Union{Module,AbstractString}; online::Bool=false, io::IO=stdout)
    id = pkg isa Module ? PkgId(Base.moduleroot(pkg)) : Base.identify_package(String(pkg))
    id === nothing && return println(io, "$pkg is not a package of the active project.")
    dir = pkg isa Module ? pkgdir(pkg) : unloaded_dir(id)
    dir === nothing && return println(io, "$(id.name) is not installed.")
    project = isfile(joinpath(dir, "Project.toml")) ? Base.parsed_toml(joinpath(dir, "Project.toml")) : Dict{String,Any}()
    v = get(project, "version", nothing)
    println(io, id.name, v isa String ? " $v" : "", "  ", contractuser(dir))
    line(what, text) = println(io, "  ", rpad(what, 16), text)
    hints = String[]
    # the manual in the package's source
    docs = package_docs(dir)
    if isdir(joinpath(dir, "docs"))
        scripts = filter(f -> endswith(f, ".jl"), readdir(joinpath(dir, "docs")))
        lists = [(f, something(doc_page_list(read(joinpath(dir, "docs", f), String)), [])) for f in scripts]
        best = isempty(lists) ? nothing : argmax(x -> length(x[2]), lists)
        line("docs/", "$(length(docs.pages)) pages of a manual")
        if best === nothing || isempty(best[2])
            line("page list", isempty(scripts) ? "no build script in docs/" :
                 "none that is a literal list in $(join(scripts, ", ")); the pages are in file order")
        else
            line("page list", "$(length(best[2])) pages, from docs/$(best[1])")
        end
        isempty(docs.missing) || line("missing", "$(length(docs.missing)) listed pages are not in the source, " *
                                      "such as $(join(first(docs.missing, 3), ", "))")
        isempty(docs.generator) || line("generated", "some pages are written by $(docs.generator) when the docs are built")
    else
        line("docs/", "not in the package's directory")
    end
    # what the package says, and a downloaded manual
    section = get(project, "docs", nothing)
    if section isa AbstractDict
        line("[docs]", join(("$k = $(repr(section[k]))" for k in ("url", "source") if haskey(section, k)), ", "))
    else
        line("[docs]", "none in its project file")
    end
    fetched = fetched_docs_dir(dir)
    if fetched === nothing
        line("downloaded", "none")
    else
        line("downloaded", "$(length(package_docs(fetched).pages)) pages, from $(strip(read(joinpath(fetched, "source.txt"), String)))")
    end
    # where it comes from
    place = try
        registry_place(dynamic(Base.require_stdlib)(PKG), id)
    catch err
        err isa InterruptException && rethrow()
        line("repository", first_line(err))
        nothing
    end
    if place !== nothing
        repo, subdir = place
        line("repository", repo * (isempty(subdir) ? "" : ", in its subdirectory $subdir"))
        if isempty(docs.pages) && fetched === nothing && !isempty(subdir)
            push!(hints, "The manual is not installed with $(id.name), as Pkg installs only its directory. " *
                         "`DocBrowser.fetch_package_docs(\"$(id.name)\")`, or the button on its page, downloads it " *
                         "from $(section isa AbstractDict && haskey(section, "source") ? section["source"] : "docs/src at the top of the repository").")
            section isa AbstractDict && haskey(section, "source") ||
                push!(hints, "Its authors can say where its manual is with `[docs] source = \"../docs/src\"` " *
                             "in its project file, if it is not in docs/src at the top of the repository.")
        end
        if online && !isempty(subdir)
            m = match(r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?$", repo)
            if m === nothing
                line("release", "not looked for, as only GitHub repositories are supported")
            else
                hash = bytes2hex(Base.invokelatest(dynamic(Base.require_stdlib)(PKG).GitTools.tree_hash, dir)::Vector{UInt8})
                ref = try
                    something(release_tag(String(m[1]), String(m[2]), subdir, hash, dir), "none of the likely tags and commits has its tree hash $hash")
                catch err
                    err isa InterruptException && rethrow()
                    "could not be looked for: " * first_line(err) *
                        (isempty(get(ENV, "GITHUB_TOKEN", "")) ? " (a GITHUB_TOKEN raises GitHub's limit on requests)" : "")
                end
                line("release", ref)
            end
        end
    end
    # the hosted documentation
    url = docs_url(dir)
    own = section isa AbstractDict && haskey(section, "url")
    line("hosted docs", url === nothing ? "no link to them in its README" : "$url, from its " * (own ? "[docs] section" : "README"))
    url === nothing && !own &&
        push!(hints, "Its authors can link its hosted docs with `[docs] url = \"…\"` in its project file.")
    for h in hints
        println(io, "\n", h)
    end
    return nothing
end

function github_get(path::String)
    headers = ["Accept" => "application/vnd.github+json", "User-Agent" => "DocBrowser.jl"]
    token = get(ENV, "GITHUB_TOKEN", "")
    isempty(token) || push!(headers, "Authorization" => "Bearer $token")
    io = IOBuffer()
    Base.invokelatest(downloader().download, "https://api.github.com/" * path, io; headers)
    return String(take!(io))
end
