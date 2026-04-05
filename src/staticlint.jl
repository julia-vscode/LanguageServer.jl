# StaticLint ↔ LanguageServer bridge
#
# Two concerns:
# 1. get_meta_data + 2-arg meta accessors (delegate to JW's StaticLint with meta_dict)
# 2. JW-based helpers for EXPR→location resolution (get_file_loc, jw_range, jw_version, etc.)

# === Environment accessor ===

function getenv(server::LanguageServerInstance, uri::URI)
    env = JuliaWorkspaces.get_environment(server.workspace, uri)
    if env !== nothing
        return env
    end
    # Fallback: empty env
    return StaticLint.ExternalEnv(SymbolServer.EnvStore(), Dict{SymbolServer.VarRef,Vector{SymbolServer.VarRef}}(), Symbol[])
end
getenv(server::LanguageServerInstance) = StaticLint.ExternalEnv(SymbolServer.EnvStore(), Dict{SymbolServer.VarRef,Vector{SymbolServer.VarRef}}(), Symbol[])

getsymbols(env::StaticLint.ExternalEnv) = env.symbols

# === JW-based EXPR→location helpers ===
# These replace the old set_doc / get_file_loc / parent_file pattern.
# No EXPR mutation — the mapping is maintained externally by JW's derived_expr_uri_map.

# 1-arg meta accessors: still needed during the transition for code that reads
# EXPR.meta directly (e.g. hasmeta checks in meta_dict accessors).
hasmeta(x::EXPR) = x.meta isa StaticLint.Meta

"""
    get_file_loc(x::EXPR, server::LanguageServerInstance)

Return `(uri, offset)` for the given EXPR node by walking parents to the file
root and looking up the owning URI from JuliaWorkspaces.
Returns `nothing` if the EXPR cannot be mapped to a file.
"""
function get_file_loc(x::EXPR, server::LanguageServerInstance)
    result = JuliaWorkspaces.get_expr_location(server.workspace, x)
    result === nothing && return nothing
    return result.uri, result.offset
end

"""
    jw_cst(server, uri)

Get the CSTParser EXPR tree for a URI from JuliaWorkspaces.
All request handlers should use this instead of `getcst(doc)` so that
`objectid`-based meta_dict lookups and `get_file_loc` work correctly.
"""
function jw_cst(server::LanguageServerInstance, uri::URI)
    return JuliaWorkspaces.get_legacy_cst(server.workspace, uri)
end

"""
    jw_source_text(server, uri)

Get the SourceText for a URI from JuliaWorkspaces.
"""
function jw_source_text(server::LanguageServerInstance, uri::URI)
    return JuliaWorkspaces.get_text_file(server.workspace, uri).content
end

"""
    jw_range(server, uri, byte_range)

Convert a byte offset range to an LSP Range using JuliaWorkspaces SourceText.
"""
function jw_range(server::LanguageServerInstance, uri::URI, rng::UnitRange)
    st = jw_source_text(server, uri)
    return Range(st, rng)
end

"""
    jw_text(server, uri)

Get the file content string for a URI.
"""
function jw_text(server::LanguageServerInstance, uri::URI)
    return jw_source_text(server, uri).content
end

"""
    jw_version(server, uri)

Get the LSP document version for a URI (from open file tracking).
"""
function jw_version(server::LanguageServerInstance, uri::URI)
    return get(server._open_file_versions, uri, 0)
end

# === get_meta_data: fetch StaticLint analysis from JuliaWorkspaces ===

const _empty_meta_dict = Dict{UInt64, StaticLint.Meta}()

"""
    get_meta_data(server::LanguageServerInstance, uri::URI)

Fetch the static lint data (meta_dict, env) from JuliaWorkspaces for the given URI.
Always returns a `(meta_dict, env)` tuple (never nothing). Falls back to empty
values when no analysis data is available.
"""
function get_meta_data(server::LanguageServerInstance, uri::URI)
    data = JuliaWorkspaces.get_static_lint_data(server.workspace, uri)
    if data !== nothing
        return data.meta_dict, data.env
    end
    empty_env = StaticLint.ExternalEnv(SymbolServer.EnvStore(), Dict{SymbolServer.VarRef,Vector{SymbolServer.VarRef}}(), Symbol[])
    return _empty_meta_dict, empty_env
end

# === 2-arg meta accessors — delegate to JW's StaticLint with meta_dict ===

const MetaDict = Dict{UInt64, StaticLint.Meta}

refof(x::EXPR, meta_dict::MetaDict) = StaticLint.refof(x, meta_dict)
scopeof(x::EXPR, meta_dict::MetaDict) = StaticLint.scopeof(x, meta_dict)
bindingof(x::EXPR, meta_dict::MetaDict) = StaticLint.bindingof(x, meta_dict)
hasmeta(x::EXPR, meta_dict::MetaDict) = StaticLint.hasmeta(x, meta_dict)
hasref(x::EXPR, meta_dict::MetaDict) = StaticLint.hasref(x, meta_dict)
haserror(x::EXPR, meta_dict::MetaDict) = StaticLint.haserror(x, meta_dict)
errorof(x::EXPR, meta_dict::MetaDict) = StaticLint.errorof(x, meta_dict)
hasbinding(x::EXPR, meta_dict::MetaDict) = StaticLint.hasbinding(x, meta_dict)
hasscope(x::EXPR, meta_dict::MetaDict) = StaticLint.hasscope(x, meta_dict)
setref!(x::EXPR, binding, meta_dict::MetaDict) = StaticLint.setref!(x, binding, meta_dict)

function retrieve_scope(x, meta_dict::MetaDict)
    if scopeof(x, meta_dict) !== nothing
        return scopeof(x, meta_dict)
    elseif parentof(x) isa EXPR
        return retrieve_scope(parentof(x), meta_dict)
    end
    return nothing
end

function retrieve_toplevel_scope(x::EXPR, meta_dict::MetaDict)
    if scopeof(x, meta_dict) !== nothing && StaticLint.is_toplevel_scope(x)
        return scopeof(x, meta_dict)
    elseif parentof(x) isa EXPR
        return retrieve_toplevel_scope(parentof(x), meta_dict)
    end
    return nothing
end
retrieve_toplevel_scope(s::StaticLint.Scope, meta_dict::MetaDict) = (StaticLint.is_toplevel_scope(s) || !(StaticLint.parentof(s) isa StaticLint.Scope)) ? s : retrieve_toplevel_scope(StaticLint.parentof(s), meta_dict)

function loose_refs(b::StaticLint.Binding, meta_dict::MetaDict)
    return StaticLint.loose_refs(b, meta_dict)
end
