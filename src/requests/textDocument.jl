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
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        server.documents[URI2(r.params.textDocument.uri)] = Document(r.params.textDocument.uri, "", true)
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    doc._version = r.params.textDocument.version
    isempty(r.params.contentChanges) && return
    
    doc._content = last(r.params.contentChanges).text
    doc._line_offsets = nothing
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
    response = JSONRPC.Response(r.id, TextEdit[])
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/codeAction")}}, params)
    return CodeActionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/codeAction")},CodeActionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
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
    response = JSONRPC.Response(r.id, commands)
    send(response, server)
end

function get_partial_completion(doc, offset)
    ppt, pt, t = toks = get_toks(doc, offset)
    is_at_end = offset == t.endbyte + 1
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
    return partial, ppt, pt, t, is_at_end
end

function latex_completions(doc, offset, toks, CIs)
    ppt, pt, t = toks
    partial = string("\\", CSTParser.Tokens.untokenize(t))
    for (k, v) in REPL.REPLCompletions.latex_symbols
        if startswith(string(k), partial)
            t1 = TextEdit(Range(doc, offset-length(partial)+1:offset), "")
            t2 = TextEdit(Range(doc, offset-length(partial):offset-length(partial)+1), v)
            push!(CIs, CompletionItem(k[2:end], 6, v, t1, TextEdit[t2]))
        end
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    
    CIs = CompletionItem[]
    doc = server.documents[URI2(r.params.textDocument.uri)]        
    rootdoc = find_root(doc, server)
    state = StaticLint.build_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    partial, ppt, pt, t, is_at_end  = get_partial_completion(doc, offset)
    toks = ppt, pt, t 
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)

    if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokenize.Tokens.BACKSLASH 
        #latex completion
        latex_completions(doc, offset, toks, CIs)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokenize.Tokens.STRING  #last(stack) isa CSTParser.LITERAL && last(stack).kind == CSTParser.Tokens.STRING
        #path completion
        path, partial = splitdir(t.val[2:end-1])
        if !startswith(path, "/")
            path = joinpath(dirname(uri2filepath(doc._uri)), path)  
        end
        if ispath(path)
            fs = readdir(path)
            for f in fs
                if startswith(f, partial)
                    push!(CIs, CompletionItem(f, 6, f, TextEdit(Range(doc, offset:offset), f[length(partial) + 1:end]), TextEdit[]))
                end
            end
        end
    elseif length(stack) > 1 && (stack[end-1] isa CSTParser.EXPR{CSTParser.Using} || 
        stack[end-1] isa CSTParser.EXPR{CSTParser.Import} || stack[end-1] isa CSTParser.EXPR{CSTParser.ImportAll})
        #import completion
        import_statement = stack[end-1]
        if (t.kind == Tokens.WHITESPACE && pt.kind ∈ (Tokens.USING,Tokens.IMPORT,Tokens.IMPORTALL,Tokens.COMMA)) || 
            (t.kind == Tokens.COMMA)
            #no partial, no dot
            for (n,m) in StaticLint.store
                startswith(n, ".") && continue
                push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n), TextEdit[]))
            end
        elseif t.kind == Tokens.DOT && pt.kind == Tokens.IDENTIFIER
            #no partial, dot
            if haskey(StaticLint.store, pt.val)
                rootmod = StaticLint.store[pt.val]
                for (n,m) in rootmod
                    startswith(n, ".") && continue
                    push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(t.val) + 1:end]), TextEdit[]))
                end
            end
        elseif t.kind == Tokens.IDENTIFIER && is_at_end 
            #partial
            if pt.kind == Tokens.DOT && ppt.kind == Tokens.IDENTIFIER
                if haskey(StaticLint.store, ppt.val)
                    rootmod = StaticLint.store[ppt.val]
                    for (n,m) in rootmod
                        if startswith(n, t.val)
                            push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(t.val) + 1:end]), TextEdit[]))
                        end
                    end
                end
            else
                for (n,m) in StaticLint.store
                    if startswith(n, t.val)
                        push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(t.val) + 1:end]), TextEdit[]))
                    end
                end
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.DOT && length(stack) > 1 && stack[end-1] isa CSTParser.BinarySyntaxOpCall
        #getfield completion, no partial
        n = length(stack)
        if n > 2 && (stack[end] isa CSTParser.OPERATOR && stack[end].kind == CSTParser.Tokens.DOT) && stack[end-1] isa CSTParser.BinarySyntaxOpCall
            offset1 = offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte)
            ref = find_ref(doc, offset1)
            if ref != nothing && ref.b.val isa Dict
                for (n,v) in ref.b.val
                    startswith(n, ".") && continue 
                    push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n), TextEdit[]))
                end
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.DOT &&
        length(stack) > 2 && stack[end-1] isa CSTParser.EXPR{CSTParser.Quotenode} && stack[end-2] isa CSTParser.BinarySyntaxOpCall
        #getfield completion, partial
        n = length(stack)
        if n > 2 && stack[end-1] isa CSTParser.EXPR{CSTParser.Quotenode} && stack[end-2] isa CSTParser.BinarySyntaxOpCall
            offset1 = offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte) - (1 + ppt.endbyte - ppt.startbyte) # get offset 2 tokens back
            ref = find_ref(doc, offset1) 
            if ref != nothing && ref.b.val isa Dict # check we've got a Module
                for (n,v) in ref.b.val
                    if startswith(n, t.val)
                        push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(t.val) + 1:end]), TextEdit[]))
                    end
                end
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokenize.Tokens.IDENTIFIER
        #token completion
        if is_at_end && partial != nothing
            spartial = t.val
            lbsi = StaticLint.get_lbsi(partial, state).i
            si = partial.si.i
            
            while length(si) >= length(lbsi)
                if haskey(state.bindings, si)
                    for (n,B) in state.bindings[si]
                        if startswith(n, spartial)
                            push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(spartial) + 1:end]), TextEdit[]))
                        end
                    end
                end
                if length(si) == 0
                    break
                else
                    si = StaticLint.shrink_tuple(si)
                end
            end
            # for (n,B) in state.bindings #iterate over bindings
            #     if startswith(n, spartial)
            #         for i = length(B):-1:1
            #             b = B[i]
            #             if StaticLint.inscope(partial.si, b.si) #only allow bindings in the current scope
            #                 push!(CIs, CompletionItem(n, 6, n, TextEdit(Range(doc, offset:offset), n[length(spartial) + 1:end]), TextEdit[]))
            #                 break
            #             end
            #         end
            #     end
            # end
            for (n,m) in state.used_modules #iterate over imported modules
                for sym in m.val[".exported"]
                    if startswith(string(sym), spartial)
                        comp = string(sym)
                        !haskey(m.val, comp) && continue
                        x = m.val[comp]
                        push!(CIs, CompletionItem(comp, 6, MarkedString(get(x, ".doc", "")), TextEdit(Range(doc, offset:offset), comp[length(spartial) + 1:end]), TextEdit[]))
                    end
                end
            end
        end
    end

    
    
    send(JSONRPC.Response(r.id, CompletionList(true, unique(CIs))), server)
end

function get_signatures(x::StaticLint.ResolvedRef, state, sigs = SignatureInformation[])
    if x.b.val isa Dict && haskey(x.b.val, ".methods")
        for m in x.b.val[".methods"]
            p_sigs = [join(string.(p), "::") for p in m["args"]]
            PI = map(ParameterInformation, p_sigs)
            push!(sigs, SignatureInformation("$(CSTParser.str_value(x.r.val))($(join(p_sigs, ",")))", "", PI))
        end
    elseif CSTParser.defines_function(x.b.val)
        for m in StaticLint.get_methods(x, state)
            sig = CSTParser.get_sig(m.val)
            args = StaticLint.get_fcall_args(sig, false)
            PI = map(p->ParameterInformation(string(CSTParser.str_value(p[1]))), args)
            push!(sigs, SignatureInformation(string(Expr(sig)), "", PI))
        end
    end
    return sigs
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
    rootdoc = find_root(doc, server)
    state = StaticLint.build_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    sigs = SignatureInformation[]
    arg = 0
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
    
    if length(stack)>1 && stack[end-1] isa CSTParser.EXPR{CSTParser.Call}
        x = find_ref(doc, offsets[end-1])
        if x isa Nothing 
            send(JSONRPC.Response(r.id, CancelParams(Dict("id" => r.id))), server)
            return
        end
        sigs = get_signatures(x, state, sigs)
        if isempty(sigs)
            send(JSONRPC.Response(r.id, CancelParams(Dict("id" => r.id))), server)
            return
        end
        if CSTParser.is_lparen(last(stack))
            arg = 0
        elseif CSTParser.is_rparen(last(stack))
            return send(JSONRPC.Response(r.id, CancelParams(Dict("id" => r.id))), server)
        else
            arg = sum(!(a isa PUNCTUATION) for a in stack[end-1].args) - 1
        end
    else
        return send(JSONRPC.Response(r.id, CancelParams(Dict("id" => r.id))), server)
    end
    
    send(JSONRPC.Response(r.id, SignatureHelp(filter(s -> length(s.parameters) > arg, sigs), 0, arg)), server)
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
    rootdoc = find_root(doc, server)
    state = StaticLint.build_bindings(server, rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    for rref in doc.code.rref
        if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
            get_locations(rref, state, locations, server)
            break
        end
    end
    
    send(JSONRPC.Response(r.id, locations), server)
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
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l - 1, end_c), newcontent)]

    send(JSONRPC.Response(r.id, lsedits), server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    documentation = Any[]
    doc = server.documents[URI2(r.params.textDocument.uri)]
    rootdoc = find_root(doc, server)
    state = StaticLint.build_bindings(server, rootdoc.code)
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
                        ms = StaticLint.get_methods(rref, state)
                        for m in ms
                            if m.val isa Dict && haskey(m.val, ".methods")
                                fname = CSTParser.str_value(rref.r.val)
                                for m1 in m.val[".methods"]
                                    push!(documentation, MarkedString(string(fname, "(", join((a->string(a[1], "::", a[2])).(m1["args"]), ", "),")"))) 
                                end
                            elseif m.t in (CSTParser.Mutable, CSTParser.Struct)
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
                    push!(documentation, MarkedString(string(get(rref.b.val, ".doc", ""))))
                end
            end
        end
    end
    
    send(JSONRPC.Response(r.id, Hover(unique(documentation))), server)
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
    # uri = r.params.textDocument.uri 
    # doc = server.documents[URI2(uri)]
    # # get_links(doc.code.ast, 0, uri, server, links)
    # doclinks = DocumentLink[]
    # for (uri2, loc) in links
    #     rng = Range(Position(get_position_at(doc, first(loc))..., one_based = true), Position(get_position_at(doc, last(loc))..., one_based = true))
    #     push!(doclinks, DocumentLink(rng, uri2))
    # end

    send(JSONRPC.Response(r.id, links), server) 
end


function find_references(textDocument::TextDocumentIdentifier, position::Position, server)
    locations = Location[]
    doc = server.documents[URI2(textDocument.uri)] 
    rootdoc = find_root(doc, server)
    state = StaticLint.build_bindings(server, rootdoc.code)
    refs = StaticLint.cat_references(server, rootdoc.code)
    rrefs, urefs = StaticLint.resolve_refs(refs, state, [], [])
    offset = get_offset(doc, position.line + 1, position.character)
    for rref in doc.code.rref
        if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
            rref.b isa StaticLint.ImportBinding && continue
            if rref.b.t in (CSTParser.FunctionDef, CSTParser.Struct, CSTParser.Mutable)
                bs = StaticLint.get_methods(rref, state)
            else
                bs = StaticLint.Binding[rref.b]
            end
            for rref1 in rrefs
                if rref1.b in bs
                    uri2 = filepath2uri(rref1.r.loc.file)
                    doc2 = server.documents[URI2(uri2)]
                    rng = rref1.r.loc.offset .+ (0:last(rref1.r.val.span))
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

    for (name,b) in StaticLint.collect_bindings(doc.code)
        push!(syms, SymbolInformation(name, 1, false, Location(doc._uri, Range(doc, b.loc.offset .+ b.val.span)), nothing))
    end
    
    send(JSONRPC.Response(r.id, syms), server)
end
