const LintSeverity = Dict('E'=>1,'W'=>2,'I'=>3)

function process_diagnostics(uri::String, server::LanguageServerInstance)
    document = get_text(server.documents[uri])

    input = Dict("file"=>normpath(unescape(URI(uri).path))[2:end], "code_str"=>String(document))

    @schedule begin
        conn = connect(server.lint_pipe_name)

        JSON.print(conn, input)

        out = JSON.parse(conn)



        diags = map(out) do l
            line_number = l["line"]
            start_col = findfirst(i->i!=' ', get_line(uri, line_number, server))
            Diagnostic(Range(Position(line_number-1, start_col-1), Position(line_number-1, typemax(Int)) ),
                        LintSeverity[string(l["code"])[1]],
                        string(l["code"]),
                        "Lint.jl",
                        l["message"])
        end
        publishDiagnosticsParams = PublishDiagnosticsParams(uri, diags)

        response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), publishDiagnosticsParams)
        send(response, server)
    end
end
