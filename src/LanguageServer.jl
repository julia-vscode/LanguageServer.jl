module LanguageServer
import URIParser
using JSON, REPL, CSTParser, DocumentFormat, SymbolServer, StaticLint
using CSTParser: EXPR, Tokenize.Tokens, typof, kindof, parentof, valof
using StaticLint: refof, scopeof, bindingof
using UUIDs
import JSONRPC
using JSONRPC: Outbound, @dict_readable
export LanguageServerInstance

include("exception_types.jl")
include("uri2.jl")
include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("staticlint.jl")

include("requests/init.jl")
include("requests/misc.jl")
include("requests/textdocument.jl")
include("requests/features.jl")
include("requests/hover.jl")
include("requests/completions.jl")
include("requests/workspace.jl")
include("requests/actions.jl")
include("utilities.jl")

end
