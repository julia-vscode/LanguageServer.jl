module LanguageServer
using JSON, JuliaFormatter
using UUIDs
using Markdown
import JSONRPC
using JSONRPC: Outbound, @dict_readable
import Logging
import JuliaWorkspaces
using JuliaWorkspaces: JuliaWorkspace, URIs2
using JuliaWorkspaces.URIs2: URI, uri2filepath, filepath2uri
using PrecompileTools
import Dates, Logging, LoggingExtras

# JuliaWorkspaces-bundled StaticLint — needed for LintOptions
const StaticLint = JuliaWorkspaces.StaticLint

export LanguageServerInstance, runserver

const INIT_OPT_USE_FORMATTER_CONFIG_DEFAULTS = "useFormatterConfigDefaults"

const g_operationId = Ref{String}("")

JSON.lower(uri::URI) = string(uri)

include("lsp_trace_logger.jl")
include("exception_types.jl")
include("protocol/protocol.jl")
include("extensions/extensions.jl")
include("textdocument.jl")
include("languageserverinstance.jl")
include("progress.jl")
include("runserver.jl")
include("staticlint.jl")
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
