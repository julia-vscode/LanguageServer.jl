function julia_get_test_env_request(params::GetTestEnvRequestParams, server::LanguageServerInstance, conn)
    r = JuliaWorkspaces.get_test_env(server.workspace, params.uri)

    return GetTestEnvRequestParamsReturn(
        r.package_name,
        r.package_uri,
        r.project_uri,
        r.env_content_hash
    )
end
