function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return CompletionParams(params)
end

_ispath(s) = false
function _ispath(s::String)
    try
        return ispath(s)
    catch e
        return false
    end
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},CompletionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    
    CIs = CompletionItem[]
    doc = server.documents[URI2(r.params.textDocument.uri)]
    offset = get_offset(doc, r.params.position)
    rng = Range(doc, offset:offset)
    ppt, pt, t, is_at_end  = get_partial_completion(doc, offset)
    x = get_expr(getcst(doc), offset)

    if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokenize.Tokens.BACKSLASH 
        #latex completion
        latex_completions(doc, offset, CSTParser.Tokenize.untokenize(t), CIs)
    elseif ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokenize.Tokens.BACKSLASH && pt isa CSTParser.Tokens.Token && pt.kind === CSTParser.Tokens.CIRCUMFLEX_ACCENT
        latex_completions(doc, offset, join(CSTParser.Tokenize.untokenize(pt), CSTParser.Tokenize.untokenize(t)), CIs)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokenize.Tokens.STRING
        #path completion
        if t.kind == CSTParser.Tokenize.Tokens.STRING
            path, partial = splitdir(t.val[2:prevind(t.val, lastindex(t.val))])
        else
            path, partial = splitdir(t.val[4:prevind(t.val, lastindex(t.val), 3)])
        end
        if !startswith(path, "/")
            path = joinpath(_dirname(uri2filepath(doc._uri)), path)
        end
        if _ispath(path)
            fs = readdir(path)
            for f in fs
                if startswith(f, partial)
                    if isdir(joinpath(path, f))
                        f = string(f, "/")
                    end
                    push!(CIs, CompletionItem(f, 17, f, TextEdit(rng, f[length(partial) + 1:end]), TextEdit[], 1))
                end
            end
        end
        if isempty(CIs)
            ind = lastindex(partial)
            while ind >= 1
                if partial[ind] == '\\'
                    latex_completions(doc, offset, partial[ind+1:end], CIs)
                    break
                end
                ind = prevind(partial, ind)
            end
        end
    elseif x isa EXPR && x.parent !== nothing && (x.parent.typ === CSTParser.Using || x.parent.typ === CSTParser.Import || x.parent.typ === CSTParser.ImportAll)
        #import completion
        import_statement = x.parent
        if (t.kind == Tokens.WHITESPACE && pt.kind ∈ (Tokens.USING,Tokens.IMPORT,Tokens.IMPORTALL,Tokens.COMMA)) || 
            (t.kind == Tokens.COMMA)
            #no partial, no dot
            for (n,m) in StaticLint.getsymbolserver(server)
                startswith(n, ".") && continue
                push!(CIs, CompletionItem(n, 9, MarkupContent(m.doc), TextEdit(rng, n), TextEdit[], 1))
            end
        elseif t.kind == Tokens.DOT && pt.kind == Tokens.IDENTIFIER
            #no partial, dot
            if haskey(StaticLint.getsymbolserver(server), pt.val)
                collect_completions(StaticLint.getsymbolserver(server)[pt.val], "", rng, CIs, server, false)
            end
        elseif t.kind == Tokens.IDENTIFIER && is_at_end 
            #partial
            if pt.kind == Tokens.DOT && ppt.kind == Tokens.IDENTIFIER
                if haskey(StaticLint.getsymbolserver(server), ppt.val)
                    rootmod = StaticLint.getsymbolserver(server)[ppt.val]
                    for (n,m) in rootmod.vals
                        if startswith(n, t.val)
                            push!(CIs, CompletionItem(n, _completion_kind(m, server), MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), TextEdit(rng, n[length(t.val) + 1:end]), TextEdit[], 1))
                        end
                    end
                end
            else
                for (n,m) in StaticLint.getsymbolserver(server)
                    if startswith(n, t.val)
                        push!(CIs, CompletionItem(n, 9, MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), TextEdit(rng, n[nextind(n,sizeof(t.val)):end]), TextEdit[], 1))
                    end
                end
            end
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.DOT && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.IDENTIFIER 
        #getfield completion, no partial
        px = get_expr(getcst(doc), offset - (1 + t.endbyte - t.startbyte))
        _get_dot_completion(px, "", rng, CIs, server)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.DOT && ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokens.IDENTIFIER
        #getfield completion, partial
        px = get_expr(getcst(doc), offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte)) # get offset 2 tokens back
        _get_dot_completion(px, t.val, rng, CIs, server)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER
        #token completion
        if is_at_end && x != nothing
            if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.AT_SIGN
                spartial = string("@", t.val)
            else
                spartial = t.val
            end
            kw_completion(doc, spartial, ppt, pt, t, CIs, offset)
            rng = Range(doc, offset:offset)
            collect_completions(x, spartial, rng, CIs, server)
        end
    end

    send(JSONRPC.Response(r.id, CompletionList(true, unique(CIs))), server)
end

function get_partial_completion(doc, offset)
    ppt, pt, t = toks = get_toks(doc, offset)
    is_at_end = offset == t.endbyte + 1
    return ppt, pt, t, is_at_end
end

function latex_completions(doc, offset, partial, CIs)
    partial = string("\\", partial)
    for (k, v) in REPL.REPLCompletions.latex_symbols
        if startswith(string(k), partial)
            t1 = TextEdit(Range(doc, offset-sizeof(partial)+1:offset), "")
            t2 = TextEdit(Range(doc, offset-sizeof(partial):offset-sizeof(partial)+1), v)
            push!(CIs, CompletionItem(k[2:end], 11, v, t1, TextEdit[t2], 1))
        end
    end
end

function kw_completion(doc, spartial, ppt, pt, t, CIs, offset)
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
            push!(CIs, CompletionItem("let", 14, "let", TextEdit(Range(doc, offset:offset), "let \$1\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
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
            push!(CIs, CompletionItem("mutable", 14, "mutable", TextEdit(Range(doc, offset:offset), "mutable struct \$1\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
        end
    elseif startswith("outer", spartial)
        push!(CIs, CompletionItem("outer", 14, "outer", TextEdit(Range(doc, offset:offset), "outer"[length(spartial) + 1:end]), TextEdit[], 2))
    elseif startswith("primitive", spartial)
        push!(CIs, CompletionItem("primitive", 14, "primitive", TextEdit(Range(doc, offset:offset), "primitive type \$1\n    \$0\nend"[length(spartial) + 1:end]), TextEdit[], 2))
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

function collect_completions(m::SymbolServer.ModuleStore, spartial, rng, CIs, server, exportedonly = true)
    for val in m.vals
        n, v = val[1], val[2]
        startswith(n, ".") && continue
        v isa String && continue
        !startswith(n, spartial) && continue
        exportedonly && !(n in m.exported) && continue
        if v isa SymbolServer.PackageRef 
            v = SymbolServer._lookup(v, getsymbolserver(server))
            v === nothing && return 
        end
        
        push!(CIs, CompletionItem(n, _completion_kind(v, server), MarkupContent(v.doc), TextEdit(rng, n[nextind(n,sizeof(spartial)):end]), TextEdit[], 1)) 
    end
end

function collect_completions(x::EXPR, spartial, rng, CIs, server, exportedonly = false)
    if x.scope !== nothing
        _get_scope_completions(x.scope, spartial, rng, CIs, server)
        if x.scope.modules isa Dict
            for m in x.scope.modules
                collect_completions(m[2], spartial, rng, CIs, server)
            end
        end
    end
    if x.parent !== nothing && x.typ !== CSTParser.ModuleH && x.typ !== CSTParser.BareModule
        return collect_completions(x.parent, spartial, rng, CIs, server)
    else
        return
    end
end

function collect_completions(x::CSTParser.Scope, spartial, rng, CIs, server, exportedonly = false)
    _get_scope_completions(x, spartial,rng, CIs, server)
end


function _get_scope_completions(s, spartial, rng, CIs, server)
    if s.names !== nothing
        for n in s.names
            if startswith(n[1], spartial)
                push!(CIs, CompletionItem(n[1], _completion_kind(n[2], server), MarkupContent(n[1]), TextEdit(rng, n[1][nextind(n[1],sizeof(spartial)):end]), TextEdit[], 1))
            end
        end
    end
end

function _get_dot_completion(px, spartial, rng, CIs, server)
    if px != nothing
        if px.ref isa CSTParser.Binding
            if px.ref.val isa StaticLint.SymbolServer.ModuleStore
                collect_completions(px.ref.val, spartial, rng, CIs, server, false)
            elseif px.ref.t isa SymbolServer.DataTypeStore
                for a in px.ref.t.fields
                    if startswith(a, spartial)
                        push!(CIs, CompletionItem(a, 2, MarkupContent(a), TextEdit(rng, a[nextind(a,sizeof(spartial)):end]), TextEdit[], 1))
                    end
                end
            elseif px.ref.t isa CSTParser.Binding && px.ref.t.val isa SymbolServer.DataTypeStore
                for a in px.ref.t.val.fields
                    if startswith(a, spartial)
                        push!(CIs, CompletionItem(a, 2, MarkupContent(a), TextEdit(rng, a[nextind(a,sizeof(spartial)):end]), TextEdit[], 1))
                    end
                end
            elseif px.ref.val isa EXPR && px.ref.val.typ === CSTParser.ModuleH && px.ref.val.scope isa CSTParser.Scope
                _get_scope_completions(px.ref.val.scope, spartial, rng, CIs, server)
            elseif px.ref.t isa CSTParser.Binding && px.ref.t.val isa EXPR && CSTParser.defines_struct(px.ref.t.val) && px.ref.t.val.scope isa CSTParser.Scope
                _get_scope_completions(px.ref.t.val.scope, spartial, rng, CIs, server)
            end
        elseif px.ref isa StaticLint.SymbolServer.ModuleStore
            collect_completions(px.ref, spartial, rng, CIs, server, false)
        end
    end
end

function _completion_kind(b ,server)
    if b isa CSTParser.Binding
        if b.t == getsymbolserver(server)["Core"].vals["String"]
            return 1
        elseif b.t == getsymbolserver(server)["Core"].vals["Function"]
            return 2
        elseif b.t == getsymbolserver(server)["Core"].vals["Module"]
            return 9
        elseif b.t == getsymbolserver(server)["Core"].vals["Int"] || b.t == getsymbolserver(server)["Core"].vals["Float64"]
            return 12
        elseif b.t == getsymbolserver(server)["Core"].vals["DataType"]
            return 22
        else 
            return 13
        end
    elseif b isa SymbolServer.ModuleStore || b isa SymbolServer.PackageRef
        return 9
    elseif b isa SymbolServer.MethodStore
        return 2        
    elseif b isa SymbolServer.FunctionStore
        return 3
    elseif b isa SymbolServer.DataTypeStore
        return 22
    else 
        return 6
    end
end

