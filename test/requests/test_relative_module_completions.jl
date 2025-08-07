### To run this test:
### $ julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->ti.name=="relative module completions"'

@testitem "relative module completions" begin
    using LanguageServer
    include(pkgdir(LanguageServer, "test", "test_shared_server.jl"))

    # Helper returns context but does not print
    function ctx(line::Int, col::Int)
        items = completion_test(line, col).items
        labels = [i.label for i in items]
        doc = LanguageServer.getdocument(server, uri"untitled:testdoc")
        mod = LanguageServer.julia_getModuleAt_request(
            LanguageServer.VersionedTextDocumentPositionParams(
                LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"),
                0,
                LanguageServer.Position(line, col)
            ),
            server,
            server.jr_endpoint
        )
        text = LanguageServer.get_text(doc)
        lines = split(text, '\n'; keepempty=true)
        line_txt = line+1 <= length(lines) ? lines[line+1] : ""
        return (labels, mod, line_txt)
    end

    # Assertion helper: only prints on failure
    function expect_has(line::Int, col::Int, expected::String)
        labels, mod, line_txt = ctx(line, col)
        ok = any(l -> l == expected, labels)
        if !ok
            @info "Relative completion failed" line=line col=col expected=expected moduleAt=mod lineText=line_txt labels=labels
        end
        @test ok
    end

    # Test content: both import and using
    settestdoc("""
module A
    module B
        module C
            module Submodule end
            import .
            import ..
            import ...
            import .Sub
            import ..Sib
            import ...Gran
            using .
            using ..
            using ...
            using .Sub
            using ..Sib
            using ...Gran
        end
        module Sibling end
    end
    module Grandsibling end
end
""")

    col = 1000

    # import . .. ... and partials
    expect_has(4,  col, "Submodule")
    expect_has(5,  col, "Sibling")
    expect_has(6,  col, "Grandsibling")
    expect_has(7,  col, "Submodule")
    expect_has(8,  col, "Sibling")
    expect_has(9,  col, "Grandsibling")

    # using . .. ... and partials
    expect_has(10, col, "Submodule")
    expect_has(11, col, "Sibling")
    expect_has(12, col, "Grandsibling")
    expect_has(13, col, "Submodule")
    expect_has(14, col, "Sibling")
    expect_has(15, col, "Grandsibling")
end
