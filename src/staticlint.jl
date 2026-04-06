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

"""
    jw_position_to_lsp(server, uri, pos)

Convert a `JuliaWorkspaces.Position` (1-based line, 1-based UTF-8 byte column)
to an LSP `Position` (0-based line, 0-based UTF-16 character).

When column == 1, the conversion is trivial (character = 0) and no SourceText
lookup is needed.
"""
function jw_position_to_lsp(server::LanguageServerInstance, uri::URI, pos::JuliaWorkspaces.Position)
    line = pos.line - 1  # 1-based → 0-based
    if pos.column == 1
        return Position(line, 0)
    end
    st = jw_source_text(server, uri)
    line_start = st.line_indices[pos.line]
    target = line_start + pos.column - 1
    text = st.content
    character = 0
    i = line_start
    while i < target
        c = text[i]
        character += UInt32(c) >= 0x010000 ? 2 : 1
        i = nextind(text, i)
    end
    return Position(line, character)
end

"""
    jw_range(server, uri, start, stop)

Convert a pair of `JuliaWorkspaces.Position` values to an LSP `Range`.
"""
function jw_range(server::LanguageServerInstance, uri::URI, start::JuliaWorkspaces.Position, stop::JuliaWorkspaces.Position)
    return Range(
        jw_position_to_lsp(server, uri, start),
        jw_position_to_lsp(server, uri, stop)
    )
end
