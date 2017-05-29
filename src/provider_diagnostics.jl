function parse_all(doc, server)
    # Try blocks should be removed
    try
        ps = CSTParser.ParseState(doc._content)
        if endswith(doc._uri, ".jmd")
            doc.code.ast, ps = parse_jmd(ps, doc._content)
        else
            doc.code.ast, ps = CSTParser.parse(ps, true)
        end
    catch er
        info("PARSING FAILED for $(doc._uri)")
        info(er)
    end
    
    # includes
    update_includes(doc, server)

    # diagnostics
    doc.diagnostics = ps.diagnostics

    # Parsing failed
    if ps.errored
        parse_errored(doc, ps)
    end

    publish_diagnostics(doc, server)
end


function convert_diagnostic{T}(h::CSTParser.Diagnostics.Diagnostic{T}, doc::Document)
    rng = Range(Position(get_position_at(doc, first(h.loc) + 1)..., one_based = true), Position(get_position_at(doc, last(h.loc) + 1)..., one_based = true))
    code =  T isa CSTParser.Diagnostics.ErrorCodes ? 1 :
            T isa CSTParser.Diagnostics.LintCodes ? 2 :
            T isa CSTParser.Diagnostics.FormatCodes ? 4 : 3
    Diagnostic(rng, code, string(T), string(typeof(h).name), isempty(h.message) ? string(T) : h.message)
end

function publish_diagnostics(doc::Document, server)
    ls_diags = convert_diagnostic.(doc.diagnostics, doc)
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, ls_diags)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), publishDiagnosticsParams)
    send(response, server)
end

function update_includes(doc::Document, server::LanguageServerInstance)
    doc.code.includes = map(_get_includes(doc.code.ast)) do incl
        (isabspath(incl[1]) ? filepath2uri(incl[1]) : joinpath(dirname(doc._uri), incl[1]), incl[2])
        
    end
end

function parse_errored(doc::Document, ps::CSTParser.ParseState)
    ast = doc.code.ast
    if last(ast.args) isa EXPR{CSTParser.ERROR}
        if length(ast.args) > 1
            loc = sum(ast.args[i].span for i = 1:length(ast.args) - 1):sizeof(doc._content)
        else
            loc = 0:sizeof(doc._content)
        end
        push!(doc.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.ParseFailure}(0:sizeof(doc._content), [], "Parsing failure"))
    end
end
