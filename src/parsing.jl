function parse_all(doc::Document, server)
    ps = CSTParser.ParseState(doc._content)
    t00 = @elapsed StaticLint.clear_meta(doc.cst)
    # @info string("Cleaning time: $t00")
    t0 = @elapsed if endswith(doc._uri, ".jmd")
        doc.cst, ps = parse_jmd(ps, doc._content)
    else
        doc.cst, ps = CSTParser.parse(ps, true)
    end
    if doc.cst.typ == CSTParser.FileH
        doc.cst.val = doc.path
    end
    empty!(doc.diagnostics)
    ls_diags = []
    # @info string("Parsing time: ", t0)
    if server.runlinter && doc._runlinter
        t1 = @elapsed scopepass(getroot(doc))
        t2 = @elapsed mark_urefs(doc, ls_diags)
        # @info string("Scoping time: ", t1)
        # @info string("Uref marking time: ", t2)
    end

    # for err in ps.errors
    #     if err.description == "Expected end."
    #         rng2 = max(0, first(err.loc)-1):last(err.loc)
    #         stack, offsets = StaticLint.get_stack(doc.code.cst, first(rng2))
    #         for i = length(stack):-1:1
    #             if stack[i] isa CSTParser.EXPR{T} where T <: Union{CSTParser.Begin,CSTParser.Quote,CSTParser.ModuleH,CSTParser.Function,CSTParser.Macro,CSTParser.For,CSTParser.While,CSTParser.If} && last(stack[i].args) isa CSTParser.EXPR{CSTParser.ErrorToken} && stack[i].args[end].args[1] isa CSTParser.KEYWORD
    #                 rng1 = offsets[i] .+ (1:stack[i].args[1].span)
    #                 push!(ls_diags, Diagnostic(Range(doc, rng1), 1, "Parsing error", "Julia language server", "Closing end is missing.", nothing))        
    #             end
    #         end
    #         push!(ls_diags, Diagnostic(Range(doc, rng2), 1, "Parsing error", "Julia language server", err.description, nothing))
    #     else
    #         rng = max(0, first(err.loc)-1):last(err.loc)
    #         push!(ls_diags, Diagnostic(Range(doc, rng), 1, "Parsing error", "Julia language server", err.description, nothing))
    #     end
    # end
    
    # if server.runlinter
    #     if doc._runlinter

            # StaticLint.pass(doc.code)
            # state = StaticLint.build_bindings(find_root(doc, server).code);
            # empty!(doc.code.rref)
            # empty!(doc.code.uref)
            # StaticLint.resolve_refs(doc.code.state.refs, state, doc.code.rref, doc.code.uref);
            
            # for r in doc.code.uref
            #     r isa StaticLint.Reference{CSTParser.BinarySyntaxOpCall} && continue
            #     push!(ls_diags ,Diagnostic(r, doc))
            # end
            # for err in doc.code.state.linterrors 
            #     push!(ls_diags ,Diagnostic(err, doc))
            # end
    #     end
    # end
    send(JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(doc._uri, ls_diags)), server)
end

# Diagnostic(b::StaticLint.Binding, doc) = Diagnostic(Range(doc, b.loc.offset .+ (0:b.val.span)), 2, "Unused variable", "Julia language server", "Variable declared but not used: $(string(Expr(b.val)))", nothing)
# Diagnostic(r::StaticLint.Reference, doc) = Diagnostic(Range(doc, r.loc.offset .+ (0:r.val.span)), 2, "Missing variable", "Julia language server", "Use of possibly undeclared variable: $(string(Expr(r.val)))", nothing)
# Diagnostic(err::StaticLint.LintError, doc) = Diagnostic(Range(doc, err.loc.offset .+ (0:err.val.span)), 2, "Lint error", "Julia language server", get(StaticLint.LintMessages, err.code, ""), nothing)

function mark_urefs(doc, out = Diagnostic[])
    line_offsets = get_line_offsets(doc)
    urefs = get_urefs(doc.cst)
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
                    push!(out, Diagnostic(Range(r[1] - 1, r[2], line - 1, char), 2, "Julia", "Julia", "Missing reference", nothing))
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

function get_urefs(x::EXPR, urefs = Tuple{Int,EXPR}[], pos = 0)
    if CSTParser.isidentifier(x) && !StaticLint.hasref(x)# && !(x.parent isa EXPR && x.parent.typ == CSTParser.Quotenode)
        push!(urefs, (pos, x))
    end
    if x.args !== nothing
        for i in 1:length(x.args)
            get_urefs(x.args[i], urefs, pos)
            pos += x.args[i].fullspan
        end
    end
    urefs
end

function mark_urefs(doc, urefs, ls_diags)
    for (p,r) in urefs
        push!(ls_diags, Diagnostic(Range(doc, p .+ (0:r.span)), 1, "Julia", "Julia", "Missing reference", nothing))
    end
end

function get_rrefs(x::EXPR, refs = [], pos = 0)
    if CSTParser.isidentifier(x) && StaticLint.hasref(x)
        push!(refs, (pos, x))
    end
    if x.args !== nothing
        for a in x.args
            get_rrefs(a, refs, pos)
            pos += a.fullspan
        end
    end
    refs
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