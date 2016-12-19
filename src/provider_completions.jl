function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character)
    ns = get_names(tdpp.textDocument.uri, offset, server)
    line = get_line(tdpp, server)
    modules = ns[:loaded_modules]

    if isempty(line) || line=="\n"
        word = ""
    else
        word = let io = IOBuffer()
            if isempty(line)
                ""
            else
                for c in reverse(line[1:chr2ind(line,tdpp.position.character)])
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
    if isempty(prefix) # Single word
        if startswith(word, "\\") # Latex completion
            for (k,v) in Base.REPLCompletions.latex_symbols
                if startswith(string(k), word)
                    push!(entries, (Base.REPLCompletions.latex_symbols[k], 1, k))
                end
            end
        else
            for m in vcat([:Base, :Core], modules)
                if startswith(string(m), word)
                    push!(entries, (string(m), 9, "Module: $m"))
                end
                for k in server.cache[m][:EXPORTEDNAMES]
                    if startswith(string(k), word)
                        if isa(server.cache[m][k], Dict)
                            push!(entries, (string(k), 9, "Module: $k"))
                        else
                            push!(entries, (string(k), kind(server.cache[m][k][1]), server.cache[m][k][2]))
                        end
                    end
                end
            end
            for k in keys(ns)
                if length(string(k))>length(word) && word==string(k)[1:length(word)]
                    push!(entries, (string(k), 6, ""))
                end
            end
        end
    else
        modname = parse(strip(prefix, '.'))
        topmodname = Symbol(first(split(prefix, '.')))
        vname = last(split(word, '.'))
        if topmodname in vcat([:Base, :Core], modules)
            for (k, v) in server.cache[modname]
                if startswith(string(k), vname)
                    n = string(modname, ".", k)
                    
                    if isa(server.cache[modname][k], Dict)
                        push!(entries, (n, 9, "Module: $n"))
                    else
                        push!(entries, (n, kind(v[1]), v[2]))
                    end
                end
            end
        end
        sword = split(word,".")
        if Symbol(sword[1]) in keys(ns)
            t = get_type(Symbol.(sword[1:end-1]), ns, doc.blocks)
            fn = keys(get_fields(t, ns, doc.blocks))
            for f in fn
                if length(string(f))>length(last(sword)) && last(sword)==string(f)[1:length(last(sword))]
                    push!(entries, (string(f), 6, ""))
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
            label  = newtext
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


kind(s::Symbol) = s==:String ? 1 :
       s==:Function ? 3 :
       s==:DataType ? 7 :
       s==:Module ? 9 :
       s==:Number ? 12 :
       s==:Enum ? 13 : 6