module LanguageServer
using JSON
using REPL
import URIParser
# import DocumentFormat
import CSTParser
import SymbolServer
using CSTParser
using CSTParser: EXPR
import CSTParser.Tokenize.Tokens

import StaticLint

export LanguageServerInstance

include("uri2.jl")
include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")
include("staticlint.jl")

include("requests/misc.jl")
include("requests/init.jl")
include("requests/textdocument.jl")
include("requests/features.jl")
include("requests/workspace.jl")
include("parsing.jl")
include("utilities.jl")
include("jmd.jl")
include("display.jl")

end
