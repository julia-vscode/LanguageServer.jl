function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    y, s = scope(tdpp, server)
    line = get_line(tdpp, server)

    if isempty(line) || line == "\n" || tdpp.position.character == 0
        word = ""
    else
        word = let io = IOBuffer()
            if isempty(line)
                ""
            else
                rline = reverse(line[1:chr2ind(line, min(length(line), tdpp.position.character))])
                for (i, c) in enumerate(rline)
                    if c == '\\' || c == '@'
                        write(io, c)
                        break
                    end
                    if !(Base.is_id_char(c) || c == '.' || c == '_' || (c == '^' && i < length(rline) && rline[i + 1] == '\\'))
                        break
                    end
                    write(io, c)
                end
                reverse(String(take!(io)))
            end
        end
    end

    entries = Tuple{Symbol,Int,String}[]

    if word == "end"
        push!(entries, ("end", 6, "end"))
    elseif word == "else"
        push!(entries, ("else", 6, "else"))
    elseif word == "elseif"
        push!(entries, ("elseif", 6, "elseif"))
    elseif word == "catch"
        push!(entries, ("catch", 6, "catch"))
    elseif word == "finally"
        push!(entries, ("finally", 6, "finally"))
    end

    prefix = word[1:searchlast(word, '.')]
    if isempty(word) && isempty(prefix) && !CSTParser.isstring(y)
    elseif isempty(prefix) # Single word
        if startswith(word, "\\") # Latex completion
            for (k, v) in Base.REPLCompletions.latex_symbols
                if startswith(string(k), word)
                    push!(entries, (Base.REPLCompletions.latex_symbols[k], 1, k))
                    length(entries) > 200 && break
                end
            end
        else
            ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
            if CSTParser.isstring(y) && isabspath(str_value(y))
                dloc = last(search(line, Regex(str_value(y)))) - last(search(line, Regex(word)))
                paths, loc, _ = Base.REPLCompletions.complete_path(str_value(y), length(str_value(y)) - dloc)
                for p in paths
                    push!(entries, (p, 17, ""))
                end
            else
                for name in BaseCoreNames
                    if startswith(string(name), word) && (isdefined(Base, name) || isdefined(Core, name))
                        x = getfield(Main, name)
                        doc = string(Docs.doc(Docs.Binding(Main, name)))
                        push!(entries, (string(name), CompletionItemKind(typeof(x)), doc))
                    end
                end
                if haskey(s.imported_names, ns)
                    for name in s.imported_names[ns]
                        if startswith(name, word) 
                            x = get_cache_entry(name, server, s)
                            # doc = string(Docs.doc(Docs.Binding(M, Symbol(name))))
                            push!(entries, (name, CompletionItemKind(typeof(x)), ""))
                        end
                    end
                end
                if y != nothing
                    Ey = Expr(y)
                    nsEy = make_name(s.namespace, Ey)
                    partial = ns == "toplevel" ? string(Ey) : nsEy
                    for (name, V) in s.symbols
                        if startswith(string(name), partial) 
                            push!(entries, (string(first(V).v.id), 6, ""))
                        end
                    end
                end
            end
        end
    else
        topmodname = Symbol(first(split(prefix, '.')))
        modname = unpack_dot(parse(strip(prefix, '.'), raise = false))
        M = get_module(modname)
        if M != false && M isa Module
            server.loaded_modules[strip(prefix, '.')] = load_mod_names(M)
        end
        partial = word[searchlast(word, '.') + 1:end]
        if strip(prefix, '.') in keys(server.loaded_modules)
            for name in server.loaded_modules[strip(prefix, '.')][2]
                if startswith(name, partial) && isdefined(M, Symbol(name))
                    x = getfield(M, Symbol(name))
                    doc = string(Docs.doc(Docs.Binding(M, Symbol(name))))
                    push!(entries, (name, CompletionItemKind(typeof(x)), doc))
                    length(entries) > 200 && break
                end
            end
        end
    end

    l, c = tdpp.position.line, tdpp.position.character
    CIs = CompletionItem[]
    for (comp, k, documentation) in entries
        newtext = string(comp)
        if startswith(documentation, "\\")
            label  = strip(documentation, '\\')
            documentation = newtext
            length(newtext) > 1 && (newtext = newtext[1:1])
        elseif k == 17 # file completion
            label = comp
            documentation = ""
        else
            label  = last(split(newtext, "."))
            documentation = replace(documentation, r"(`|\*\*)", "")
            documentation = replace(documentation, "\n\n", "\n")
        end

        if k == 1
            push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(l, c - endof(word) + endof(newtext), l, c), ""), [TextEdit(Range(l, c - endof(word), l, c - endof(word) + endof(newtext)), newtext)]))
        else
            push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(tdpp.position, tdpp.position), newtext[endof(word) - endof(prefix) + 1:end]), []))
        end
    end

    completion_list = CompletionList(true, unique(CIs))

    response =  JSONRPC.Response(get(r.id), completion_list)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end

function searchlast(str, c)
    i0 = search(str, c, 1)
    if i0 == 0 
        return 0
    else
        while true
            i1 = search(str, c, i0 + 1)
            if i1 == 0
                return i0
            end
            i0 = i1
        end
    end
end
