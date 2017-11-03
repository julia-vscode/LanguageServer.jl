__precompile__()
module LanguageServer
using JSON
import URIParser
import DocumentFormat
import CSTParser
import CSTParser: EXPR, UnaryOpCall, UnarySyntaxOpCall, BinaryOpCall, BinarySyntaxOpCall, WhereOpCall, ConditionalOpCall
import CSTParser: IDENTIFIER, KEYWORD, LITERAL, OPERATOR, PUNCTUATION, Quotenode, ERROR, Tokens
import CSTParser: TopLevel, Block, Call, NOTHING, FileH
import CSTParser: contributes_scope
import Tokenize.Tokens, Tokenize.Tokens.untokenize

const LeafNodes = Union{IDENTIFIER,KEYWORD,LITERAL,OPERATOR,PUNCTUATION}

mutable struct Variable
    id
    t
    val
end

mutable struct LSDiagnostic{C}
    loc::UnitRange{Int}
    actions::Vector{DocumentFormat.TextEdit}
    message::String
end

export LanguageServerInstance

struct VariableLoc
    v::Variable
    loc::UnitRange{Int}
    uri::String
end

include("uri2.jl")
include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
include("trav/toplevel.jl")
include("trav/macros.jl")
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
