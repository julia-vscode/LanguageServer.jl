using LanguageServer:
    JuliaWorkspace,
    add_workspace_folder,
    remove_workspace_folder,
    add_file,
    update_file,
    delete_file

@testset "Julia workspace" begin
    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)

    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace(Set([pkg_root_uri]))
    @test haskey(jw._packages, project_uri)

    jw = JuliaWorkspace()
    jw = add_workspace_folder(jw, pkg_root_uri)
    @test haskey(jw._packages, project_uri)

    jw = JuliaWorkspace(Set{LanguageServer.URI}([]))
    jw = add_workspace_folder(jw, pkg_root_uri)
    @test haskey(jw._packages, project_uri)

    jw = JuliaWorkspace()
    jw = add_workspace_folder(jw, pkg_root_uri)
    jw = remove_workspace_folder(jw, pkg_root_uri)
    @test !haskey(jw._packages, project_uri)

    jw = JuliaWorkspace()
    jw = add_file(jw, project_file_uri)
    @test haskey(jw._packages, project_uri)

    jw = JuliaWorkspace()
    jw = add_file(jw, project_file_uri)
    jw = update_file(jw, project_file_uri)
    @test haskey(jw._packages, project_uri)

    jw = JuliaWorkspace()
    jw = add_file(jw, project_file_uri)
    jw = delete_file(jw, project_file_uri)
    @test !haskey(jw._packages, project_uri)
end
