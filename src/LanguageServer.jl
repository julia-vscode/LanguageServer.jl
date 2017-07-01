module LanguageServer

using JSON
using URIParser
import CSTParser
import Tokenize.Tokens

export LanguageServerInstance
const VariableLoc = Tuple{CSTParser.Variable,UnitRange{Int},String}

include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
# include("scope.jl")
include("trav/toplevel.jl")
include("trav/local.jl")
include("trav/lint.jl")
include("trav/utils.jl")
include("provider_diagnostics.jl")
include("provider_misc.jl")
include("provider_hover.jl")
include("provider_completions.jl")
include("provider_definitions.jl")
include("provider_signatures.jl")
include("provider_references.jl")
include("provider_links.jl")
include("provider_formatting.jl")
include("transport.jl")
include("provider_symbols.jl")
include("provider_action.jl")
include("utilities.jl")
include("jmd.jl")
# include("lint.jl")


end
