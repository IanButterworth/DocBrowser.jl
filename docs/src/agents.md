# For AI agents

The pages are also available as plain text, so that coding agents can read the documentation
of the exact package versions a project uses, offline, instead of searching the web. Install
the `jldocs` command with Pkg's (experimental) app support, and put `~/.julia/bin` on your
`PATH`:

```
pkg> app add https://github.com/JuliaLang/DocBrowser.jl
```

```
jldocs find sort                         # names and manual sections that match
jldocs show Base.sort!                   # a page, with its links numbered
jldocs show Base.sort! --brief           # just each docstring's signature and first paragraph
jldocs show manual/arrays --outline      # the headings of a long page...
jldocs show manual/arrays --section 21   # ...and one of them
jldocs show GLMakie/                     # the pages of a package's manual
jldocs names Plots --load                # the names of a module
```

It works in the project of the current directory, or the one `--project PATH` names. It does
not load the project's packages unless asked to with `--load`, since that runs their code. Without
the app, `julia --project -m DocBrowser ...` does the same in an environment that has DocBrowser,
and in Julia [`DocBrowser.find_docs`](@ref), [`DocBrowser.lookup`](@ref) and
[`DocBrowser.list_names`](@ref) return the same text.

## What an agent does with it

Asked how to set the size of a GLMakie window, in a project that uses GLMakie, an agent might
run:

```
$ jldocs find px_per_unit
GLMakie/explanations/figure#The-px_per_unit-factor  manual of GLMakie: The px_per_unit factor  /…/docs/src/explanations/figure.md
(The names of a package of the project that is not loaded were not searched: GLMakie. …)

$ jldocs show GLMakie/explanations/figure --outline
# GLMakie/explanations/figure  (GLMakie 0.13.17)
Path: /…/docs/src/explanations/figure.md
§1 Figures
…
§7 Figure size and resolution
§8 The px_per_unit factor

$ jldocs show GLMakie/explanations/figure#The-px_per_unit-factor    # or --section 8
```

Every answer is for the versions the project uses, and says what it could not see, such as the
names of packages that are not loaded. Each page gives the local file it comes from as `Path:`,
so the agent can also read or `grep` the Markdown or source directly. A lookup that finds
nothing exits with 1, and a mistake in the command with 2, so an agent can tell them apart from
an answer.

## Telling agents about it

Agents use the tool when their instructions mention it. To have every agent you use know about
it, in every project, add a line to your global instructions: `~/.claude/CLAUDE.md` for Claude
Code, or `~/.codex/AGENTS.md` for Codex, for example:

```
For Julia documentation, run `jldocs find <words>` and `jldocs show <name>`
(see `jldocs --help`) before searching the web or relying on memory.
```

For one project, the same line goes in its `AGENTS.md` or `CLAUDE.md`. For more detail, such as
how to read long pages without filling the context, install the skill in
[`skills/julia-docs`](https://github.com/JuliaLang/DocBrowser.jl/tree/main/skills/julia-docs): for Claude Code, copy that directory to
`~/.claude/skills/julia-docs`.

