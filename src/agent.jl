## Plain text, for programs and AI agents ##

# The pages are built by a browser that is never shown.
const HEADLESS = Ref{Any}(nothing)

function headless_browser()
    b = HEADLESS[]
    b isa Browser && return b
    out = IOContext(IOBuffer(), :displaysize => (40, 120), :color => false)
    b = Browser(REPL.Terminals.TTYTerminal("", IOBuffer(), out, IOBuffer()))
    HEADLESS[] = b
    return b
end

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
function lookup(query::AbstractString; outline::Bool=false, section::Int=0, width::Int=100,
                context::Module=Main, load::Bool=false)
    b = headless_browser()
    t = agent_target(b.cat, String(query), context)
    t === nothing && return "Nothing is called $(repr(query)); search for it instead.\n"
    t isa URLTarget && return "$(query) is a web page: $(t.url)\n"
    if t isa LoadTarget && load
        Core.eval(Main, :(import $(Symbol(t.id.name))))
        HEADLESS[] = nothing # the catalog was made before the package was loaded
        return invokelatest(lookup, query; outline, section, width, context)
    end
    key, k = page_key(b.cat, t)
    key === nothing && return "There is no page for $(repr(query)).\n"
    push!(get!(Set{Symbol}, b.flags, key), :extended)
    p = page(b, key, width)
    io = IOBuffer()
    println(io, "# ", something(place_ref(b.cat, key, 0), link_ref(b, key, key), key_title(b, key)))
    key isa LoadTarget && println(io, "(", key.id.name, " is not loaded. Look this up again with ",
                                  "`load=true`, or `--load`, to load it and read its docstrings.)")
    if outline
        for (i, li) in enumerate(p.headings)
            println(io, "§", i, " ", strip(String(p.lines[li])))
        end
        isempty(p.headings) && println(io, "(this page has no headings)")
        return String(take!(io))
    end
    section == 0 && (section = k)
    lines = eachindex(p.lines)
    if section != 0
        section in eachindex(p.headings) || return "This page has no section $section.\n"
        stop = section < length(p.headings) ? p.headings[section+1] - 1 : length(p.lines)
        lines = p.headings[section]:stop
    end
    refs, numbers = link_numbers(b, key, p, lines)
    for li in lines
        text = String(p.lines[li])
        # the place in the margin of a block of code that copies it is not part of the text
        spots = [s for s in p.spots if s.line == li && !(s.target isa CodeTarget)]
        # buttons, such as the one that loads a package, mean nothing here
        # (a button may have its key beside it)
        !isempty(spots) && all(s -> s.target isa ToggleTarget || s.target isa LoadTarget, spots) &&
            textwidth(strip(text)) - sum(s -> length(s.cols), spots) <= 12 && continue
        # a source location shows only its file's name, which a program cannot open
        for s in spots
            s.target isa SourceTarget || continue
            full = string(contractuser(s.target.file), ':', s.target.line)
            occursin(full, text) || (text = replace(text, string(basename(s.target.file), ':', s.target.line) => full))
        end
        marks = Tuple{Int,String}[(last(s.cols), "[$(numbers[i])]") for (i, s) in enumerate(p.spots)
                                  if s.line == li && haskey(numbers, i)]
        println(io, rstrip(insert_marks(text, marks)))
    end
    if !isempty(refs)
        println(io, "\nLinks:")
        for (n, ref) in enumerate(refs)
            println(io, "[", n, "] ", ref)
        end
    end
    p.source === nothing || println(io, "\nSource: ", p.source.file, ":", p.source.line)
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
        println(io, ref, "  manual: ", hit_title(b.cat, h))
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
            load || return "$(mod) is not loaded. List its names with `load=true`, or `--load`, to load it.\n"
            Core.eval(Main, :(import $(Symbol(t.id.name))))
            HEADLESS[] = nothing
            return invokelatest(list_names, mod; internal)
        end
        t isa ModuleTarget || return "$(mod) is not a module.\n"
        mod = t.mod
    end
    io = IOBuffer()
    println(io, "# ", display_name(mod))
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
        ref = something(page_ref(t.path), t.path)
        return isempty(t.anchor) ? ref : string(ref, '#', t.anchor)
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
      show <query> [--outline] [--section N] [--width N] [--load]
          The page for a name (`Base.sort!`), a module (`Plots`) or a place in a manual
          (`manual/arrays#Broadcasting`), as plain text. Links end in a number, listed at the
          end in a form `show` takes. `--outline` lists the numbered headings of a long page,
          and `--section N` gives one of them.
      names <module> [--internal] [--load]
          The names of a module, by kind, and whether each is exported or public.

    The project is the one the current directory is in, or the one `--project PATH` names. Its
    packages are not loaded without `--load`, which runs their code; until then their pages show
    what their source documents, such as the README.
    """

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
    # options can come before or after the command
    words = String[]
    flags = Set{String}()
    values = Dict{String,String}()
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("--section", "--width", "--limit", "--project") && i < length(args)
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
    number(flag, default) = something(tryparse(Int, get(values, flag, "")), default)
    use_project!(get(values, "--project", nothing))
    cmd = popfirst!(words)
    query = join(words, ' ')
    out = if cmd == "show" && !isempty(query)
        lookup(query; outline="--outline" in flags, section=number("--section", 0), width=number("--width", 100),
               load="--load" in flags)
    elseif cmd == "find" && !isempty(query)
        find_docs(query; text="--text" in flags, internal="--internal" in flags, limit=number("--limit", 20))
    elseif cmd == "names" && !isempty(query)
        list_names(query; internal="--internal" in flags, load="--load" in flags)
    else
        print(stderr, AGENT_USAGE)
        return 1
    end
    print(stdout, out)
    return 0
end
