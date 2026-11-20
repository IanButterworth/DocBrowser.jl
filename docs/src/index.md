# [DocBrowser](@id man-docbrowser)

`DocBrowser` is a full-window browser of Julia's manual, the manuals of your packages, and the
docstrings of every loaded module. Open it by pressing Enter at an empty `help?>` prompt, or by
typing a name and pressing Alt-Enter to open it at that name. The REPL loads the package the
first time the browser is opened.

The manual is read from the Markdown it is written in, which Julia installs in
`share/doc/julia/src`. The standard libraries ship their manuals with their source, and so do
most packages, in `docs/src`, in the order that `docs/make.jl` gives. Pages that a package's
documentation build writes, such as Literate tutorials, are not in its source, and its pages
say so, with a link to its online documentation. A package in a subdirectory of a repository,
such as GLMakie in Makie.jl, is installed without a manual kept elsewhere in the repository; the
browser downloads it in the background from the release of the installed version, unless the
`JULIA_DOCBROWSER_AUTODOWNLOAD` environment variable is `no`. [`DocBrowser.explain_docs`](@ref)
says where the browser looked for a package's manual, and why it found no more.

The browser has three panes:

  * Contents: *Julia*, with its manual (*Manual*, *Base*, *Standard library* and *Developer
    docs*), then *Packages*: the active *Project*, its *Dependencies*, *Indirect* dependencies
    and *Extensions*, and last `Main`, where your own definitions are. Each library is one row.
    Dependencies that are not loaded yet are listed too: select one and press Enter to load it
    with `import` and see its documentation.
  * Names: the sections of a manual page, or the names in a module, grouped by kind. A
    library's manual, if its source has one, is listed first. Each name is marked `●` if
    exported, `○` if public, or `·` if internal. Internal and deprecated names are hidden until
    you press `i`.
  * Documentation: the docstrings of a name, or a module's docstring or README, with its
    version, licence, repository and online docs. Functions list their methods, and types
    their fields, subtypes and constructors.

Names mentioned in a docstring are links, and so are mentions of packages such as
`Example.jl`. Long pages start with links to their headings, extended help is folded away
until you press `x`, and a `⧉` beside a block of code copies it.

Use the arrow keys (or `h` `j` `k` `l`) to move, Enter to open, Tab to step through the links
of a page, and Backspace to go back. Press `/` to search: names come first, then the manual and the
text of docstrings, and names in the manuals of packages that are not loaded yet, which load
when picked. Ctrl-T narrows the search to names, then to text. Press `y` to close the browser and
put the name being viewed at the `julia>` prompt, or with the cursor in a block of Julia code,
that code; `e` to open the source of the selected link
or name in your editor (set by `JULIA_EDITOR`), `w` to change the layout, and `?` to see every
key. In terminals that support it, you can click on anything, scroll with the mouse wheel, and
use the mouse's back and forward buttons. Right-click, Alt-click or Ctrl-click opens the source
of a method, name, package or link. Drag across the documentation to copy text, or
double-click to copy a word and triple-click to copy a line. To select text with your terminal
instead, hold the key it uses for this while you drag: Shift in most terminals, Option in
iTerm2 and Fn in Terminal.app.

The browser opens again where it was last closed.

Every page has a link that you can share. Press `c`, or click `⧉ link` above the page, to copy
one, such as `help?> docs: manual/performance-tips#man-code-warntype`. Pasted at the `julia>`
prompt, it opens the browser at that place. You can also type `docs:` and a place in help mode
yourself: a page such as `manual/variables` or `stdlib/Pkg/environments`, with `#` and a
heading if you like, or a name such as `Base.sum`. The address of a page of the online docs,
at docs.julialang.org or pkgdocs.julialang.org, works the same way.

Packages whose repository the browser cannot find get a link that searches the web for them.
Set the `JULIA_DOCBROWSER_SEARCH_URL` environment variable to use another search engine, with
`%s` where the query goes, for example `https://www.google.com/search?q=%s`. The default is
DuckDuckGo.

```@docs
DocBrowser
DocBrowser.browse
DocBrowser.download_manual
```
