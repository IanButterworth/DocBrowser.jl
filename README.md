# DocBrowser.jl

[![CI](https://github.com/IanButterworth/DocBrowser.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/IanButterworth/DocBrowser.jl/actions/workflows/CI.yml)

A full-window browser in the REPL for Julia's manual and the docstrings of every loaded module.
Press Enter at an empty `help?>` prompt to open it.

## Installation

```julia
pkg> add DocBrowser
```

Then load it in `~/.julia/config/startup.jl`, so that help mode opens the browser in every session:

```julia
using DocBrowser
```

Loading it takes about 2 ms: it only sets up help mode, and the browser itself is loaded the
first time you open it. Julia 1.12 and later are supported.

## Using it

- Enter at an empty `help?>` prompt opens the browser where it was last closed.
- Type a name and press Alt-Enter to open it at that name.
- `DocBrowser.browse()` and `DocBrowser.browse(x)` open it from code.

The browser has three panes:

- **Contents:** *Julia*, with its manual (*Manual*, *Base*, *Standard library*, *Developer docs*)
  and its own modules, then the loaded *Packages*, the active project's dependencies first, and
  then `Main`, where your own definitions are. Dependencies that are not loaded yet are listed
  too: select one and press Enter to load it.
- **Names:** the sections of a manual page, or the names in a module, grouped by kind. Each is
  marked `●` if exported, `○` if public, or `·` if internal. Press `i` to show internal and
  deprecated names. A package's own manual, if its source has one, is listed first.
- **Documentation:** the docstrings of a name, or a module's docstring or README, with its
  version, licence, repository and online docs. Functions list their methods, and types their
  fields, subtypes and constructors.

Names mentioned in a docstring are links, and so are mentions of packages such as `Example.jl`.
Extended help is folded away until you press `x`, and each example has a link that pastes its
code at the `julia>` prompt.

### Keys and mouse

- Arrow keys or `h` `j` `k` `l` move, Enter opens, Tab steps through a page's links, Backspace goes back.
- `/` searches the names of every loaded module, and Ctrl-T searches the text of their docstrings.
- `y` closes the browser and puts the name being viewed at the `julia>` prompt.
- `e` opens the source in your editor (`JULIA_EDITOR`), `w` changes the layout, `?` lists every key.
- In terminals that support it, click anything, scroll, and use the mouse's back and forward buttons.
  Right-click, Alt-click or Ctrl-click opens the source of a method, name, package or link.
- Drag across the documentation to copy text, double-click to copy a word, triple-click for a line.
  To select with your terminal instead, hold the key it uses for this (Shift in most terminals,
  Option in iTerm2, Fn in Terminal.app).

### Links to share

Press `c`, or click `⧉ link` above a page, to copy a link to it, such as
`help?> docs: manual/performance-tips#man-code-warntype`. Pasted at the `julia>` prompt, it
opens the browser at that place. In help mode you can type `docs:` and a page (`manual/variables`,
`stdlib/Pkg/environments`), with `#` and a heading if you like, or a name such as `Base.sum`. The
address of a page of docs.julialang.org or pkgdocs.julialang.org works too.

## The manual

Julia's releases do not include the Markdown source of the manual. The first time the browser
opens, it downloads it (about 1.7 MB) from the Julia repository, at the commit your Julia was
built from, and keeps it in the depot's scratch space. Contents shows *Manual loading…* until
that finishes, or *Manual failed*, whose page has a link to try again. If that commit is not on GitHub,
as for some local builds, the nearest version is downloaded instead, and its pages say so. To
download it ahead of time, for example before going offline, run `DocBrowser.download_manual()`.

The standard libraries, including Pkg, ship their manuals with their source, so those are
always there. So do most packages, in `docs/src`, in the order their `docs/make.jl` gives.
Pages that the documentation build writes, such as Literate tutorials, are not in the source,
and a notice on the package's manual pages says when some are missing.

## Settings

- `JULIA_DOCBROWSER_SEARCH_URL`: the search engine for packages whose repository the browser
  cannot find, with `%s` where the query goes, e.g. `https://www.google.com/search?q=%s`.
  The default is DuckDuckGo.

## How it hooks into the REPL

Julia has no hook for this, so on loading, the package changes the running REPL's help mode:
it binds Enter and Alt-Enter, and handles pasted `help?> docs: ...` lines. It also binds `?` at
the `julia>` prompt, to show a hint on the empty `help?>` prompt. Your own key bindings for
those keys are kept underneath and still run for everything else.

## Packages

This repository holds two packages:

- **DocBrowser**, at the top: the package to install. It sets up help mode and loads
  DocBrowserCore when the browser is first opened.
- **DocBrowserCore**, in [`lib/DocBrowserCore`](lib/DocBrowserCore): the browser itself.
  `DocBrowserCore.browse()` opens it without the help mode set-up.

## Origin

This started as a pull request to add the browser to Julia as a standard library,
[JuliaLang/julia#64993](https://github.com/JuliaLang/julia/pull/64993).
