module LanguageServer
using JSON, REPL, CSTParser, JuliaFormatter, SymbolServer, StaticLint
using CSTParser: EXPR, Tokenize.Tokens, Tokenize.Tokens.kind, headof, parentof, valof, to_codeobject
using StaticLint: refof, scopeof, bindingof
using UUIDs
using Base.Docs, Markdown
import JSONRPC
using JSONRPC: Outbound, @dict_readable
import TestItemDetection
import Logging
using PrecompileTools

export LanguageServerInstance, runserver

include("URIs2/URIs2.jl")
using .URIs2

JSON.lower(uri::URI) = string(uri)

include("exception_types.jl")
include("protocol/protocol.jl")
include("extensions/extensions.jl")
include("textdocument.jl")
include("document.jl")
include("juliaworkspace.jl")
include("languageserverinstance.jl")
include("multienv.jl")
include("runserver.jl")
include("jet.jl")
include("staticlint.jl")

include("requests/misc.jl")
include("requests/textdocument.jl")
include("requests/features.jl")
include("requests/hover.jl")
include("requests/completions.jl")
include("requests/workspace.jl")
include("requests/actions.jl")
include("requests/init.jl")
include("requests/signatures.jl")
include("requests/highlight.jl")
include("utilities.jl")
include("precompile.jl")

end
