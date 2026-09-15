@testitem "julia.experimental.loweringLint switches the lint engine" setup=[TestSetup, SharedServer] begin
    using LanguageServer: set_lowering_lint!
    import JuliaWorkspaces

    settestdoc("function f(x)\n    unused_local = 1\n    return x\nend\n")

    unused_from_lowering() = any(
        d -> d.code === :unused_binding && d.source == "JuliaWorkspaces.jl",
        JuliaWorkspaces.get_diagnostic(server.workspace, uri"untitled:testdoc"))

    # Off by default: nothing from the lowering producer.
    @test server.lowering_lint == false
    @test !unused_from_lowering()

    set_lowering_lint!(server, true)
    @test server.lowering_lint == true
    @test unused_from_lowering()

    # Idempotent and reversible.
    set_lowering_lint!(server, true)
    @test unused_from_lowering()
    set_lowering_lint!(server, false)
    @test server.lowering_lint == false
    @test !unused_from_lowering()

    closetestdoc()
end
