module LanguageServer
using JSON
using URIParser
import DocumentFormat
import CSTParser
import Tokenize.Tokens

mutable struct Variable
    id
    t
    val::CSTParser.EXPR
end

mutable struct LSDiagnostic{C}
    loc::UnitRange{Int}
    actions::Vector{DocumentFormat.TextEdit}
    message::String
end

export LanguageServerInstance
const VariableLoc = Tuple{Variable,UnitRange{Int},String}

include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
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
include("provider_rename.jl")
include("provider_links.jl")
include("provider_formatting.jl")
include("transport.jl")
include("provider_symbols.jl")
include("provider_action.jl")
include("utilities.jl")
include("jmd.jl")


end
