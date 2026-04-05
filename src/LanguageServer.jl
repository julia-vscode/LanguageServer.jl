module LanguageServer
using JSON, REPL, CSTParser, JuliaFormatter
using CSTParser: EXPR, Tokenize.Tokens, Tokenize.Tokens.kind, headof, parentof, valof, to_codeobject
using UUIDs
using Base.Docs, Markdown
import JSONRPC
using JSONRPC: Outbound, @dict_readable
import Logging
import JuliaWorkspaces
using JuliaWorkspaces: JuliaWorkspace, URIs2
using JuliaWorkspaces.URIs2: URI, uri2filepath, filepath2uri
using PrecompileTools
import Dates

# JuliaWorkspaces-bundled modules — these replace the standalone StaticLint/SymbolServer packages
const JWStat = JuliaWorkspaces.StaticLint
const JWSymServer = JuliaWorkspaces.SymbolServer
# Backward-compat aliases so existing code referencing StaticLint.X / SymbolServer.X compiles
const StaticLint = JWStat
const SymbolServer = JWSymServer

export LanguageServerInstance, runserver

const INIT_OPT_USE_FORMATTER_CONFIG_DEFAULTS = "useFormatterConfigDefaults"

const g_operationId = Ref{String}("")

JSON.lower(uri::URI) = string(uri)

include("exception_types.jl")
include("protocol/protocol.jl")
include("extensions/extensions.jl")
include("textdocument.jl")
include("languageserverinstance.jl")
include("runserver.jl")
include("staticlint.jl")
include("jw_bridge.jl")
include("testitem_diagnostic_marking.jl")

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
include("requests/testing.jl")
include("utilities.jl")
include("precompile.jl")

end
