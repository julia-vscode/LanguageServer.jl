# Bridge utilities for accessing JuliaWorkspaces data from LS handlers.
#
# These functions provide a clean interface for handlers to get CSTs,
# metadata, and environments from JW instead of the old Document model.

"""
    get_jw_source_text(server, uri)

Get the `SourceText` from JuliaWorkspaces for position calculations.
Returns `nothing` if the file is not tracked by JW.
"""
function get_jw_source_text(server::LanguageServerInstance, uri::URI)
    JuliaWorkspaces.has_file(server.workspace, uri) || return nothing
    return JuliaWorkspaces.get_text_file(server.workspace, uri).content
end

"""
    get_jw_cst(server, uri)

Get the legacy CSTParser EXPR tree from JuliaWorkspaces.
Returns `nothing` if the file is not tracked by JW.
"""
function get_jw_cst(server::LanguageServerInstance, uri::URI)
    JuliaWorkspaces.has_file(server.workspace, uri) || return nothing
    return JuliaWorkspaces.get_legacy_cst(server.workspace, uri)
end

"""
    get_jw_lint_data(server, uri)

Get static lint analysis data from JuliaWorkspaces.

Returns a named tuple `(meta_dict, env, workspace_packages, root)` or `nothing`
if the file is not tracked or has no root.
"""
function get_jw_lint_data(server::LanguageServerInstance, uri::URI)
    JuliaWorkspaces.has_file(server.workspace, uri) || return nothing
    return JuliaWorkspaces.get_static_lint_data(server.workspace, uri)
end

"""
    get_jw_env(server, uri)

Get the resolved environment for a file from JuliaWorkspaces.
Returns `nothing` if the file is not tracked or has no root.
"""
function get_jw_env(server::LanguageServerInstance, uri::URI)
    JuliaWorkspaces.has_file(server.workspace, uri) || return nothing
    return JuliaWorkspaces.get_environment(server.workspace, uri)
end
