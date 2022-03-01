using JSON

server = LanguageServer.LanguageServerInstance(IOBuffer(), IOBuffer(), dirname(Pkg.Types.Context().env.project_file), first(Base.DEPOT_PATH))

mktempdir() do dir

    # TODO use types directly and skip the string JSON entirely
    initstr = """{"processId":17712,"rootPath":"","rootUri":"$(LanguageServer.filepath2uri(dir))","capabilities":{"workspace":{"applyEdit":true,"workspaceEdit":{"documentChanges":true},"didChangeConfiguration":{"dynamicRegistration":true},"didChangeWatchedFiles":{"dynamicRegistration":true},"symbol":{"dynamicRegistration":true,"symbolKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]}},"executeCommand":{"dynamicRegistration":true},"configuration":true,"workspaceFolders":true},"textDocument":{"publishDiagnostics":{"relatedInformation":true},"synchronization":{"dynamicRegistration":true,"willSave":true,"willSaveWaitUntil":true,"didSave":true},"completion":{"dynamicRegistration":true,"contextSupport":true,"completionItem":{"snippetSupport":true,"commitCharactersSupport":true,"documentationFormat":["markdown","plaintext"],"deprecatedSupport":true},"completionItemKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]}},"hover":{"dynamicRegistration":true,"contentFormat":["markdown","plaintext"]},"signatureHelp":{"dynamicRegistration":true,"signatureInformation":{"documentationFormat":["markdown","plaintext"]}},"definition":{"dynamicRegistration":true},"references":{"dynamicRegistration":true},"documentHighlight":{"dynamicRegistration":true},"documentSymbol":{"dynamicRegistration":true,"symbolKind":{"valueSet":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26]}},"codeAction":{"dynamicRegistration":true,"codeActionLiteralSupport":{"codeActionKind":{"valueSet":["","quickfix","refactor","refactor.extract","refactor.inline","refactor.rewrite","source","source.organizeImports"]}}},"codeLens":{"dynamicRegistration":true},"formatting":{"dynamicRegistration":true},"rangeFormatting":{"dynamicRegistration":true},"onTypeFormatting":{"dynamicRegistration":true},"rename":{"dynamicRegistration":true},"documentLink":{"dynamicRegistration":true},"typeDefinition":{"dynamicRegistration":true},"implementation":{"dynamicRegistration":true},"colorProvider":{"dynamicRegistration":true}}},"trace":"off","workspaceFolders":[{"uri":"$(LanguageServer.filepath2uri(dir))","name":"CSTParser"}]}"""
    init_params = LanguageServer.InitializeParams(JSON.parse(initstr))

    server.runlinter = true
    server.jr_endpoint = nothing
    LanguageServer.initialize_request(init_params, server, nothing)
    # LanguageServer.process(LanguageServer.JSONRPC.Request{Val{Symbol("initialized")},Any}(0, nothing), server)

    function test_edit(server, text, s1, s2, insert)
        LanguageServer.textDocument_didOpen_notification(LanguageServer.LanguageServer.DidOpenTextDocumentParams(LanguageServer.TextDocumentItem("none", "julia", 0, text)), server, nothing)
        doc = LanguageServer.getdocument(server, LanguageServer.URI2("none"))
        LanguageServer.parse_all(doc, server)
        params = LanguageServer.DidChangeTextDocumentParams(
            LanguageServer.VersionedTextDocumentIdentifier(doc._uri, 5),
            [LanguageServer.TextDocumentContentChangeEvent(LanguageServer.Range(LanguageServer.Position(s1...), LanguageServer.Position(s2...)), 0, insert)]
        )
        tdcce = params.contentChanges[1]
        doc._line_offsets = nothing

        # TODO: This should only re-parse necessary parts of the document
        LanguageServer.applytextdocumentchanges(doc, tdcce)
        LanguageServer.parse_all(doc, server)

        new_cst = CSTParser.parse(LanguageServer.get_text(doc), true)

        CSTParser.to_codeobject(doc.cst) == CSTParser.to_codeobject(new_cst), doc.cst, new_cst
    end

    # techinically tests the same as test_document.jl, but should be changed to incremental re-parsing
    # once that's implemented again
    @testset "text edits" begin
        @test test_edit(server, "a", (0, 0), (0, 0), "a")[1]
        @test test_edit(server, "a", (0, 1), (0, 1), "a")[1]
        @test test_edit(server, "a", (0, 0), (0, 1), "abc")[1]
        @test test_edit(server, "a\n", (1, 0), (1, 0), "b")[1]
        @test test_edit(server, "a", (0, 0), (0, 1), "")[1]
        @test test_edit(server, "a\na", (1, 0), (1, 1), "b")[1]
        @test test_edit(server, "a\na", (1, 0), (1, 1), "")[1]
        @test test_edit(server, "begin\nend", (0, 4), (0, 5), "")[1]
        @test test_edit(server, "a\nb", (1, 1), (1, 1), "\n")[1]
        @test test_edit(server, "bein\nend", (0, 2), (0, 2), "g")[1]
        @test test_edit(server, "a\nb\nc", (2, 0), (2, 1), "")[1]
        @test test_edit(server, "a\nb\nc", (1, 0), (1, 1), "")[1]
        @test test_edit(server, "begin while f end end", (0, 10), (0, 11), "")[1]
        @test test_edit(server, "begin while true end end\nf() = 1", (0, 12), (0, 16), "")[1]
        @test test_edit(server, "for i ", (0, 6), (0, 6), ";")[1]

        @test test_edit(server, "a\n\nc", (1, 0), (1, 0), "b")[1]
        @test test_edit(server, "a\nb\ne", (1, 1), (1, 1), "\nc\nd")[1]
        @test test_edit(server, "aaa\nbbb", (0, 0), (0, 0), "\n")[1]
    end

end
