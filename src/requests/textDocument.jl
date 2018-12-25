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
        server.documents[URI2(r.params.textDocument.uri)] = Document(r.params.textDocument.uri, "", true, server)
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
    # if !haskey(server.documents, URI2(r.params.textDocument.uri))
    #     send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
    #     return
    # end
    # doc = server.documents[URI2(r.params.textDocument.uri)]
    commands = Command[]
    # range = r.params.range
    # range_loc = get_offset(doc, range.start.line + 1, range.start.character):get_offset(doc, range.stop.line + 1, range.stop.character)
    
    # tde = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
    # action_type = Any
    # tdeall = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
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
    # file_actions = []
    # for d in doc.diagnostics
    #     if typeof(d).parameters[1] == action_type && !isempty(d.actions) 
    #         for a in d.actions
    #             push!(file_actions, a)
                
    #         end
    #     end
    # end
    # sort!(file_actions, lt = (a, b) -> last(b.range) < first(a.range))
    # for a in file_actions
    #     start_l, start_c = get_position_at(doc, first(a.range))
    #     end_l, end_c = get_position_at(doc, last(a.range))
    #     push!(tdeall.edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), a.text))
    # end

    # if !isempty(tde.edits)
    #     push!(commands, Command("Fix deprecation", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tde])]))
    # end
    # if !isempty(tdeall.edits)
    #     push!(commands, Command("Fix all similar deprecations in file", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tdeall])]))
    # end
    response = JSONRPC.Response(r.id, commands)
    send(response, server)
end

function get_partial_completion(doc, offset)
    ppt, pt, t = toks = get_toks(doc, offset)
    is_at_end = offset == t.endbyte + 1
    partial = nothing
    for ref in doc.code.uref
        if offset == ref.loc.offset + ref.val.span
            partial = ref
            break
        end
    end
    if partial == nothing
        for rref in doc.code.rref
            if offset == rref.r.loc.offset + rref.r.val.span
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
            push!(CIs, CompletionItem(k[2:end], 6, v, t1, TextEdit[t2], 1))
        end
    end
end

function kw_completion(doc, spartial, ppt, pt, t, offsets, stack, CIs, offset)
    length(spartial) == 0 && return
    fc = first(spartial)
    if startswith("abstract", spartial)
    elseif fc == 'b'
        if startswith("baremodule", spartial)
            push!(CIs, CompletionItem("baremodule", 14, "baremodule", TextEdit(Range(doc, offset:offset), "baremodule \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("begin", spartial)
            push!(CIs, CompletionItem("begin", 14, "begin", TextEdit(Range(doc, offset:offset), "begin\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("break", spartial)
            push!(CIs, CompletionItem("break", 14, "break", TextEdit(Range(doc, offset:offset), "break"[length(spartial) + 1:end]), TextEdit[], 1))
        end
    elseif fc == 'c'
        if startswith("catch", spartial)
            push!(CIs, CompletionItem("catch", 14, "catch", TextEdit(Range(doc, offset:offset), "catch"[length(spartial) + 1:end]), TextEdit[], 1))
        end
        if startswith("const", spartial)
            push!(CIs, CompletionItem("const", 14, "const", TextEdit(Range(doc, offset:offset), "const \$0"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("continue", spartial)
            push!(CIs, CompletionItem("continue", 14, "continue", TextEdit(Range(doc, offset:offset), "continue"[length(spartial) + 1:end]), TextEdit[], 1))
        end
    elseif startswith("do", spartial)
        push!(CIs, CompletionItem("do", 14, "do", TextEdit(Range(doc, offset:offset), "do \$0\n end"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif fc == 'e'
        if startswith("else", spartial)
            push!(CIs, CompletionItem("else", 14, "else", TextEdit(Range(doc, offset:offset), "else"[length(spartial) + 1:end]), TextEdit[], 1))
        end
        if startswith("elseif", spartial)
            push!(CIs, CompletionItem("elseif", 14, "elseif", TextEdit(Range(doc, offset:offset), "elseif"[length(spartial) + 1:end]), TextEdit[], 1))
        end
        if startswith("end", spartial)
            push!(CIs, CompletionItem("end", 14, "end", TextEdit(Range(doc, offset:offset), "end"[length(spartial) + 1:end]), TextEdit[], 1))
        end
        if startswith("export", spartial)
            push!(CIs, CompletionItem("export", 14, "export", TextEdit(Range(doc, offset:offset), "export \$0"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif fc == 'f'
        if startswith("finally", spartial)
            push!(CIs, CompletionItem("finally", 14, "finally", TextEdit(Range(doc, offset:offset), "finally"[length(spartial) + 1:end]), TextEdit[], 1))
        end
        if startswith("for", spartial)
            push!(CIs, CompletionItem("for", 14, "for", TextEdit(Range(doc, offset:offset), "for \$1 in \$2\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("function", spartial)
            push!(CIs, CompletionItem("function", 14, "function", TextEdit(Range(doc, offset:offset), "function \$1(\$2)\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif startswith("global", spartial)
        push!(CIs, CompletionItem("global", 14, "global", TextEdit(Range(doc, offset:offset), "global \$0\n"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif fc == 'i'
        if startswith("if", spartial)
            push!(CIs, CompletionItem("if", 14, "if", TextEdit(Range(doc, offset:offset), "if \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("import", spartial)
            push!(CIs, CompletionItem("import", 14, "import", TextEdit(Range(doc, offset:offset), "import \$0\n"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("importall", spartial)
            push!(CIs, CompletionItem("importall", 14, "importall", TextEdit(Range(doc, offset:offset), "importall \$0\n"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif fc == 'l'
        if startswith("let", spartial)
            push!(CIs, CompletionItem("let", 14, "let", TextEdit(Range(doc, offset:offset), "let \$1\n   \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("local", spartial)
            push!(CIs, CompletionItem("local", 14, "local", TextEdit(Range(doc, offset:offset), "local \$0\n"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif fc == 'm'
        if startswith("macro", spartial)
            push!(CIs, CompletionItem("macro", 14, "macro", TextEdit(Range(doc, offset:offset), "macro \$1(\$2)\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("module", spartial)
            push!(CIs, CompletionItem("module", 14, "module", TextEdit(Range(doc, offset:offset), "module \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
        if startswith("mutable", spartial)
            push!(CIs, CompletionItem("mutable", 14, "mutable", TextEdit(Range(doc, offset:offset), "mutable struct \$1\n   \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif startswith("outer", spartial)
        push!(CIs, CompletionItem("outer", 14, "outer", TextEdit(Range(doc, offset:offset), "outer"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif startswith("primitive", spartial)
        push!(CIs, CompletionItem("primitive", 14, "primitive", TextEdit(Range(doc, offset:offset), "primitive type \$1\n   \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif startswith("quote", spartial)
        push!(CIs, CompletionItem("quote", 14, "quote", TextEdit(Range(doc, offset:offset), "quote\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif startswith("return", spartial)
        push!(CIs, CompletionItem("return", 14, "return", TextEdit(Range(doc, offset:offset), "return \$0\n"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif startswith("struct", spartial)
        push!(CIs, CompletionItem("struct", 14, "struct", TextEdit(Range(doc, offset:offset), "struct \$1\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif fc == 't'
        if startswith("try", spartial)
            push!(CIs, CompletionItem("try", 14, "try", TextEdit(Range(doc, offset:offset), "try \$1\n    \$0\ncatch\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif startswith("using", spartial)
        push!(CIs, CompletionItem("using", 14, "using", TextEdit(Range(doc, offset:offset), "using \$0\n"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif startswith("while", spartial)
        push!(CIs, CompletionItem("while", 14, "while", TextEdit(Range(doc, offset:offset), "while \$1\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return CompletionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},CompletionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    
    CIs = CompletionItem[]
    doc = server.documents[URI2(r.params.textDocument.uri)]        
    rootdoc = find_root(doc, server)
    state = StaticLint.build_bindings(rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    partial, ppt, pt, t, is_at_end  = get_partial_completion(doc, offset)
    toks = ppt, pt, t 
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)

    if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokenize.Tokens.BACKSLASH 
        #latex completion
        latex_completions(doc, offset, toks, CIs)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokenize.Tokens.STRING
        #path completion
        path, partial = splitdir(t.val[2:prevind(t.val, length(t.val))])
        if !startswith(path, "/")
            path = joinpath(dirname(uri2filepath(doc._uri)), path)  
        end
        if ispath(path)
            fs = readdir(path)
            for f in fs
                if startswith(f, partial)
                    if isdir(joinpath(path, f))
                        f = string(f, "/")
                    end
                    push!(CIs, CompletionItem(f, 6, f, TextEdit(Range(doc, offset:offset), f[length(partial) + 1:end]), TextEdit[], 1))
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
            for (n,m) in server.packages
                startswith(n, ".") && continue
                push!(CIs, CompletionItem(n, 6, MarkupContent(m.doc), TextEdit(Range(doc, offset:offset), n), TextEdit[], 1))
            end
        elseif t.kind == Tokens.DOT && pt.kind == Tokens.IDENTIFIER
            #no partial, dot
            if haskey(server.packages, pt.val)
                rootmod = server.packages[pt.val]
                for (n,m) in rootmod.vals
                    startswith(n, ".") && continue
                    push!(CIs, CompletionItem(n, 6, MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), TextEdit(Range(doc, offset:offset), n[nextind(n,sizeof(t.val)):end]), TextEdit[], 1))
                end
            end
        elseif t.kind == Tokens.IDENTIFIER && is_at_end 
            #partial
            if pt.kind == Tokens.DOT && ppt.kind == Tokens.IDENTIFIER
                if haskey(server.packages, ppt.val)
                    rootmod = server.packages[ppt.val]
                    for (n,m) in rootmod.vals
                        if startswith(n, t.val)
                            push!(CIs, CompletionItem(n, 6, MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), TextEdit(Range(doc, offset:offset), n[length(t.val) + 1:end]), TextEdit[], 1))
                        end
                    end
                end
            else
                for (n,m) in server.packages
                    if startswith(n, t.val)
                        push!(CIs, CompletionItem(n, 6, MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), TextEdit(Range(doc, offset:offset), n[nextind(n,sizeof(t.val)):end]), TextEdit[], 1))
                    end
                end
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.DOT && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.IDENTIFIER 
        #getfield completion, no partial
        offset1 = offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte)
        ref = find_ref(doc, offset1)
        if ref != nothing && ref.b.val isa StaticLint.SymbolServer.ModuleStore # check we've got a Module
            for (n,v) in ref.b.val.vals
                startswith(n, ".") && continue 
                push!(CIs, CompletionItem(n, 6, MarkupContent(n), TextEdit(Range(doc, offset:offset), n), TextEdit[], 1))
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.DOT && ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokens.IDENTIFIER
        #getfield completion, partial
        offset1 = offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte) - (1 + ppt.endbyte - ppt.startbyte) # get offset 2 tokens back
        ref = find_ref(doc, offset1) 
        if ref != nothing && ref.b.val isa StaticLint.SymbolServer.ModuleStore # check we've got a Module
            for (n,v) in ref.b.val.vals
                if startswith(n, t.val)
                    push!(CIs, CompletionItem(n, 6, MarkupContent(v isa SymbolServer.SymStore ? v.doc : n), TextEdit(Range(doc, offset:offset), n[nextind(n,sizeof(t.val)):end]), TextEdit[], 1))
                end
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER
        #token completion
        if is_at_end && partial != nothing
            if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.AT_SIGN
                spartial = string("@", t.val)
            else
                spartial = t.val
            end
            kw_completion(doc, spartial, ppt, pt, t, offsets, stack, CIs, offset)
            lbsi = StaticLint.get_lbsi(partial, state).i
            si = partial.si.i
            
            while length(si) >= length(lbsi)
                if haskey(state.bindings, si)
                    for (n,B) in state.bindings[si]
                        if startswith(n, spartial)
                            push!(CIs, CompletionItem(n, 6, MarkupContent(n), TextEdit(Range(doc, offset:offset), n[nextind(n,sizeof(spartial)):end]), TextEdit[], 1))
                        end
                    end
                end
                if length(si) == 0
                    break
                else
                    si = StaticLint.shrink_tuple(si)
                end
            end
            for m in state.used_modules #iterate over imported modules
                for sym in m.val.exported
                    if startswith(string(sym), spartial)
                        comp = string(sym)
                        !haskey(m.val.vals, comp) && continue
                        x = m.val.vals[comp]
                        docs = x isa StaticLint.SymbolServer.SymStore ? x.doc : ""
                        push!(CIs, CompletionItem(comp, 6, MarkupContent(docs), TextEdit(Range(doc, offset:offset), comp[nextind(comp, sizeof(spartial)):end]), TextEdit[], 1))
                    end
                end
            end
        end
    end

    send(JSONRPC.Response(r.id, CompletionList(true, unique(CIs))), server)
end

# temp fix for user defined sigs
function get_sig_args(sig)
    while sig isa CSTParser.WhereOpCall
        sig = sig.arg1
    end
    state, s = StaticLint.State(), StaticLint.Scope()
    StaticLint.get_fcall_bindings(sig, state, s)
    out = Tuple{Int,String}[]
    if haskey(state.bindings, ())
        for (n,B) in state.bindings[()]
            b = last(B)
            push!(out, (b.si.n, n))
        end
    end
    sort!(out, lt = (a,b)->a[1]<b[1])   
    return [o[2] for o in out]
end

function get_signatures(x::StaticLint.ResolvedRef, state, sigs = SignatureInformation[])
    if x.b.val isa StaticLint.SymbolServer.FunctionStore || x.b.val isa StaticLint.SymbolServer.structStore
        for m in x.b.val.methods
            p_sigs = [join(string.(p), "::") for p in m.args]
            PI = map(ParameterInformation, p_sigs)
            push!(sigs, SignatureInformation("$(CSTParser.str_value(x.r.val))($(join(p_sigs, ",")))", "", PI))
        end
    elseif CSTParser.defines_function(x.b.val)
        for m in StaticLint.get_methods(x, state)
            !(m.val isa CSTParser.AbstractEXPR) && continue 
            sig = CSTParser.get_sig(m.val)
            args = get_sig_args(sig)
            PI = map(p->ParameterInformation(string(p)), args)
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
    state = StaticLint.build_bindings(rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    sigs = SignatureInformation[]
    arg = 0
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
    
    if length(stack)>1 && stack[end-1] isa CSTParser.EXPR{CSTParser.Call}
        call_ex = stack[end-1]
        fname = call_ex.args[1]
        if fname isa CSTParser.EXPR{CSTParser.Curly}
            fname = fname.args[1]
        end
        fname_offset = offsets[end-1]
        if fname isa CSTParser.BinarySyntaxOpCall && fname.op.kind == CSTParser.Tokens.DOT
            fname_offset += fname.arg1.fullspan + fname.op.fullspan
        end

        x = find_ref(doc, fname_offset)
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
        elseif CSTParser.is_rparen(last(stack)) && offset > last(offsets) 
            return send(JSONRPC.Response(r.id, CancelParams(Dict("id" => r.id))), server)
        else
            arg = sum(!(a isa PUNCTUATION) for a in call_ex.args) - 2
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
    state = StaticLint.build_bindings(rootdoc.code)
    offset = get_offset(doc, r.params.position.line + 1, r.params.position.character)
    stack, offsets = StaticLint.get_stack(doc.code.cst, offset)
    if length(stack)>2 && stack[end] isa CSTParser.LITERAL && stack[end].kind == CSTParser.Tokens.STRING && stack[end-1] isa CSTParser.EXPR{CSTParser.Call} && length(stack[end-1]) == 4 && stack[end-1].args[1] isa CSTParser.IDENTIFIER && stack[end-1].args[1].val == "include"
        path = (joinpath(dirname(doc._uri), stack[end].val))
        if haskey(server.documents, URI2(path))
            push!(locations, Location(path, 1))
        end
    else
        for rref in doc.code.rref
            if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
                get_locations(rref, state, locations, server)
                break
            end
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
    state = StaticLint.build_bindings(rootdoc.code)
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
                    if rref.b.t == server.packages["Core"].vals["Function"]
                        ms = StaticLint.get_methods(rref, state)
                        for m in ms
                            if m.val isa StaticLint.SymbolServer.FunctionStore || m.val isa StaticLint.SymbolServer.structStore
                                fname = CSTParser.str_value(rref.r.val)
                                for m1 in m.val.methods
                                    push!(documentation, MarkedString(string(fname, "(", join((a->string(a[1], "::", a[2])).(m1.args), ", "),")"))) 
                                end
                            elseif m.t == server.packages["Core"].vals["DataType"]
                                push!(documentation, MarkedString(string(Expr(m.val))))
                            else
                                push!(documentation, MarkedString(string(Expr(CSTParser.get_sig(m.val)))))
                            end
                        end
                    elseif rref.b.t == server.packages["Core"].vals["DataType"]
                        push!(documentation, MarkedString(string(Expr(rref.b.val))))
                    elseif rref.b.t != nothing
                        if rref.b.t isa CSTParser.AbstractEXPR
                            push!(documentation, MarkedString(string(Expr(rref.b.t) )))
                        elseif rref.b.t isa StaticLint.SymbolServer.SymStore
                            push!(documentation, MarkedString(replace(replace(rref.b.t.doc, "```"=>""), "\n\n" => "\n")))
                        end
                    else
                        push!(documentation, MarkedString(string(Expr(rref.b.val))))
                    end
                elseif rref.b.val isa StaticLint.SymbolServer.SymStore
                    push!(documentation, MarkedString(replace(replace(rref.b.val.doc, "```"=>""), "\n\n" => "\n")))
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
    state = StaticLint.build_bindings(rootdoc.code)
    refs = StaticLint.cat_references(rootdoc.code)
    rrefs, urefs = StaticLint.resolve_refs(refs, state, [], [])
    offset = get_offset(doc, position.line + 1, position.character)
    for rref in doc.code.rref
        if rref.r.loc.offset <= offset <= rref.r.loc.offset + rref.r.val.fullspan
            rref.b isa StaticLint.ImportBinding && continue
            if rref.b.t in (server.packages["Core"].vals["Function"], server.packages["Core"].vals["DataType"])
                bs = StaticLint.get_methods(rref, state)
            else
                bs = StaticLint.Binding[rref.b]
            end
            for rref1 in rrefs
                if rref1.b in bs
                    uri2 = filepath2uri(rref1.r.loc.file)
                    doc2 = server.documents[URI2(uri2)]
                    rng = rref1.r.loc.offset .+ (0:rref1.r.val.span)
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

    for (s, S) in doc.code.state.bindings
        for (name, B) in S
            isempty(name) && continue
            for b in B
                push!(syms, SymbolInformation(name, 1, false, Location(doc._uri, Range(doc, b.loc.offset .+ (0:b.val.span))), nothing))
            end
        end
    end
    send(JSONRPC.Response(r.id, syms), server)
end
