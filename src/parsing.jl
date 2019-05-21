function parse_all(doc::Document, server)
    ps = CSTParser.ParseState(doc._content)
    t00 = @elapsed StaticLint.clear_meta(getcst(doc))
    t0 = @elapsed if endswith(doc._uri, ".jmd")
        doc.cst, ps = parse_jmd(ps, doc._content)
    else
        doc.cst, ps = CSTParser.parse(ps, true)
    end
    if doc.cst.typ === CSTParser.FileH
        doc.cst.val = doc.path
    end
    empty!(doc.diagnostics)
    ls_diags = Diagnostic[]
    if server.runlinter && doc._runlinter
        t1 = @elapsed scopepass(getroot(doc))
        t2 = @elapsed mark_errors(doc, ls_diags)
    end
    # @info string("Cleaning time: $t00")
    # @info string("Parsing time: ", t0)
    # @info string("Scoping time: ", t1)
    # @info string("Uref marking time: ", t2)
    
    send(JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, ls_diags)), server)
end

function mark_errors(doc, out = Diagnostic[])
    line_offsets = get_line_offsets(doc)
    urefs = get_errors(doc.cst)
    n = length(urefs)
    n == 0 && return out
    i = 1
    start = true
    offset = urefs[i][1]
    
    r = Int[0, 0]
    pos = 0
    nlines = length(line_offsets)
    if offset > last(line_offsets)
        line = nlines
    else
        line = 1
        while line < nlines
            while line_offsets[line] <= offset < line_offsets[line + 1]
                ind = line_offsets[line]
                char = 0
                while offset > ind
                    ind = nextind(doc._content, ind)
                    char += 1
                end
                if start
                    r[1] = line
                    r[2] = char
                    offset += urefs[i][2].span
                else
                    if urefs[i][2].typ === CSTParser.IDENTIFIER
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), 2, "Julia", "Julia", "Missing reference: $(urefs[i][2].val)", nothing))
                    elseif urefs[i][2].typ === CSTParser.ErrorToken
                        push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), 1, "Julia", "Julia", "Parsing error", nothing))
                    end
                    i += 1
                    i>=n && break
                    offset = urefs[i][1]
                end
                start = !start
                offset = start ? urefs[i][1] : urefs[i][1] + urefs[i][2].span
            end
            line += 1
        end
    end
    return out
end

function get_errors(x::EXPR, urefs = Tuple{Int,EXPR}[], pos = 0)
    if x.typ === CSTParser.ErrorToken || (CSTParser.isidentifier(x) && !StaticLint.hasref(x) #= && !(x.parent isa EXPR && x.parent.typ == CSTParser.Quotenode) =#)
        push!(urefs, (pos, x))
    end
    if x.args !== nothing
        for i in 1:length(x.args)
            get_errors(x.args[i], urefs, pos)
            pos += x.args[i].fullspan
        end
    end
    urefs
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