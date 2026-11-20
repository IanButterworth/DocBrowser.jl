---
name: julia-docs
description: Read Julia documentation from the command line with `docbrowser`, at the exact versions a project uses - the Julia manual, docstrings of Base, the standard libraries and the project's packages, their names, and where their methods are defined. Use before searching the web for anything about a Julia function, type, macro, module or package, when writing or fixing Julia code, or when a Julia name's behaviour, keyword arguments or exports are in doubt.
---

# Julia documentation with docbrowser

`docbrowser` prints the pages of DocBrowser.jl as plain text. Its answers match the Julia
version and the package versions of the project, and need no network, so prefer it to the web
and to memory for anything about Julia names.

If `docbrowser` is not on the `PATH`, look in `~/.julia/bin`. Otherwise install it with
`julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/IanButterworth/DocBrowser.jl")'`,
or, in an environment that has DocBrowser, use `julia --project -m DocBrowser` in its place.

## Commands

Run them in the project's directory, or pass `--project PATH`.

- `docbrowser find <words>`: names and manual sections that match, best first, one a line.
  Each line starts with something `show` takes. `--text` also searches the text of docstrings
  and of the manual, for when the name is not known.
- `docbrowser show <query>`: one page. A query is a name (`Base.sort!`, `DataFrames.select`),
  a module (`Base.Iterators`), or a place in the manual (`manual/arrays#Broadcasting`,
  `stdlib/Random`, `base/sort`). `show manual` lists the pages of the manual. The first line
  gives the version the page is about.
- `docbrowser names <module>`: the names of a module, by kind, and whether each is exported
  or public. `--internal` adds the others.

## Reading pages without wasting context

- For a long page, such as a manual chapter, run `show <query> --outline` first. It lists the
  numbered headings. Then `show <query> --section N` gives only that part.
- For a function with many docstrings or a very long one, `show <query> --brief` gives the
  signature and first paragraph of each docstring. When the docstrings come from several
  modules, as when a package adds a method to a function of `Base`, each starts with a
  `From Module:` line, and the outline says which one each heading is in.
- A mistyped option is an error, with exit code 2; it is never silently ignored.
- Links in a page end in a number, as in `sortslices[2]`. The `Links:` list at the end gives
  what each number leads to, in a form `show` takes, and for a page of a manual, its file.
- Each page's `Path:` line gives the file it comes from: the Markdown of a manual page, or the
  source file and line of a docstring. `find` gives the file of each manual section too. These
  are local files of the installed versions, so read or search them directly, for example with
  `grep`, when that is quicker than more `show` commands.
- A docstring page ends with its methods and the file and line where each is defined. Read
  that file when the docstring does not answer the question.

## Packages that are not loaded

The project's packages are not loaded by default, because loading runs their code. Until then,
`show` gives what the package's source documents, such as its README, and `find` does not see
its names. Add `--load` to `show` or `names` to load the package and read its docstrings. Only
do this for packages the project already depends on.
