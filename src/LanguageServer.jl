module LanguageServer

using JSON
using Lint
using URIParser
using JuliaParser

export LanguageServerInstance

include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
include("protocol.jl")
include("staticanalysis.jl")
include("provider_diagnostics.jl")
include("provider_misc.jl")
include("provider_hover.jl")
include("provider_completions.jl")
include("provider_definitions.jl")
include("provider_signatures.jl")
include("transport.jl")
include("provider_symbols.jl")
include("utilities.jl")

end
