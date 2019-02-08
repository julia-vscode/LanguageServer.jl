module LanguageServer
using JSON
using REPL
import URIParser
import DocumentFormat
import CSTParser
import SymbolServer
using CSTParser: TopLevel, Block, Call, FileH, EXPR, UnaryOpCall, UnarySyntaxOpCall, BinaryOpCall, BinarySyntaxOpCall, WhereOpCall, ConditionalOpCall, IDENTIFIER, KEYWORD, LITERAL, OPERATOR, PUNCTUATION, Quotenode, contributes_scope
import CSTParser.Tokenize.Tokens

import StaticLint

export LanguageServerInstance

include("uri2.jl")
include("protocol/protocol.jl")
include("document.jl")
include("languageserverinstance.jl")
include("jsonrpc.jl")

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
