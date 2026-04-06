# StaticLint ↔ LanguageServer bridge
#
# JW-based helpers for source text, range, and data access.

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
