function process(r::JSONRPC.Request{Val{Symbol("textDocument/codeAction")}, CodeActionParams}, server)
    doc = server.documents[r.params.textDocument.uri]
    commands = Command[]
    range = r.params.range
    range_loc = get_offset(doc, range.start.line + 1, range.start.character):get_offset(doc, range.stop.line + 1, range.stop.character)
    
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
    for d in doc.diagnostics
        if first(d.loc) <= first(range_loc) <= last(range_loc) <= last(d.loc) && typeof(d).parameters[1] isa CSTParser.Diagnostics.LintCodes && !isempty(d.actions) 
            for a in d.actions
                start_l, start_c = get_position_at(doc, first(a.range))
                end_l, end_c = get_position_at(doc, last(a.range))
                push!(tde.edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), a.text))
            end
        end
    end
    
    if !isempty(tde.edits)
        push!(commands, Command("Fix deprecation", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tde])]))
    end

    response = JSONRPC.Response(get(r.id), commands)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/codeAction")}}, params)
    return CodeActionParams(params)
end
