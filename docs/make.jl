using Documenter, DocBrowser

makedocs(;
    sitename = "DocBrowser.jl",
    modules = [DocBrowser],
    pages = ["Home" => "index.md", "For AI agents" => "agents.md", "Reference" => "api.md"],
    format = Documenter.HTML(; canonical = "https://JuliaLang.github.io/DocBrowser.jl/stable/", edit_link = "main"),
    # only the public names need a place in the docs; the rest are documented for the source
    checkdocs = :public,
)

deploydocs(; repo = "github.com/JuliaLang/DocBrowser.jl.git", devbranch = "main")
