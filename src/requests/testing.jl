function julia_get_test_env_request(params::GetTestEnvRequestParams, server::LanguageServerInstance, conn)
    r = JuliaWorkspaces.get_test_env(server.workspace, params.uri)

    return GetTestEnvRequestParamsReturn(
        something(r.package_name, missing),
        something(r.package_uri, missing),
        something(r.project_uri, missing),
        something(r.env_content_hash, missing)
    )
end
