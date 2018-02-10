__precompile__()
module LanguageServer
using JSON
import URIParser
import DocumentFormat
import CSTParser
using CSTParser: TopLevel, Block, Call, FileH, EXPR, UnaryOpCall, UnarySyntaxOpCall, BinaryOpCall, BinarySyntaxOpCall, WhereOpCall, ConditionalOpCall, IDENTIFIER, KEYWORD, LITERAL, OPERATOR, PUNCTUATION, Quotenode, ERROR, Tokens, contributes_scope
using StaticLint

export LanguageServerInstance

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
include("staticlint.jl")
include("requests/misc.jl")
include("requests/init.jl")
include("requests/textDocument.jl")
include("requests/workspace.jl")
include("parsing.jl")
include("utilities.jl")
include("jmd.jl")

end
