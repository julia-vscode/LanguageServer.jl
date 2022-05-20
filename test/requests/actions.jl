action_request_test(line0, char0, line1=line0, char1=char0; diags=[]) = LanguageServer.textDocument_codeAction_request(LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier(uri"untitled:testdoc"), LanguageServer.Range(LanguageServer.Position(line0, char0), LanguageServer.Position(line1, char1)), LanguageServer.CodeActionContext(diags, missing)), server, server.jr_endpoint)

@testset "reexport" begin
    settestdoc("using Base.Meta\n")
    @test any(c.command == "ReexportModule" for c in action_request_test(0, 15))
    c = filter(c -> c.command == "ReexportModule", action_request_test(0, 15))[1]
    
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "inline expand" begin
    settestdoc("f(x) = x")
    @test any(c.command == "ExpandFunction" for c in action_request_test(0, 5))
    c = filter(c -> c.command == "ExpandFunction", action_request_test(0, 5))[1]

    settestdoc("g(x) = x\nf(x) = x")
    @test any(c.command == "ExpandFunction" for c in action_request_test(0, 0))
    @test any(c.command == "ExpandFunction" for c in action_request_test(1, 0))
    
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)

    settestdoc("f(x) = begin x end")
    @test any(c.command == "ExpandFunction" for c in action_request_test(0, 5))
    c = filter(c -> c.command == "ExpandFunction", action_request_test(0, 5))[1]
    
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "fixmissingref" begin
    doc = settestdoc("argtail\n")
    e = LanguageServer.mark_errors(doc)[1]
    @test any(c.command == "FixMissingRef" for c in action_request_test(0, 5, diags=[e]))
    c = filter(c -> c.command == "FixMissingRef", action_request_test(0, 5, diags=[e]))[1]
    
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "explicit import" begin
    doc = settestdoc("using Base.Meta\nMeta.quot")
    @test LanguageServer.find_using_statement(doc.cst.args[2].args[1]) !== nothing
    
    @test any(c.command == "ExplicitPackageVarImport" for c in action_request_test(1, 1))
    c = filter(c -> c.command == "ExplicitPackageVarImport", action_request_test(1, 1))[1]
    
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "farg unused" begin
    doc = settestdoc("function f(arg::T) end\n")
    
    @test any(c.command == "DeleteUnusedFunctionArgumentName" for c in action_request_test(0, 12))
    c = filter(c -> c.command == "DeleteUnusedFunctionArgumentName", action_request_test(0, 12))[1]
    
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "unused assignment" begin
    doc = settestdoc("function f()\n    x = 1 + 2\n    return 3\nend\n")

    @test any(c.command == "ReplaceUnusedAssignmentName" for c in action_request_test(1, 4))
    c = filter(c -> c.command == "ReplaceUnusedAssignmentName", action_request_test(1, 4))[1]

    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "===/!== for nothing comparison" begin
    for str in ("x = 1\nif x == nothing end", "x = 1\nif x != nothing end")
        doc = settestdoc(str)
        @test any(c.command == "CompareNothingWithTripleEqual" for c in action_request_test(1, 6))
        c = filter(c -> c.command == "CompareNothingWithTripleEqual", action_request_test(1, 6))[1]
        LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
    end
end

@testset "Add license header" begin
    doc = settestdoc("hello\nworld\n")

    @test !any(c.command == "AddLicenseIdentifier" for c in action_request_test(1, 1))

    @test any(c.command == "AddLicenseIdentifier" for c in action_request_test(0, 1))
    c = filter(c -> c.command == "AddLicenseIdentifier", action_request_test(0, 1))[1]

    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "Organize imports" begin
    doc = settestdoc("using JSON\nusing Example: foo, bar\nf(x) = x\n")

    @test any(c.command == "OrganizeImports" for c in action_request_test(0, 1))
    @test any(c.command == "OrganizeImports" for c in action_request_test(1, 10))
    @test !any(c.command == "OrganizeImports" for c in action_request_test(2, 2))

    c = filter(c -> c.command == "OrganizeImports", action_request_test(0, 1))[1]
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "Convert between string and raw strings" begin
    # "..." -> raw"..."
    doc = settestdoc("""
        "this is fine"

        @show "this is fine"

        @raw_str "this is fine"

        r"not fine"

        "not \$(fine) either"

        "docstring"
        f(x) = x
        """)

    @test any(c.command == "RewriteAsRawString" for c in action_request_test(0, 2))
    @test any(c.command == "RewriteAsRawString" for c in action_request_test(2, 10))
    @test any(c.command == "RewriteAsRawString" for c in action_request_test(4, 12))
    @test !any(c.command == "RewriteAsRawString" for c in action_request_test(6, 4))
    @test !any(c.command == "RewriteAsRawString" for c in action_request_test(8, 2))
    @test !any(c.command == "RewriteAsRawString" for c in action_request_test(10, 3))

    c = filter(c -> c.command == "RewriteAsRawString", action_request_test(0, 2))[1]
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)

    # Test the internal method doing the conversion, with `quotes = "\""`
    # raw = string("raw", quotes, sprint(escape_raw_string, valof(x)), quotes)
    str = "he\$\"llo"
    raw_str = "he\$\\\"llo" # Will be `he$\"llo` when unescaped/printed
    @test sprint(LanguageServer.escape_raw_string, str) == raw_str

    # raw"..." -> "..."
    doc = settestdoc("""
        raw"this is fine"

        @raw_str "not fine"

        "not fine"
        """)

    @test any(c.command == "RewriteAsRegularString" for c in action_request_test(0, 5))
    @test !any(c.command == "RewriteAsRegularString" for c in action_request_test(2, 12))
    @test !any(c.command == "RewriteAsRegularString" for c in action_request_test(4, 3))

    c = filter(c -> c.command == "RewriteAsRegularString", action_request_test(0, 5))[1]
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)

    # Test the internal method doing the conversion, with `quotes = ""`
    # regular = quotes * repr(valof(x)) * quotes
    raw_str = "he\$l\"lo"
    str = "\"he\\\$l\\\"lo\"" # Will be `"he\$l\"lo` when unescaped/printed
    @test repr(raw_str) == str
end

@testset "Add docstring template" begin
    doc = settestdoc("""
        f(x) = x

        @inline f(x) = x

        f(x::T) where T <: Int = x

        function g(x)
        end

        function g(x::T) where T <: Int
        end

        "docstring"
        h(x) = x

        "docstring"
        function h(x)
        end
        """)

    ok_locations = [
        [(0, i) for i in 0:3],
        [(2, i) for i in 8:11],
        [(4, i) for i in 0:21],
        [(6, i) for i in 0:12],
        [(9, i) for i in 0:30],
    ]
    not_ok_locations = [
        [(13, i) for i in 0:4],
        [(16, i) for i in 0:12],
    ]
    for loc in Iterators.flatten(ok_locations)
        @test any(c.command == "AddDocstringTemplate" for c in action_request_test(loc...))
    end
    for loc in Iterators.flatten(not_ok_locations)
        @test !any(c.command == "AddDocstringTemplate" for c in action_request_test(loc...))
    end

    c = filter(c -> c.command == "AddDocstringTemplate", action_request_test(0, 1))[1]
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end

@testset "Update docstring signature" begin
    doc = settestdoc("""
        "hello"
        f(x) = x

        \"\"\"hello\"\"\"
        g(x) = x

        \"\"\"
            h()

        hello
        \"\"\"
        function h(x)
        end

        i(x) = x
        """)

    @test any(c.command == "UpdateDocstringSignature" for c in action_request_test(1, 0))
    @test any(c.command == "UpdateDocstringSignature" for c in action_request_test(4, 0))
    @test any(c.command == "UpdateDocstringSignature" for c in action_request_test(11, 0))
    @test !any(c.command == "UpdateDocstringSignature" for c in action_request_test(14, 0))

    c = filter(c -> c.command == "UpdateDocstringSignature", action_request_test(1, 0))[1]
    LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
end
