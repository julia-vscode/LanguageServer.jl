using LanguageServer
using Documenter

makedocs(;
    modules=[LanguageServer],
    authors="Julia VSCode",
    repo="https://github.com/julia-vscode/LanguageServer.jl/blob/{commit}{path}#L{line}",
    sitename="LanguageServer.jl",
    format=Documenter.HTML(;
        prettyurls = prettyurls = get(ENV, "CI", nothing) == "true",
        # canonical="https://julia-vscode.github.io/LanguageServer.jl",
        # assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Syntax Reference" => "syntax.md",
    ],
)

deploydocs(;
    repo="github.com/julia-vscode/LanguageServer.jl",
)
