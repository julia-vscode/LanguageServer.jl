function parse_all(doc, server)
    ps = CSTParser.ParseState(doc._content)
    if endswith(doc._uri, ".jmd")
        doc.code.cst, ps = parse_jmd(ps, doc._content)
    else
        doc.code.cst, ps = CSTParser.parse(ps, true)
    end
    # update_includes(doc, server)
    empty!(doc.diagnostics)
    ls_diags = []
    
    for err in ps.errors
        rng = _offset_unitrange(err.loc)
        push!(ls_diags, Diagnostic(Range(doc, rng), 1, "ERROR", "ERROR", err.description, nothing))
    end
    
    if server.runlinter
        if doc._runlinter
            StaticLint.pass(doc.code)
            bindings = StaticLint.cat_bindings(server, find_root(doc, server).code);
            empty!(doc.code.rref)
            empty!(doc.code.uref)
            StaticLint.resolve_refs(doc.code.state.refs, bindings, doc.code.rref, doc.code.uref);
            
            for (i, r) in enumerate(doc.code.uref)
                rng = 0:last(r.val.span)
                push!(ls_diags ,Diagnostic(Range(doc, r.loc.offset .+ rng), 2, "missing variable", "missing variable", "$i missing variable: $(string(Expr(r.val))) at $(r.loc)", nothing))
            end
        end
    end
    send(JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, ls_diags)), server)
end

StaticLint.getfile(server::LanguageServerInstance, path) = server.documents[URI2(filepath2uri(path))].code
StaticLint.setfile(server::LanguageServerInstance, path, x) = server.documents[URI2(filepath2uri(path))] = x
StaticLint.is_loaded(server::LanguageServerInstance, path) = haskey(server.documents, URI2(filepath2uri(path)))
function StaticLint.load_file(server::LanguageServerInstance, path::String, index, nb, parent)
    code = read(path, String)
    uri = filepath2uri(path)
    doc = Document(uri, code, true, server, index, nb, parent)
    StaticLint.setfile(server, path, doc)
    return doc.code
end



function convert_diagnostic(h::LSDiagnostic{T}, doc::Document) where {T}
    rng = Range(doc, h.loc)
    code = 1
    Diagnostic(rng, code, string(T), string(typeof(h).name), isempty(h.message) ? string(T) : h.message, nothing)
end

function publish_diagnostics(doc::Document, server)
    ls_diags = convert_diagnostic.(doc.diagnostics, doc)
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, ls_diags)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, publishDiagnosticsParams)
    send(response, server)
end

# function update_includes(doc::Document, server::LanguageServerInstance)
#     doc.code.includes = map(_get_includes(doc.code.ast)) do incl
#         (isabspath(incl[1]) ? filepath2uri(incl[1]) : joinuriwithpath(dirname(doc._uri), incl[1]), incl[2])
#     end
# end

function parse_errored(doc::Document, ps::CSTParser.ParseState)
    cst = doc.code.cst
    for err in ps.errors
        push!(doc.diagnostics, LSDiagnostic{CSTParser.ErrorToken}(err.loc, [], err.description))
    end
    if false #!isempty(ps.errored)
        err_loc = ps.nt.startbyte
        if length(cst.args) > 1
            start_loc = sum(cst.args[i].fullspan for i = 1:length(cst.args) - 1)
            loc = start_loc:err_loc
        else
            loc = 0:sizeof(doc._content)
            loc = 0:err_loc
        end
        push!(doc.diagnostics, LSDiagnostic{CSTParser.Diagnostics.ParseFailure}(loc, [], string(ps.error_code)))
    end
end

function clear_diagnostics(uri::URI2, server)
    doc = server.documents[uri]
    empty!(doc.diagnostics)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, Diagnostic[]))
    send(response, server)

end

function clear_diagnostics(server)
    for (uri, doc) in server.documents
        clear_diagnostics(uri, server)
    end
end