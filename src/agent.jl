## Plain text, for programs and AI agents ##

# The pages are built by a browser that is never shown.
const HEADLESS = Ref{Any}(nothing)
# Whether the command line is running, which changes how the text says to do something.
const CLI = Ref(false)
# Why Julia's manual is missing, if it could not be downloaded.
const MANUAL_NOTE = Ref{Union{Nothing,String}}(nothing)

function headless_browser()
    b = HEADLESS[]
    b isa Browser && return b
    ensure_manual()
    out = IOContext(IOBuffer(), :displaysize => (40, 120), :color => false)
    b = Browser(REPL.Terminals.TTYTerminal("", IOBuffer(), out, IOBuffer()))
    HEADLESS[] = b
    return b
end

# The manual is downloaded the first time it is needed, as the browser does when it first opens.
function ensure_manual()
    installed_manual_dir() === nothing || return
    isfile(joinpath(downloaded_manual_dir(), "pages.toml")) && return
    Base.generating_output() && return
    println(stderr, "Downloading Julia's manual for this version of Julia, which is done once...")
    try
        download_manual()
    catch err
        err isa InterruptException && rethrow()
        MANUAL_NOTE[] = "Julia's manual is not available, as it could not be downloaded: " * first_line(err)
    end
    return
end

load_hint() = CLI[] ? "run this again with `--load`" : "call this again with `load=true`"
search_hint() = CLI[] ? "search for it with `docbrowser find`" : "search for it with `DocBrowser.find_docs`"

"""
    DocBrowser.lookup(query; outline=false, section=0, width=100, context=Main, load=false) -> String

The page that the browser shows for `query`, as plain text. `query` is a name such as
`Base.sort!` or `Plots.plot`, a place in a manual such as `manual/arrays#Broadcasting`,
`stdlib/Random` or the path of a Markdown file, or anything that `docs: ` takes at the
`help?>` prompt.

Links in the text end in a number, as in `sort[3]`, and the list at the end gives what each
links to, in a form that `lookup` takes. With `outline`, only the headings of the page are
listed, numbered; `section` gives the text under one of them.

A package of the active project that is not loaded stays unloaded, and its page shows what its
source documents, such as its README. With `load`, it is loaded first, which runs its code,
and then its docstrings can be read.
"""
function lookup(query::AbstractString; outline::Bool=false, section::Int=0, brief::Bool=false,
                width::Int=100, context::Module=Main, load::Bool=false)
    b = headless_browser()
    strip(query) in ("manual", "docs") && return manual_index(b)
    t = agent_target(b.cat, String(query), context)
    if t === nothing
        note = MANUAL_NOTE[] === nothing ? "" : "\n" * MANUAL_NOTE[]
        return "Nothing is called $(repr(query)); $(search_hint()).$note\n"
    end
    t isa URLTarget && return "$(query) is a web page: $(t.url)\n"
    if t isa LoadTarget && load
        Core.eval(Main, :(import $(Symbol(t.id.name))))
        HEADLESS[] = nothing # the catalog was made before the package was loaded
        return invokelatest(lookup, query; outline, section, brief, width, context)
    end
    key, k = page_key(b.cat, t)
    key === nothing && return "There is no page for $(repr(query)).\n"
    push!(get!(Set{Symbol}, b.flags, key), :extended)
    p = page(b, key, width)
    io = IOBuffer()
    title = something(place_ref(b.cat, key, 0), link_ref(b, key, key), key_title(b, key))
    v = page_version(key)
    println(io, "# ", title, v === nothing ? "" : "  ($v)")
    path = page_path(key, p)
    path === nothing || println(io, "Path: ", path)
    key isa LoadTarget && println(io, "(", key.id.name, " is not loaded, so its docstrings cannot be read. ",
                                  "To load it, which runs its code, ", load_hint(), ".)")
    if outline
        for (i, li) in enumerate(p.headings)
            from = docstring_from(p, li)
            println(io, "§", i, " ", strip(String(p.lines[li])), from === nothing ? "" : "  (from $from)")
        end
        isempty(p.headings) && println(io, "(this page has no headings)")
        return String(take!(io))
    end
    section == 0 && (section = k)
    section == 0 || section in eachindex(p.headings) || return "This page has no section $section.\n"
    part = section == 0 ? eachindex(p.lines) :
        (p.headings[section]:(section < length(p.headings) ? p.headings[section+1] - 1 : length(p.lines)))
    total = length(part)
    lines = filter(li -> !is_button_line(p, li), brief ? brief_lines(p, collect(part)) : collect(part))
    refs, numbers = link_numbers(b, key, p, lines)
    for li in lines
        text = String(p.lines[li])
        # the place in the margin of a block of code that copies it is not part of the text
        spots = [s for s in p.spots if s.line == li && !(s.target isa CodeTarget)]
        # A source location shows only its file's name, or its path from `~`, which a program
        # cannot always open.
        for s in spots
            s.target isa SourceTarget || continue
            full = string(s.target.file, ':', s.target.line)
            occursin(full, text) && continue
            short = string(contractuser(s.target.file), ':', s.target.line)
            text = replace(text, (occursin(short, text) ? short : string(basename(s.target.file), ':', s.target.line)) => full)
        end
        marks = Tuple{Int,String}[(last(s.cols), "[$(numbers[i])]") for (i, s) in enumerate(p.spots)
                                  if s.line == li && haskey(numbers, i)]
        println(io, rstrip(insert_marks(text, marks)))
    end
    brief && length(lines) < total && println(io, "\n(", total - length(lines), " more lines: drop `--brief`",
                                              " for all of it, or read one part with `--outline` and `--section`)")
    if !isempty(refs)
        println(io, "\nLinks:")
        for (n, ref) in enumerate(refs)
            println(io, "[", n, "] ", ref)
        end
    end
    return String(take!(io))
end

# The file that a page is read from, as a path a program can open: the Markdown of a page of a
# manual, the source of a docstring, or the directory of a package.
function page_path(@nospecialize(key), p::Page)
    key isa ManualTarget && return key.path
    key isa NameEntry && return p.source === nothing ? nothing : string(p.source.file, ':', p.source.line)
    key isa ModuleTarget && return something(pkgdir(key.mod), Some(nothing))
    key isa LoadTarget && return unloaded_dir(key.id)
    return nothing
end

# Whether line `li` only has buttons, such as the one that loads a package, which mean nothing
# in text. A button may have its key beside it.
function is_button_line(p::Page, li::Int)
    spots = [s for s in p.spots if s.line == li && !(s.target isa CodeTarget)]
    isempty(spots) && return false
    all(s -> s.target isa ToggleTarget || s.target isa LoadTarget, spots) || return false
    return textwidth(strip(String(p.lines[li]))) - sum(s -> length(s.cols), spots) <= 12
end

# The version of what a page documents: Julia's, or the package's.
function page_version(@nospecialize(key))
    m = key isa NameEntry ? key.mod : key isa ModuleTarget ? key.mod : nothing
    if key isa LoadTarget
        file = Base.locate_package(key.id)
        file === nothing && return nothing
        proj = Base.current_project(dirname(dirname(file)))
        v = proj === nothing ? nothing : get(Base.parsed_toml(proj), "version", nothing)
        return v isa String ? "$(key.id.name) $v" : nothing
    end
    key isa ManualTarget && return startswith(key.path, manual_dir()) ? "Julia $VERSION" : nothing
    m === nothing && return nothing
    root = Base.moduleroot(m)
    root === Main && return nothing
    (root in (Base, Core) || is_stdlib(PkgId(root))) && return "Julia $VERSION"
    v = pkgversion(root)
    return v === nothing ? nothing : "$(nameof(root)) $v"
end

# The module that the docstring around line `li` comes from, when the page has the docstrings
# of several modules, which it labels.
function docstring_from(p::Page, li::Int)
    for k in li:-1:1
        m = match(r"^\s*From (\S+):$", String(p.lines[k]))
        m === nothing || return m[1]
    end
    return nothing
end

# The start of each docstring among `lines`: its signature and its first paragraph.
function brief_lines(p::Page, lines::Vector{Int})
    keep = Int[]
    # the header of a page ends with a rule; each docstring after it starts a part
    rule = findfirst(li -> occursin(r"^\s*─{8,}\s*$", String(p.lines[li])), lines)
    rule === nothing || append!(keep, lines[1:rule])
    taking, prose = true, false
    for li in lines[something(rule, 0)+1:end]
        text = String(p.lines[li])
        if occursin(r"^\s*From (\S+):$", text)
            taking, prose = true, false
            # the blank line that sets the label apart from the docstring before
            li - 1 in lines && !(li - 1 in keep) && isempty(strip(String(p.lines[li-1]))) && push!(keep, li - 1)
        elseif taking && isempty(strip(text)) && prose
            taking = false
        elseif taking && !isempty(strip(text)) && !is_code_line(p.lines[li])
            prose = true
        end
        taking && push!(keep, li)
    end
    return keep
end

# The pages of Julia's manual, by part, each with what `lookup` takes for it.
function manual_index(b::Browser)
    io = IOBuffer()
    println(io, "# Julia's manual  (Julia $VERSION)")
    isempty(b.cat.manual) && MANUAL_NOTE[] !== nothing && println(io, MANUAL_NOTE[])
    part = nothing
    for pg in b.cat.manual
        title = pg.role === :devdocs && !isempty(pg.group) ? pg.group : getfield(SIDEBAR_TITLES, pg.role)
        if title != part
            part = title
            println(io, "\n", title)
        end
        println(io, "  ", something(page_ref(pg.path), pg.path), "  ", pg.title)
    end
    return String(take!(io))
end

"""
    DocBrowser.find_docs(query; text=false, internal=false, limit=20) -> String

Names and sections of the manuals that match `query`, best first, one a line, each in a form
that [`lookup`](@ref) takes. With `text`, the words are looked for in docstrings and in the
text of the manuals too, not only in names and headings.
"""
function find_docs(query::AbstractString; text::Bool=false, internal::Bool=false, limit::Int=20)
    b = headless_browser()
    io = IOBuffer()
    names = search(b.cat, query; internal, limit)
    text && (names = unique!(vcat(names, search_text(b.cat, query; internal, limit))))
    for e in first(names, limit)
        print(io, display_name(e), "  ", e.kind, ", ", e.vis)
        from = reexported_from(e)
        from === nothing || print(io, ", from ", display_name(from))
        e.documented || print(io, ", undocumented")
        println(io)
    end
    for h in first(search_manual(b.cat, query; text), limit)
        ref = something(page_ref(h.path), h.path)
        isempty(h.heading) || (ref *= "#" * slugify(h.heading))
        # and the file, which can be read directly, unless that is what `show` takes
        println(io, ref, "  manual: ", hit_title(b.cat, h), startswith(ref, h.path) ? "" : "  " * h.path)
    end
    out = String(take!(io))
    return isempty(out) ? "Nothing matches $(repr(query)).\n" : out
end

"""
    DocBrowser.list_names(mod; internal=false, load=false) -> String

The names of module `mod` (a module, or its name), by kind. Each says whether it is exported
or public, which package it comes from when it is re-exported, and whether it is documented.
"""
function list_names(mod::Union{Module,AbstractString}; internal::Bool=false, load::Bool=false)
    b = headless_browser()
    if !(mod isa Module)
        t = agent_target(b.cat, String(mod), Main)
        if t isa LoadTarget && isempty(t.then)
            load || return "$(mod) is not loaded. To load it, which runs its code, $(load_hint()).\n"
            Core.eval(Main, :(import $(Symbol(t.id.name))))
            HEADLESS[] = nothing
            return invokelatest(list_names, mod; internal)
        end
        t isa ModuleTarget || return "$(mod) is not a module.\n"
        mod = t.mod
    end
    io = IOBuffer()
    println(io, "# ", display_name(mod))
    dir = pkgdir(mod)
    dir === nothing || println(io, "Path: ", dir)
    kind = :none
    for e in module_entries(b.cat, mod)
        (internal || e.vis !== :internal) && !e.deprecated || continue
        if e.kind !== kind
            kind = e.kind
            println(io, "\n", kind_title(kind))
        end
        print(io, "  ", e.name, "  ", e.vis)
        from = reexported_from(e)
        from === nothing || print(io, ", from ", display_name(from))
        e.documented || print(io, ", undocumented")
        println(io)
    end
    return String(take!(io))
end

# What `query` names: a place, a file of a manual, or a name in a loaded module or in a
# package of the active project that is not loaded.
function agent_target(cat::Catalog, query::String, ctx::Module)
    s = strip(query)
    isempty(s) && return nothing
    t = place_target(s, cat)
    t === nothing || return t
    m = match(r"^(.+?\.md)(?:#(.*))?$", s)
    m !== nothing && isfile(m[1]) && return ManualTarget(normpath(m[1]), something(m[2], ""))
    parts = split(s, '.')
    if all(p -> !isempty(p) && Base.isidentifier(p), parts[1:end-1]) && valid_name_part(parts[end])
        roots = Module[ctx, Main, Base, Core]
        for m in values(Base.loaded_modules)
            nameof(m) === Symbol(parts[1]) && pushfirst!(roots, m)
        end
        for root in unique!(roots)
            t = name_target(root, root === ctx || root === Main || root === Base || root === Core ?
                                  parts : parts[2:end])
            t === nothing || return t
        end
        for id in cat.unloaded
            id.name == parts[1] && return LoadTarget(id, length(parts) > 1 ? join(parts[2:end], '.') : "")
        end
    end
    return place_target("docs: " * s, cat)
end

function name_target(root::Module, parts)
    isempty(parts) && return ModuleTarget(root)
    m = root
    for p in parts[1:end-1]
        visible_binding(m, Symbol(p)) || return nothing
        v = getglobal(m, Symbol(p))
        v isa Module || return nothing
        m = v
    end
    sym = Symbol(parts[end])
    visible_binding(m, sym) || return nothing
    v = getglobal(m, sym)
    return v isa Module ? ModuleTarget(v) : NameTarget(m, sym)
end

# The page to show for a target, and the heading of it to start at.
function page_key(cat::Catalog, @nospecialize(t))
    t isa ModuleTarget && return (t, 0)
    t isa LoadTarget && return (t, 0)
    t isa ManualTarget && return (ManualTarget(t.path, ""), anchor_heading(cat, t.path, t.anchor))
    if t isa NameTarget
        e = @attempt classify(cat, t.mod, t.name) nothing
        if e === nothing
            # an internal name that the module only imported is listed under its owner
            owner = @attempt which(t.mod, t.name) t.mod
            e = @attempt classify(cat, owner, t.name) nothing
        end
        return (e, 0)
    end
    return (nothing, 0)
end

# A number for each link among `lines` that leads somewhere `lookup` can go, the same number
# for links to the same place.
function link_numbers(b::Browser, key, p::Page, lines)
    refs = String[]
    numbers = Dict{Int,Int}()
    for (i, s) in enumerate(p.spots)
        s.line in lines || continue
        ref = link_ref(b, key, s.target)
        ref === nothing && continue
        n = findfirst(==(ref), refs)
        n === nothing && (push!(refs, ref); n = length(refs))
        numbers[i] = n
    end
    return refs, numbers
end

function link_ref(b::Browser, key, @nospecialize(t))
    t isa NameTarget && return string(display_name(t.mod), '.', t.name)
    t isa ModuleTarget && return display_name(t.mod)
    t isa URLTarget && return t.url
    t isa LoadTarget && return isempty(t.then) ? t.id.name : string(t.id.name, '.', t.then)
    if t isa ManualTarget
        # what `show` takes, then the file, which can be read directly
        ref = page_ref(t.path)
        ref === nothing && return isempty(t.anchor) ? t.path : string(t.path, '#', t.anchor)
        return string(ref, isempty(t.anchor) ? "" : "#" * t.anchor, "  ", t.path)
    end
    if t isa AnchorTarget
        ref = key isa ManualTarget ? place_ref(b.cat, key, t.heading) : nothing
        return ref === nothing ? "§$(t.heading) of this page (section $(t.heading))" : ref
    end
    return nothing
end

# `s` with each text put after the column it goes with.
function insert_marks(s::String, marks::Vector{Tuple{Int,String}})
    isempty(marks) && return s
    sort!(marks)
    io = IOBuffer()
    col, k = 0, 1
    for c in s
        print(io, c)
        col += textwidth(c)
        while k <= length(marks) && marks[k][1] <= col
            print(io, marks[k][2])
            k += 1
        end
    end
    for j in k:length(marks)
        print(io, marks[j][2])
    end
    return String(take!(io))
end

const AGENT_USAGE = """
    Julia's documentation, as plain text: the manual, and the docstrings of the packages in a
    project, at the versions it uses.

    usage: docbrowser <command> [options]     (or: julia -m DocBrowser <command> [options])

      find <words> [--text] [--internal] [--limit N]
          Names and manual sections that match, one a line, each something `show` takes.
          `--text` looks in the text of docstrings and the manual too.
      show <query> [--outline] [--section N] [--brief] [--width N] [--load]
          The page for a name (`Base.sort!`), a module (`Plots`) or a place in a manual
          (`manual/arrays#Broadcasting`), as plain text. Links end in a number, listed at the
          end in a form `show` takes. `--outline` lists the numbered headings of a long page,
          `--section N` gives one of them, and `--brief` the start of each docstring.
          `show manual` lists the pages of Julia's manual. `Path:` gives the local file the
          page comes from, which can be read directly.
      names <module> [--internal] [--load]
          The names of a module, by kind, and whether each is exported or public.

    The project is the one the current directory is in, or the one `--project PATH` names. Its
    packages are not loaded without `--load`, which runs their code; until then their pages show
    what their source documents, such as the README. Julia's manual is downloaded the first
    time it is needed.
    """

# The options of each command, and those that take a value.
const AGENT_OPTIONS = Dict("show" => ["--outline", "--section", "--brief", "--width", "--load"],
                           "find" => ["--text", "--internal", "--limit"],
                           "names" => ["--internal", "--load"])
const VALUE_OPTIONS = ("--section", "--width", "--limit", "--project")

# A Pkg app runs in an environment of its own, but the documentation to show is that of the
# project it is run in, as `--project=@.` finds it, unless Julia was given a project already.
function use_project!(path::Union{Nothing,String})
    path === nothing && Base.ACTIVE_PROJECT[] !== nothing && return
    dir = abspath(something(path, pwd()))
    proj = isfile(dir) ? dir : Base.current_project(dir)
    proj === nothing && (proj = Base.load_path_expand("@v#.#"))
    proj === nothing && return
    for env in ("@stdlib", "@v#.#", proj)
        env in LOAD_PATH || pushfirst!(LOAD_PATH, env)
    end
    Base.ACTIVE_PROJECT[] = proj
    return
end

function (@main)(args::Vector{String})
    any(in(("help", "--help", "-h")), args[1:min(1, end)]) && (print(stdout, AGENT_USAGE); return 0)
    CLI[] = true
    # options can come before or after the command
    words = String[]
    flags = Set{String}()
    values = Dict{String,String}()
    i = 1
    while i <= length(args)
        a = args[i]
        if a in VALUE_OPTIONS
            i < length(args) || return usage_error("`$a` needs a value")
            values[a] = args[i+1]
            i += 1
        elseif startswith(a, "--project=")
            values["--project"] = String(chopprefix(a, "--project="))
        elseif startswith(a, "--")
            push!(flags, a)
        else
            push!(words, a)
        end
        i += 1
    end
    isempty(words) && (print(stderr, AGENT_USAGE); return 1)
    cmd = popfirst!(words)
    haskey(AGENT_OPTIONS, cmd) || return usage_error("there is no command `$cmd`")
    isempty(words) && return usage_error("`$cmd` needs something to look for")
    for opt in Iterators.flatten((flags, keys(values)))
        opt == "--project" || opt in AGENT_OPTIONS[cmd] || return usage_error("`$cmd` has no option `$opt`")
    end
    for (opt, v) in values
        opt == "--project" || tryparse(Int, v) !== nothing || return usage_error("`$opt` needs a number, not `$v`")
    end
    number(flag, default) = something(tryparse(Int, get(values, flag, "")), default)
    use_project!(get(values, "--project", nothing))
    query = join(words, ' ')
    out = if cmd == "show"
        lookup(query; outline="--outline" in flags, section=number("--section", 0), brief="--brief" in flags,
               width=number("--width", 100), load="--load" in flags)
    elseif cmd == "find"
        find_docs(query; text="--text" in flags, internal="--internal" in flags, limit=number("--limit", 20))
    else
        list_names(query; internal="--internal" in flags, load="--load" in flags)
    end
    print(stdout, out)
    return 0
end

function usage_error(msg::String)
    println(stderr, "docbrowser: ", msg, ". See `docbrowser --help`.")
    return 2
end
