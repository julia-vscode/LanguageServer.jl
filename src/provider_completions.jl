function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character)
    ns = get_names(tdpp.textDocument.uri, offset, server)
    line = get_line(tdpp, server)
    

    if isempty(line) || line=="\n" || tdpp.position.character==0
        word = ""
    else
        word = let io = IOBuffer()
            if isempty(line)
                ""
            else
                for c in reverse(line[1:chr2ind(line,min(length(line), tdpp.position.character))])
                    if c=='\\'
                        write(io, c)
                        break
                    end
                    if !(Base.is_id_char(c) || c=='.' || c=='_' || c=='^')
                        break
                    end
                    write(io, c)
                end
                reverse(takebuf_string(io))
            end
        end
    end

    prefix = word[1:findlast(word,'.')]

    entries = Tuple{Symbol,Int,String}[]
    if isempty(word) && isempty(prefix)
    elseif isempty(prefix) # Single word
        if startswith(word, "\\") # Latex completion
            for (k,v) in Base.REPLCompletions.latex_symbols
                if startswith(string(k), word)
                    push!(entries, (Base.REPLCompletions.latex_symbols[k], 1, k))
                    length(entries)>200 && break
                end
            end
        else
            for m in vcat([:Base, :Core], ns.modules)
                if startswith(string(m), word)
                    push!(entries, (string(m), 9, "Module: $m"))
                    length(entries)>200 && break
                end
                for k in server.cache[m][:EXPORTEDNAMES]
                    if startswith(string(k), word)
                        if isa(server.cache[m][k], Dict)
                            push!(entries, (string(k), 9, "Module: $k"))
                            length(entries)>200 && break
                        else
                            push!(entries, (string(k), CompletionItemKind(server.cache[m][k][1]), server.cache[m][k][2]))
                            length(entries)>200 && break
                        end
                    end
                end
            end
            for k in keys(ns.list)
                if length(string(k))>length(word) && word==string(k)[1:length(word)]
                    push!(entries, (string(k), 6, ""))
                end
            end
        end
    else
        modname = parse(strip(prefix, '.'))
        topmodname = Symbol(first(split(prefix, '.')))
        vname = last(split(word, '.'))
        if topmodname in vcat([:Base, :Core], ns.modules)
            for (k, v) in server.cache[modname]
                k==:EXPORTEDNAMES && continue
                if startswith(string(k), vname)
                    n = string(modname, ".", k)
                    if isa(server.cache[modname][k], Dict)
                        push!(entries, (n, 9, "Module: $n"))
                        length(entries)>200 && break
                    else
                        push!(entries, (n, CompletionItemKind(v[1]), v[2]))
                        length(entries)>200 && break
                    end
                end
            end
        end
        sword = split(word,".")
        if Symbol(sword[1]) in keys(ns.list)
            t = get_type(Symbol.(sword[1:end-1]), ns)
            fn = keys(get_fields(t, ns))
            for f in fn
                if length(string(f))>length(last(sword)) && last(sword)==string(f)[1:length(last(sword))]
                    push!(entries, (string(f), 6, ""))
                    length(entries)>200 && break
                end
            end
        end
    end

    l, c = tdpp.position.line, tdpp.position.character
    CIs = []
    for (comp, k, documentation) in entries
        newtext = string(comp)
        if startswith(documentation, "\\")
            label  = strip(documentation, '\\')
            documentation = newtext
            length(newtext)>1 && (newtext=newtext[1:1])
        else
            label  = last(split(newtext, "."))
            documentation = replace(documentation, r"(`|\*\*)", "")
            documentation = replace(documentation, "\n\n", "\n")
        end

        if endof(newtext)>=endof(word)
            push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(tdpp.position, tdpp.position), newtext[endof(word)+1:end]), []))
        else
            push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(l, c-endof(word)+endof(newtext), l, c), ""),[TextEdit(Range(l, c-endof(word), l, c-endof(word)+endof(newtext)), newtext)]))
        end
    end

    completion_list = CompletionList(true,CIs)

    response =  JSONRPC.Response(get(r.id), completion_list)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end

