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
        if err.description == "Expected end."
            rng2 = max(0, first(err.loc)-1):last(err.loc)
            stack, offsets = StaticLint.get_stack(doc.code.cst, first(rng2))
            for i = length(stack):-1:1
                if stack[i] isa CSTParser.EXPR{T} where T <: Union{CSTParser.Begin,CSTParser.Quote,CSTParser.ModuleH,CSTParser.Function,CSTParser.Macro,CSTParser.For,CSTParser.While,CSTParser.If} && last(stack[i].args) isa CSTParser.EXPR{CSTParser.ErrorToken} && stack[i].args[end].args[1] isa CSTParser.KEYWORD
                    rng1 = offsets[i] .+ (1:stack[i].args[1].span)
                    push!(ls_diags, Diagnostic(Range(doc, rng1), 1, "Parsing error", "Julia language server", "Closing end is missing.", nothing))        
                end
            end
            push!(ls_diags, Diagnostic(Range(doc, rng2), 1, "Parsing error", "Julia language server", err.description, nothing))
        else
            rng = max(0, first(err.loc)-1):last(err.loc)
            push!(ls_diags, Diagnostic(Range(doc, rng), 1, "Parsing error", "Julia language server", err.description, nothing))
        end
    end
    
    if server.runlinter
        if doc._runlinter
            StaticLint.pass(doc.code)
            bindings = StaticLint.build_bindings(find_root(doc, server).code);
            empty!(doc.code.rref)
            empty!(doc.code.uref)
            StaticLint.resolve_refs(doc.code.state.refs, bindings, doc.code.rref, doc.code.uref);
            
            for (i, r) in enumerate(doc.code.uref)
                r isa StaticLint.Reference{CSTParser.BinarySyntaxOpCall} && continue
                rng = 0:r.val.span
                push!(ls_diags ,Diagnostic(Range(doc, r.loc.offset .+ rng), 2, "Missing variable", "Julia language server", "Use of possibly undeclared variable: $(string(Expr(r.val)))", nothing))
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
    ls_diags = map(doc.diagnostics) do diag
        convert_diagnostic(diag, doc)
    end
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, ls_diags)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, publishDiagnosticsParams)
    send(response, server)
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