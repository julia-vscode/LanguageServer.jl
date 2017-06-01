function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    line = get_line(tdpp, server)

    if isempty(line) || line == "\n" || tdpp.position.character == 0
        word = ""
    else
        word = let io = IOBuffer()
            if isempty(line)
                ""
            else
                for c in reverse(line[1:chr2ind(line, min(length(line), tdpp.position.character))])
                    if c == '\\' || c == '@'
                        write(io, c)
                        break
                    end
                    if !(Base.is_id_char(c) || c == '.' || c == '_')
                        break
                    end
                    write(io, c)
                end
                reverse(String(take!(io)))
            end
        end
    end

    entries = Tuple{Symbol,Int,String}[]
    prefix = word[1:findlast(word, '.')]
    if isempty(word) && isempty(prefix)
    elseif isempty(prefix) # Single word
        if startswith(word, "\\") # Latex completion
            for (k, v) in Base.REPLCompletions.latex_symbols
                if startswith(string(k), word)
                    push!(entries, (Base.REPLCompletions.latex_symbols[k], 1, k))
                    length(entries) > 200 && break
                end
            end
        else
            y, s, modules, current_namespace = get_scope(doc, offset, server)
            for m in vcat([:Base, :Core], unique(modules))
                if startswith(string(m), word)
                    push!(entries, (string(m), 9, "Module: $m"))
                    length(entries) > 200 && break
                end
                if isdefined(Main, m)
                    M = getfield(Main, m)
                    if M isa Module
                        for n in names(M)
                            if startswith(string(n), word)
                                x = getfield(M, n)
                                doc = string(Docs.doc(Docs.Binding(M, n)))
                                push!(entries, (string(n), CompletionItemKind(typeof(x)), doc))
                            end
                        end
                    end
                end
            end
            for (v, loc, uri) in s.symbols
                if startswith(string(v.id), word) 
                    push!(entries, (string(v.id), 6, ""))
                elseif startswith(string(v.id), string(current_namespace, ".", word))
                    push!(entries, (string(v.id)[length(string(current_namespace)) + 2:end], 6, ""))
                end
            end
        end
    else
        y, s, modules, current_namespace = get_scope(doc, offset, server)
        topmodname = Symbol(first(split(prefix, '.')))
        modname = unpack_dot(parse(strip(prefix, '.'), raise = false))
        vname = last(split(word, '.'))
        if topmodname in vcat([:Base, :Core], unique(modules)) && isdefined(Main, topmodname)
            M = get_module(modname)
            if M isa Module
                for n in names(M, true, true)
                    if !startswith(string(n), "#") && startswith(string(n), vname) && isdefined(M, n)
                        x = getfield(M, n)
                        doc = string(Docs.doc(Docs.Binding(M, n)))
                        push!(entries, (n, CompletionItemKind(typeof(x)), doc))
                        length(entries) > 200 && break
                    end
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
