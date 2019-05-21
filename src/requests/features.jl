function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/codeAction")}}, params)
    return CodeActionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/codeAction")},CodeActionParams}, server)
    commands = Command[]
    
    response = JSONRPC.Response(r.id, commands)
    send(response, server)
end

function get_signatures(b, sigs, server) end

function get_signatures(b::CSTParser.Binding, sigs, server)
    if b.t == getsymbolserver(server)["Core"].vals["Function"]
        if b.val isa CSTParser.EXPR && CSTParser.defines_function(b.val)
            sig = CSTParser.rem_where_decl(CSTParser.get_sig(b.val))
            args = EXPR[]
            for i = 2:length(sig.args)
                if sig.args[i].binding !== nothing 
                    push!(args, sig.args[i].binding)
                end
            end
            params = (a->ParameterInformation(a.name)).(args)
            push!(sigs, SignatureInformation(string(Expr(sig)), "", params))
        end
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params)
    return TextDocumentPositionParams(params)
end


function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)] 
    sigs = SignatureInformation[]
    offset = get_offset(doc, r.params.position)
    rng = Range(doc, offset:offset)
    x = get_expr(getcst(doc), offset)
    arg = 0

    if x isa EXPR && x.parent isa EXPR && x.parent.typ === CSTParser.Call
        if x.parent.args[1].typ === CSTParser.IDENTIFIER && StaticLint.hasref(x.parent.args[1])
            call_name = x.parent.args[1]
        elseif x.parent.args[1].typ === CSTParser.Curly && x.parent.args[1].args[1].typ === CSTParser.IDENTIFIER
            call_name = x.parent.args[1].args[1]
        else
            call_name = nothing
        end
        if call_name !== nothing && StaticLint.hasref(call_name)
            if call_name.ref isa CSTParser.Binding
                f_binding = call_name.ref
                while f_binding !== nothing && f_binding.t == getsymbolserver(server)["Core"].vals["Function"]
                    get_signatures(f_binding, sigs, server)
                    f_binding = f_binding.overwrites
                end
            elseif call_name.ref isa SymbolServer.FunctionStore
                for m in call_name.ref.methods
                    sig = string(call_name.val, "(", join([a[2] for a in m.args], ", "),")")
                    params = (a->ParameterInformation(a[1])).(m.args)
                    push!(sigs, SignatureInformation(sig, "", params))
                end
            end
        end
    end
    (isempty(sigs) || (x.typ === CSTParser.PUNCTUATION  && x.kind === CSTParser.Tokens.RPAREN)) && return send(JSONRPC.Response(r.id, CancelParams(Dict("id" => r.id))), server)

    if x.typ === CSTParser.Tokens.LPAREN
        arg = 0
    else
        arg = sum(!(a.typ === CSTParser.PUNCTUATION) for a in x.parent.args) - 1
    end
    send(JSONRPC.Response(r.id, SignatureHelp(filter(s->length(s.parameters) > arg, sigs), 0, arg)), server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    locations = Location[]
    doc = server.documents[URI2(r.params.textDocument.uri)]
    offset = get_offset(doc, r.params.position)
    x = get_expr(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x)
        b = x.ref
        while b isa CSTParser.Binding
            if b.val isa EXPR
                p, o = get_file_loc(b.val)
                if p isa String && hasfile(server, p)
                    doc1 = getfile(server, p)
                    push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:b.val.span))))
                end
            elseif b.val isa SymbolServer.FunctionStore
                for m in b.val.methods
                    file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
                    ((file, m.line) == DefaultTypeConstructorLoc || file == nothing) && continue
                    push!(locations, Location(filepath2uri(file), Range(m.line - 1, 0, m.line, 0)))
                end
            end
            if b.t == getsymbolserver(server)["Core"].vals["Function"] && b.overwrites isa CSTParser.Binding && (b.overwrites.t == getsymbolserver(server)["Core"].vals["Function"] || b.overwrites.t == getsymbolserver(server)["Core"].vals["DataType"])
                b = b.overwrites
            else
                b = nothing
            end
        end
    end
    
    send(JSONRPC.Response(r.id, locations), server)
end

function get_file_loc(x::EXPR, offset = 0, c  = nothing)
    if c !== nothing
        for a in x.args
            a == c && break
            offset += a.fullspan
        end
    end
    if x.parent !== nothing
        return get_file_loc(x.parent, offset, x)
    elseif x.typ === CSTParser.FileH
        return x.val, offset
    else
        return "", offset
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/formatting")}}, params)
    return DocumentFormattingParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/formatting")},DocumentFormattingParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    newcontent = DocumentFormat.format(doc._content)
    end_l, end_c = get_position_at(doc, sizeof(doc._content))
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l, end_c), newcontent)]

    send(JSONRPC.Response(r.id, lsedits), server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentLink")}}, params)
    return DocumentLinkParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentLink")},DocumentLinkParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    links = Tuple{String,UnitRange{Int}}[]

    send(JSONRPC.Response(r.id, links), server) 
end


function find_references(textDocument::TextDocumentIdentifier, position::Position, server)
    locations = Location[]
    doc = server.documents[URI2(textDocument.uri)] 
    offset = get_offset(doc, position)
    x = get_expr(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x) && x.ref isa CSTParser.Binding
        for r in x.ref.refs
            !(r isa EXPR) && continue
            p, o = get_file_loc(r)
            if p isa String && hasfile(server, p)
                doc1 = getfile(server, p)
                push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:r.span))))
            end
        end
    end
    return locations
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params)
    return ReferenceParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    locations = find_references(r.params.textDocument, r.params.position, server)
    send(JSONRPC.Response(r.id, locations), server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/rename")}}, params)
    return RenameParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/rename")},RenameParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    tdes = Dict{String,TextDocumentEdit}()
    locations = find_references(r.params.textDocument, r.params.position, server)
    
    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, r.params.newName))
        else
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, server.documents[URI2(loc.uri)]._version), [TextEdit(loc.range, r.params.newName)])
        end
    end
    
    send(JSONRPC.Response(r.id, WorkspaceEdit(nothing, collect(values(tdes)))), server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    syms = SymbolInformation[]
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]

    bs = collect_bindings_w_loc(getcst(doc))
    for x in bs
        p,b = x[1], x[2]
        !(b.val isa EXPR) && continue
        isempty(b.name) && continue
        push!(syms, SymbolInformation(b.name, 1, false, Location(doc._uri, Range(doc, p .+ (0:b.val.span))), nothing))
    end
    send(JSONRPC.Response(r.id, syms), server)
end

function collect_bindings_w_loc(x::EXPR, pos = 0, bindings = Tuple{Int,CSTParser.Binding}[])
    if x.binding !== nothing
        push!(bindings, (pos, x.binding))
    end
    if x.args !== nothing
        for a in x.args
            collect_bindings_w_loc(a, pos, bindings)
            pos += a.fullspan
        end
    end
    return bindings
end
