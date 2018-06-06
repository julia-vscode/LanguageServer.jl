function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    if URI2(uri) in keys(server.documents)
        doc = server.documents[URI2(uri)]
        doc._content = r.params.textDocument.text
    else
        server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false, server)
        doc = server.documents[URI2(uri)]
        if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
            doc._workspace_file = true
        end
        set_open_in_editor(doc, true)
        if is_ignored(uri, server)
            doc._runlinter = false
        end
    end
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    !haskey(server.documents, URI2(uri)) && return
    doc = server.documents[URI2(uri)]
    empty!(doc.diagnostics)
    publish_diagnostics(doc, server)
    if !is_workspace_file(doc)
        delete!(server.documents, URI2(uri))
    else
        set_open_in_editor(doc, false)
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[URI2(r.params.textDocument.uri)]
    doc._version = r.params.textDocument.version
    isempty(r.params.contentChanges) && return
    # dirty = get_offset(doc, last(r.params.contentChanges).range.start.line + 1, last(r.params.contentChanges).range.start.character + 1):get_offset(doc, first(r.params.contentChanges).range.stop.line + 1, first(r.params.contentChanges).range.stop.character + 1)
    # for c in r.params.contentChanges
    #     update(doc, c.range.start.line + 1, c.range.start.character + 1, c.rangeLength, c.text)
    # end
    doc._content = last(r.params.contentChanges).text
    doc._line_offsets = Nullable{Vector{Int}}()
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    return DidSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[URI2(uri)]
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSave")}}, params)
    return WillSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSave")},WillSaveTextDocumentParams}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSaveWaitUntil")}}, params)
    return WillSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSaveWaitUntil")},WillSaveTextDocumentParams}, server)
    response = JSONRPC.Response(get(r.id), TextEdit[])
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/codeAction")}}, params)
    return CodeActionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/codeAction")},CodeActionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    commands = Command[]
    range = r.params.range
    range_loc = get_offset(doc, range.start.line + 1, range.start.character):get_offset(doc, range.stop.line + 1, range.stop.character)
    
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
    action_type = Any
    tdeall = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
    # for d in doc.diagnostics
    #     if first(d.loc) <= first(range_loc) <= last(range_loc) <= last(d.loc) && typeof(d).parameters[1] isa LintCodes && !isempty(d.actions) 
    #         action_type = typeof(d).parameters[1]
    #         for a in d.actions
    #             start_l, start_c = get_position_at(doc, first(a.range))
    #             end_l, end_c = get_position_at(doc, last(a.range))
    #             push!(tde.edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), a.text))
    #         end
    #     end
    # end
    file_actions = []
    for d in doc.diagnostics
        if typeof(d).parameters[1] == action_type && !isempty(d.actions) 
            for a in d.actions
                push!(file_actions, a)
                
            end
        end
    end
    sort!(file_actions, lt = (a, b) -> last(b.range) < first(a.range))
    for a in file_actions
        start_l, start_c = get_position_at(doc, first(a.range))
        end_l, end_c = get_position_at(doc, last(a.range))
        push!(tdeall.edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), a.text))
    end

    if !isempty(tde.edits)
        push!(commands, Command("Fix deprecation", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tde])]))
    end
    if !isempty(tdeall.edits)
        push!(commands, Command("Fix all similar deprecations in file", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tdeall])]))
    end
    response = JSONRPC.Response(get(r.id), commands)
    send(response, server)
end

function get_toks(doc, offset)
    ts = CSTParser.Tokenize.tokenize(doc._content)
    lt = nothing
    t = CSTParser.Tokenize.Lexers.next_token(ts)
    if offset >= length(doc._content)
        boffset = sizeof(doc._content) - 1 
    else
        boffset = chr2ind(doc._content, offset) - 1
    end

    while true
        if t.startbyte <= boffset <= t.endbyte
            break
        end
        lt = t
        t = CSTParser.Tokenize.Lexers.next_token(ts)
        t.startbyte:t.endbyte
    end
    return lt, t
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    
    CIs = CompletionItem[]
    doc = server.documents[URI2(r.params.textDocument.uri)] 
    rootdoc = find_root(doc, server)
    bindings = StaticLint.cat_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    lt, t = get_toks(doc, offset)

    if lt isa CSTParser.Tokens.Token && lt.kind == CSTParser.Tokenize.Tokens.BACKSLASH
        partial = string("\\", CSTParser.Tokens.untokenize(t))
        for (k, v) in Base.REPLCompletions.latex_symbols
            if startswith(string(k), partial)
                t1 = TextEdit(Range(doc, offset-length(partial)+1:offset), "")
                t2 = TextEdit(Range(doc, offset-length(partial):offset-length(partial)+1), v)
                push!(CIs, CompletionItem(k[2:end], 6, v, t1, TextEdit[t2]))
            end
        end
    else      
        partial = nothing
        for ref in doc.code.uref
            if offset == ref.loc.offset + last(ref.val.span)
                partial = ref
                break
            end
        end
        if partial == nothing
            for rref in doc.code.rref
                if offset == rref.r.loc.offset + last(rref.r.val.span)
                    partial = rref.r
                    break
                end
            end
        end
        
        if partial == nothing
            if lt isa CSTParser.Tokens.Token && lt.kind == CSTParser.Tokens.DOT
                stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
            end
        else
            spartial = CSTParser.str_value(partial.val)
            for (n,B) in bindings
                if startswith(n, spartial)
                    for i = length(B):-1:1
                        b = B[i]
                        if StaticLint.inscope(partial.index, partial.pos, b.index, b.pos)
                            push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(spartial) + 1:end]), TextEdit[]))
                            break
                        end
                    end
                end
            end
            for m in bindings["using"]
                for sym in m.val.exported
                    if startswith(string(sym), spartial)
                        comp = string(sym)
                        x = m.val.loaded[comp].val
                        push!(CIs, CompletionItem(comp, 6, MarkedString(string(Docs.doc(x))), TextEdit(Range(doc, offset:offset), comp[length(spartial) + 1:end]), TextEdit[]))
                    end
                end
            end
        end        
    end

    send(JSONRPC.Response(get(r.id), CompletionList(true, unique(CIs))), server)
end

function get_signatures(x::StaticLint.ResolvedRef, bindings, sigs = SignatureInformation[])
    if x.b.val isa Union{Function,DataType}
        for m in methods(x.b.val)
            args = Base.arg_decl_parts(m)[2]
            p_sigs = [join(string.(p), "::") for p in args[2:end]]
            desc = string(m)
            PI = map(ParameterInformation, p_sigs)
            push!(sigs, SignatureInformation(desc, "", PI))
        end
    elseif CSTParser.defines_function(x.b.val)
        for m in StaticLint.get_methods(x, bindings)
            sig = CSTParser.get_sig(m.val)
            args = StaticLint.get_fcall_args(sig, false)
            PI = map(p->ParameterInformation(string(CSTParser.str_value(p[1]))), args)
            push!(sigs, SignatureInformation(string(Expr(sig)), "", PI))
        end
    end
    return sigs
end




function get_ref(doc, offset)
    for rref in doc.code.rref
        if rref.r.loc.offset == offset
            return rref 
        elseif rref.r.loc.offset > offset
            break
        end
    end
    return nothing
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params)
    return TextDocumentPositionParams(params)
end


function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)] 
    rootdoc = find_root(doc, server)
    bindings = StaticLint.cat_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    sigs = SignatureInformation[]
    arg = 0
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
    
    if length(stack)>1 && stack[end-1] isa CSTParser.EXPR{CSTParser.Call}
        x = get_ref(doc, offsets[end-1])
        x isa Void && send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
        sigs = get_signatures(x, bindings, sigs)
        isempty(sigs) && send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
        if CSTParser.is_lparen(last(stack))
            arg = 0
        elseif CSTParser.is_rparen(last(stack))
            return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
        else
            arg = sum(!(a isa PUNCTUATION) for a in stack[end-1].args) - 1
        end
    else
        return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    end
    # y,s = scope(r.params, server)
    # if CSTParser.is_rparen(y)
    #     return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    # elseif length(s.stack) > 0 && last(s.stack) isa EXPR{Call}
    #     fcall = s.stack[end]
    #     fname = CSTParser.get_name(last(s.stack))
    #     x = get_cache_entry(fname, server, s)
    # elseif length(s.stack) > 1 && CSTParser.is_comma(s.stack[end]) && s.stack[end-1] isa EXPR{Call}
    #     fcall = s.stack[end-1]
    #     fname = CSTParser.get_name(fcall)
    #     x = get_cache_entry(fname, server, s)
    # else
    #     return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    # end
    # arg = sum(!(a isa PUNCTUATION) for a in fcall.args) - 1

    

    # for m in methods(x)
    #     args = Base.arg_decl_parts(m)[2]
    #     p_sigs = [join(string.(p), "::") for p in args[2:end]]
    #     desc = string(m)
    #     PI = map(ParameterInformation, p_sigs)
    #     push!(sigs.signatures, SignatureInformation(desc, "", PI))
    # end
    
    
    # nsEy = join(vcat(s.namespace, str_value(fname)), ".")
    # if haskey(s.symbols, nsEy)
    #     for vl in s.symbols[nsEy]
    #         if vl.v.t == :function
    #             sig = CSTParser.get_sig(vl.v.val)
    #             if sig isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(sig.op)
    #                 sig = sig.arg1
    #             end
    #             Ps = ParameterInformation[]
    #             for j = 2:length(sig.args)
    #                 if sig.args[j] isa EXPR{CSTParser.Parameters}
    #                     for parg in sig.args[j].args
    #                         if !(sig.args[j] isa PUNCTUATION)
    #                             arg_id = str_value(CSTParser._arg_id(sig.args[j]))
    #                             arg_t = CSTParser.get_t(sig.args[j])
    #                             push!(Ps, ParameterInformation(string(arg_id,"::",arg_t)))
    #                         end
    #                     end
    #                 else
    #                     if !(sig.args[j] isa PUNCTUATION)
    #                         arg_id = str_value(CSTParser._arg_id(sig.args[j]))
    #                         arg_t = CSTParser.get_t(sig.args[j])
    #                         push!(Ps, ParameterInformation(string(arg_id,"::",arg_t)))
    #                     end
    #                 end
    #             end
    #             push!(sigs.signatures, SignatureInformation(string(Expr(sig)), "", Ps))
    #         end
    #     end
    # end
    
    SH = SignatureHelp(sigs, 0, 0)
    send(JSONRPC.Response(get(r.id), SignatureHelp(filter(s -> length(s.parameters) > arg, sigs), 0, arg)), server)
end

function get_locations(rref::StaticLint.ResolvedRef, bindings, locations, server)
    if rref.b.t in (CSTParser.FunctionDef, CSTParser.Struct, CSTParser.Mutable)
        for b in StaticLint.get_methods(rref, bindings)
            get_locations(b, bindings, locations, server)
        end
    else
        get_locations(rref.b, bindings, locations, server)
    end
end

function get_locations(b::StaticLint.Binding, bindings, locations, server)
    if b.val isa CSTParser.AbstractEXPR
        uri2 = filepath2uri(b.loc.file)
        doc2 = server.documents[URI2(uri2)]
        push!(locations, Location(uri2, Range(doc2, b.loc.offset + b.val.span)))
    elseif b.val isa Function
        for m in methods(b.val)
            file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
            if (file, m.line) == DefaultTypeConstructorLoc || file == nothing
                continue
            end
            push!(locations, Location(filepath2uri(file), Range(m.line - 1, 0, m.line, 0)))
        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    locations = Location[]

    doc = server.documents[URI2(r.params.textDocument.uri)]
    rootdoc = find_root(doc, server)
    bindings = StaticLint.cat_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    for rref in doc.code.rref
        if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
            get_locations(rref, bindings, locations, server)
            break
        end
    end
    
    send(JSONRPC.Response(get(r.id), locations), server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/formatting")}}, params)
    return DocumentFormattingParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/formatting")},DocumentFormattingParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    newcontent = DocumentFormat.format(doc._content)
    end_l, end_c = get_position_at(doc, sizeof(doc._content))
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l - 1, end_c), newcontent)]

    send(JSONRPC.Response(get(r.id), lsedits), server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    documentation = Any[]
    doc = server.documents[URI2(r.params.textDocument.uri)]
    rootdoc = find_root(doc, server)
    bindings = StaticLint.cat_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)

    if last(stack) isa CSTParser.KEYWORD && last(stack).kind == CSTParser.Tokens.END && length(stack) > 1
        push!(documentation, MarkedString("Closes `$(Expr(stack[end-1].args[1]))` expression"))
    elseif CSTParser.is_rparen(last(stack)) && length(stack) > 1
        if stack[end-1] isa EXPR{CSTParser.Call}
            push!(documentation, MarkedString("Closes `$(Expr(stack[end-1].args[1]))` call"))
        elseif stack[end-1] isa EXPR{CSTParser.Tuple}
            push!(documentation, MarkedString("Closes a tuple"))
        end
    else
        for rref in doc.code.rref
            if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
                if rref.b.val isa CSTParser.AbstractEXPR
                    if rref.b.t == CSTParser.FunctionDef
                        ms = StaticLint.get_methods(rref, bindings)
                        for m in ms
                            if m.t in (CSTParser.Mutable, CSTParser.Struct)
                                push!(documentation, MarkedString(string(Expr(m.val))))
                            else
                                push!(documentation, MarkedString(string(Expr(CSTParser.get_sig(m.val)))))
                            end
                        end
                    elseif rref.b.t in (CSTParser.Abstract,CSTParser.Primitive, CSTParser.Mutable,CSTParser.Struct)
                        push!(documentation, MarkedString(string(Expr(rref.b.val))))
                    elseif rref.b.t != nothing
                        push!(documentation, MarkedString(string(rref.b.t isa CSTParser.AbstractEXPR ? Expr(rref.b.t) : rref.b.t)))
                    else
                        push!(documentation, MarkedString(string(Expr(rref.b.val))))
                    end
                else
                    push!(documentation, MarkedString(string(Docs.doc(rref.b.val))))
                end
            end
        end
    end
    
    send(JSONRPC.Response(get(r.id), Hover(unique(documentation))), server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentLink")}}, params)
    return DocumentLinkParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentLink")},DocumentLinkParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    links = Tuple{String,UnitRange{Int}}[]
    # uri = r.params.textDocument.uri 
    # doc = server.documents[URI2(uri)]
    # # get_links(doc.code.ast, 0, uri, server, links)
    # doclinks = DocumentLink[]
    # for (uri2, loc) in links
    #     rng = Range(Position(get_position_at(doc, first(loc))..., one_based = true), Position(get_position_at(doc, last(loc))..., one_based = true))
    #     push!(doclinks, DocumentLink(rng, uri2))
    # end

    send(JSONRPC.Response(get(r.id), links), server) 
end


function find_references(textDocument::TextDocumentIdentifier, position::Position, server)
    locations = Location[]
    doc = server.documents[URI2(textDocument.uri)] 
    rootdoc = find_root(doc, server)
    bindings = StaticLint.cat_bindings(server, rootdoc.code)
    refs = StaticLint.cat_references(server, rootdoc.code)
    rrefs, urefs = StaticLint.resolve_refs(refs, bindings, [], [])
    offset = get_offset(doc, position.line + 1, position.character)
    for rref in doc.code.rref
        if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
            if rref.b.t in (CSTParser.FunctionDef, CSTParser.Struct, CSTParser.Mutable)
                bs = StaticLint.get_methods(rref, bindings)
            else
                bs = StaticLint.Binding[rref.b]
            end
            for rref1 in rrefs
                if rref1.b in bs
                    uri2 = filepath2uri(rref1.r.loc.file)
                    doc2 = server.documents[URI2(uri2)]
                    rng = rref1.r.loc.offset + (0:last(rref1.r.val.span))
                    push!(locations, Location(uri2, Range(doc2, rng)))
                end
            end
            break
        end
    end
    return locations
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params)
    return ReferenceParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    locations = find_references(r.params.textDocument, r.params.position, server)
    send(JSONRPC.Response(get(r.id), locations), server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/rename")}}, params)
    return RenameParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/rename")},RenameParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
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
    
    send(JSONRPC.Response(get(r.id), WorkspaceEdit(nothing, collect(values(tdes)))), server)
end





function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    syms = SymbolInformation[]
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]

    for (name, bs) in doc.code.state.bindings
        for b in bs
            if b.index == doc.code.index && b.val isa CSTParser.AbstractEXPR
                push!(syms, SymbolInformation(name, 1, Location(doc._uri, Range(doc, b.loc.offset + b.val.span))))
            end
        end
    end
    
    send(JSONRPC.Response(get(r.id), syms), server)
end