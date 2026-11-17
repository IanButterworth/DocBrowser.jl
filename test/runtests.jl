using Test
using REPL
using DocBrowser

const CORE = Base.PkgId(Base.UUID("7917522e-f5cf-4099-ba06-1d518c8891e3"), "DocBrowserCore")

function fake_terminal(input::String)
    out = IOContext(IOBuffer(), :displaysize => (30, 110), :color => true)
    return REPL.Terminals.TTYTerminal("xterm", IOBuffer(input), out, IOBuffer())
end

@testset "the browser is loaded on first use" begin
    @test !haskey(Base.loaded_modules, CORE)
    # Downloaded first, so that no download is still running when the tests end.
    @test isdir(DocBrowser.download_manual())
    @test haskey(Base.loaded_modules, CORE)
    # `y` closes the browser and returns the name that was shown.
    @test DocBrowser.browse(fake_terminal("y"); query="sum") == "sum"
end

@testset "REPL help mode" begin
    @test DocBrowser.is_docs_place("docs: Base.sum")
    @test DocBrowser.is_docs_place("  https://docs.julialang.org/en/v1/base/collections/")
    @test DocBrowser.is_docs_place("https://pkgdocs.julialang.org/v1/environments/")
    @test !DocBrowser.is_docs_place("sum") && !DocBrowser.is_docs_place("https://example.org")

    repl = REPL.LineEditREPL(fake_terminal(""), true)
    repl.interface = REPL.setup_interface(repl)
    modes = repl.interface.modes
    help = only(filter(m -> endswith(DocBrowser.prompt_text(m), "help?> "), modes))
    julia_prompt = only(filter(m -> endswith(DocBrowser.prompt_text(m), "julia> "), modes))
    enter, done, question = help.keymap_dict['\r'], help.on_done, julia_prompt.keymap_dict['?']
    DocBrowser.install(repl)
    @test help.keymap_dict['\r'] !== enter && help.on_done !== done
    @test julia_prompt.keymap_dict['?'] !== question
    @test haskey(help.keymap_dict['\e'], '\r')
    # a second install leaves the bindings as they are
    enter = help.keymap_dict['\r']
    DocBrowser.install(repl)
    @test help.keymap_dict['\r'] === enter
end
