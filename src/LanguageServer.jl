module LanguageServer
import URIParser
using JSON, REPL, CSTParser, DocumentFormat, SymbolServer, StaticLint, Distributed
using CSTParser: EXPR, Tokenize.Tokens

export LanguageServerInstance

include("uri2.jl")
include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
include("staticlint.jl")

include("requests/init.jl")
include("requests/misc.jl")
include("requests/textdocument.jl")
include("requests/features.jl")
include("requests/hover.jl")
include("requests/completions.jl")
include("requests/workspace.jl")
include("parsing.jl")
include("utilities.jl")
include("jmd.jl")
include("display.jl")

end
