module LanguageServer

using Compat
using JSON
using Lint
using URIParser

include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
include("protocol.jl")
include("parse.jl")
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
