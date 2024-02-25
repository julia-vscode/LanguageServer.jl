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

# these are the endpoints of JSON-RPC error codes
# per the LSP spec, no LSP error codes should lie
# between these
const SERVER_ERROR_END       = -32000
const SERVER_ERROR_START     = -32099

# These are existing reserved errors for JSONRPC.jl
# We shouldn't throw these manually
const SERVER_NOT_INITIALIZED = -32002
const UNKNOWN_ERROR_CODE     = -32001

# LSP specific error codes
# these are the defined ranges for LSP errors
# not real error codes. Custom errors must lie
# outside this range
const LSP_RESERVED_ERROR_START = -32899
const LSP_RESERVED_ERROR_END   = -32800

const REQUEST_CANCELLED      = -32800
const CONTENT_MODIFIED       = -32801
const SERVER_CANCELLED       = -32802
const REQUEST_FAILED         = -32803

# Specific to our implementation
const NO_DOCUMENT        = -33100
const MISMATCHED_VERSION = -33101
const SHUTDOWN_REQUEST   = -32600

const ERROR_CODES = (
    REQUEST_CANCELLED,
    CONTENT_MODIFIED,
    SERVER_CANCELLED,
    REQUEST_FAILED,
    NO_DOCUMENT,
    MISMATCHED_VERSION,
    SHUTDOWN_REQUEST
)

function __init__()
    # init JSONRPC error messages
    conflicting_codes = filter(ERROR_CODES) do code
        !haskey(JSONRPC.JSONRPCErrorStrings, code) && return false
        return JSONRPC.JSONRPCErrorStrings[code] != "ServerError"
    end
    # if any of the codes we want to use are already set,
    # it means we have a conflict with another application
    # using JSONRPC.jl at the same time in this process
    # warn the user of this, so that they can debug/work around it
    if !isempty(conflicting_codes)
        @warn """JSONRPC Error Codes conflict!

        Another library besides LanguageServer.jl is using JSONRPC.jl with conflicting error codes.
        LanguageServer.jl will overwrite this with its own state. Faulty behavior/error printing may arise.
        """ Codes=conflicting_codes
    end

    JSONRPC.RPCErrorStrings[REQUEST_CANCELLED]      = "RequestCancelled"
    JSONRPC.RPCErrorStrings[CONTENT_MODIFIED]       = "ContentModified"
    JSONRPC.RPCErrorStrings[SERVER_CANCELLED]       = "ServerCancelled"
    JSONRPC.RPCErrorStrings[REQUEST_FAILED]         = "RequestFailed"
    nothing
end

include("exception_types.jl")
include("protocol/protocol.jl")
include("extensions/extensions.jl")
include("textdocument.jl")
include("document.jl")
include("juliaworkspace.jl")
include("languageserverinstance.jl")
include("multienv.jl")
include("runserver.jl")
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
