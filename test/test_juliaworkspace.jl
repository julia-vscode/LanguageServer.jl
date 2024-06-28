using LanguageServer:
    JuliaWorkspace,
    add_workspace_folder,
    remove_workspace_folder,
    add_file,
    update_file,
    delete_file

@testitem "Julia workspace" begin
    using LanguageServer: filepath2uri, JuliaWorkspace

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace(Set([pkg_root_uri]))
    @test haskey(jw._packages, project_uri)
end

@testitem "add_workspace_folder" begin
    using LanguageServer: filepath2uri, JuliaWorkspace, add_workspace_folder

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace()
    jw = add_workspace_folder(jw, pkg_root_uri)
    @test haskey(jw._packages, project_uri)
end

@testitem "add_workspace_folder 2" begin
    using LanguageServer: filepath2uri, JuliaWorkspace, add_workspace_folder

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace(Set{LanguageServer.URI}([]))
    jw = add_workspace_folder(jw, pkg_root_uri)
    @test haskey(jw._packages, project_uri)
end

@testitem "add_workspace_folder and remove_workspace_folder" begin
    using LanguageServer: filepath2uri, JuliaWorkspace, add_workspace_folder, remove_workspace_folder

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace()
    jw = add_workspace_folder(jw, pkg_root_uri)
    jw = add_workspace_folder(jw, filepath2uri(joinpath(@__DIR__)))
    jw = remove_workspace_folder(jw, pkg_root_uri)
    @test !haskey(jw._packages, project_uri)
end

@testitem "add_file" begin
    using LanguageServer: filepath2uri, JuliaWorkspace, add_file

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace()
    jw = add_file(jw, project_file_uri)
    @test haskey(jw._packages, project_uri)
end

@testitem "update_file" begin
    using LanguageServer: filepath2uri, JuliaWorkspace, add_file, update_file

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace()
    jw = add_file(jw, project_file_uri)
    jw = update_file(jw, project_file_uri)
    @test haskey(jw._packages, project_uri)
end

@testitem "delete_file" begin
    using LanguageServer: filepath2uri, JuliaWorkspace, add_file, delete_file

    pkg_root = abspath(joinpath(@__DIR__, ".."))
    pkg_root_uri = filepath2uri(pkg_root)
    project_file_path = joinpath(pkg_root, "Project.toml")
    project_path = dirname(project_file_path)
    project_file_uri = filepath2uri(project_file_path)
    project_uri = filepath2uri(project_path)

    jw = JuliaWorkspace()
    jw = add_file(jw, project_file_uri)
    jw = delete_file(jw, project_file_uri)
    @test !haskey(jw._packages, project_uri)
end

@testitem "load_folder" begin
    using LanguageServer: filepath2uri, load_folder, hasdocument

    include("test_shared_server.jl")
    pkg_root = abspath(joinpath(@__DIR__, ".."))
    
    filepath = "test/test_juliaworkspace.jl"

    empty!(server._documents)
    load_folder(pkg_root, server)
    
    uri = filepath2uri(joinpath(pkg_root, filepath))
    @test hasdocument(server, uri)

    server.lint_ignoredglobs = [
        "\\..*",
        filepath,
    ]
    empty!(server._documents)
    load_folder(pkg_root, server)
    
    @test !hasdocument(server, uri)

    server.lint_ignoredglobs = [
        "\\..*",
        "test",
    ]
    empty!(server._documents)
    load_folder(pkg_root, server)
    
    @test !hasdocument(server, uri)
end    
