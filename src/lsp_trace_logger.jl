@enum LSPTraceValue lsp_trace_off lsp_trace_messages lsp_trace_verbose

function parse_lsp_trace_value(s::AbstractString)
    s == "off" && return lsp_trace_off
    s == "messages" && return lsp_trace_messages
    s == "verbose" && return lsp_trace_verbose
    return lsp_trace_off
end

mutable struct LSPTraceLogger{T} <: Logging.AbstractLogger
    lsi::T
end

function Logging.handle_message(logger::LSPTraceLogger, level, message, _module, group, id, file, line; kwargs...)
    endpoint = logger.lsi.jr_endpoint
    endpoint === nothing && return nothing

    tv = LSPTraceValue(logger.lsi.trace_value[])

    tv == lsp_trace_off && return nothing

    msg = string(_module, ": ", message)

    if tv == lsp_trace_messages
        JSONRPC.send(endpoint, logTrace_notification_type, LogTraceParams(msg, missing))
    else # verbose
        verbose_parts = String[]
        for (k, v) in kwargs
            push!(verbose_parts, string(k, " = ", v))
        end
        verbose_str = isempty(verbose_parts) ? missing : join(verbose_parts, "\n")
        JSONRPC.send(endpoint, logTrace_notification_type, LogTraceParams(msg, verbose_str))
    end

    return nothing
end

function Logging.shouldlog(logger::LSPTraceLogger, level, _module, group, id)
    return LSPTraceValue(logger.lsi.trace_value[]) != lsp_trace_off
end

function Logging.min_enabled_level(logger::LSPTraceLogger)
    return Debug
end
