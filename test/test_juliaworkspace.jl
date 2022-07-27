using LanguageServer:
    JuliaWorkspace,
    add_workspace_folder,
    remove_workspace_folder,
    add_file,
    update_file,
    remove_file

@testset "Julia workspace" begin
    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)

    project_file = jointpath(pkg_root, "Project.toml")
    project_uri = filepath2uri(project_file)

    jw = JuliaWorkspace(Set(pkg_root_uri))
    @test project_uri in jw._packages == true

    jw = JuliaWorkspace()
    jw = add_workspace_folder(jw, pkg_root)
    @test project_uri in jw._packages == true

    jw = JuliaWorkspace()
    jw = add_workspace_folder(jw, pkg_root)
    jw = remove_workspace_folder(jw, pkg_root)
    @test project_uri in jw._packages == false

    jw = JuliaWorkspace()
    jw = add_file(jw, project_uri)
    @test project_uri in jw._packages == true

    jw = JuliaWorkspace()
    jw = add_file(jw, project_uri)
    jw = update_file(jw, project_uri)
    @test project_uri in jw._packages == true

    jw = JuliaWorkspace()
    jw = add_file(jw, project_uri)
    jw = delete_file(jw, project_uri)
    @test project_uri in jw._packages == false
end
