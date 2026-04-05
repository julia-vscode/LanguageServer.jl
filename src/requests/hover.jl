function textDocument_hover_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)
    documentation = JuliaWorkspaces.get_hover_text(server.workspace, uri, index)
    return documentation === nothing ? nothing : Hover(MarkupContent(documentation), missing)
end

# get_tooltip and related helpers are now in JuliaWorkspaces.
# Re-export for LS callers (completions, features) that still need them.
const _empty_meta_dict_hover = JuliaWorkspaces._empty_hover_meta_dict
get_tooltip(b::StaticLint.Binding, documentation::String, server, meta_dict=_empty_meta_dict_hover, expr = nothing, env = nothing; show_definition = false) =
    JuliaWorkspaces._get_tooltip(b, documentation, meta_dict, expr, env; show_definition)

