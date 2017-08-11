function parse_all(doc, server)
    # Try blocks should be removed
    ps = CSTParser.ParseState(doc._content)
    if endswith(doc._uri, ".jmd")
        doc.code.ast, ps = parse_jmd(ps, doc._content)
    else
        doc.code.ast, ps = CSTParser.parse(ps, true)
    end
    update_includes(doc, server)
    if ps.errored
        parse_errored(doc, ps)
    end
    if server.runlinter
        if doc._runlinter
            L = lint(doc, server)
            doc.diagnostics = L.diagnostics
        end
        
        publish_diagnostics(doc, server)
    end
end



function convert_diagnostic(h::LSDiagnostic{T}, doc::Document) where {T}
    rng = Range(doc, h.loc)
    code =  T isa CSTParser.Diagnostics.ErrorCodes ? 1 :
            T isa LintCodes ? 2 : 3
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
        err_loc = ps.nt.startbyte
        if length(ast.args) > 1
            start_loc = sum(ast.args[i].fullspan for i = 1:length(ast.args) - 1)
            loc = start_loc:err_loc
        else
            loc = 0:sizeof(doc._content)
            loc = 0:err_loc
        end
        push!(doc.diagnostics, LSDiagnostic{CSTParser.Diagnostics.ParseFailure}(loc, [], "Parsing failure"))
    end
end
