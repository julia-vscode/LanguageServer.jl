function process(r::JSONRPC.Request{Val{Symbol("textDocument/formatting")},DocumentFormattingParams}, server)
    doc = server.documents[r.params.textDocument.uri]
    edits = TextEdit[]

    ps = CSTParser.ParseState(doc._content)
    CSTParser.parse(ps, true)
    for d in ps.diagnostics
        for a in d.actions
            apply_format(doc, edits, a)
        end
    end

    response = JSONRPC.Response(get(r.id), edits)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/formatting")}}, params)
    return DocumentFormattingParams(params)
end


function apply_format(doc::Document, edits, a::CSTParser.Diagnostics.Action) end

function apply_format(doc::Document, edits, a::CSTParser.Diagnostics.AddWS)
    start_byte = first(a.range)
    end_byte = last(a.range)
    start_l, start_c = get_position_at(doc, start_byte)
    end_l, end_c = get_position_at(doc, end_byte)
    push!(edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), " "^a.length))
end

function apply_format(doc::Document, edits, a::CSTParser.Diagnostics.Deletion)
    start_l, start_c = get_position_at(doc, first(a.range))
    end_l, end_c = get_position_at(doc, last(a.range))
    push!(edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), ""))
end

