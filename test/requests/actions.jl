action_request_test(line0, char0, line1=line0, char1=char0; diags=[]) = LanguageServer.textDocument_codeAction_request(LanguageServer.CodeActionParams(LanguageServer.TextDocumentIdentifier("testdoc"), LanguageServer.Range(LanguageServer.Position(line0, char0), LanguageServer.Position(line1, char1)), LanguageServer.CodeActionContext(diags, missing)), server, server.jr_endpoint)

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

@testset "===/!== for nothing comparison" begin
    for str in ("x = 1\nif x == nothing end", "x = 1\nif x != nothing end")
        doc = settestdoc(str)
        @test any(c.command == "CompareNothingWithTripleEqual" for c in action_request_test(1, 6))
        c = filter(c -> c.command == "CompareNothingWithTripleEqual", action_request_test(1, 6))[1]
        LanguageServer.workspace_executeCommand_request(LanguageServer.ExecuteCommandParams(missing, c.command, c.arguments), server, server.jr_endpoint)
    end
end
