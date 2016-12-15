function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    tdpp = r.params
    doc = server.documents[tdpp.textDocument.uri]
    line = get_line(tdpp, server)

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
    # Global completions
    comp = Base.REPLCompletions.completions(word,endof(word))[1]
    n = length(comp)
    comp = comp[1:min(length(comp),50)]

    # Local completions
    sword = split(word,".")
    offset = get_offset(doc, tdpp.position.line+1, tdpp.position.character+1)
    # ns = get_names(doc.blocks, offset)
    ns = get_names(tdpp.textDocument.uri, server, offset)
    if length(sword)==1
        for k in keys(ns)
            if length(string(k))>length(word) && word==string(k)[1:length(word)]
                push!(comp, string(k))
            end
        end
    else
        if Symbol(sword[1]) in keys(ns)
            t = get_type(Symbol.(sword[1:end-1]), ns, doc.blocks)
            fn = keys(get_fields(t, ns, doc.blocks))
            for f in fn
                if length(string(f))>length(last(sword)) && last(sword)==string(f)[1:length(last(sword))]
                    push!(comp, string(f))
                end
            end
        end
    end

    
    CIs = map(comp) do label
        l, c = tdpp.position.line, tdpp.position.character
        s = get_sym(label)
        
        if label[1]=='\\'
            d = Base.REPLCompletions.latex_symbols[label]
            newtext = Base.REPLCompletions.latex_symbols[label]
        else
            if s == nothing
                d = ""
            else
                d = get_docs(s)
                d = isa(d,Vector{MarkedString}) ? (x->x.value).(d) : d
                d = join(d[2:end],'\n')
                d = replace(d,'`',"")
            end
            newtext = prefix*label
        end

        kind = isa(s, String) ? 1 :
               isa(s, Function) ? 3 :
               isa(s, DataType) ? 7 :
               isa(s, Module) ? 9 :
               isa(s, Number) ? 12 :
               isa(s, Enum) ? 13 : 6

        if endof(newtext)>=endof(word)
            return CompletionItem(label, kind, d, TextEdit(Range(tdpp.position, tdpp.position), newtext[endof(word)+1:end]), [])
        else
            return CompletionItem(label, kind, d, TextEdit(Range(l, c-endof(word)+endof(newtext), l, c), ""),[TextEdit(Range(l, c-endof(word), l, c-endof(word)+endof(newtext)), newtext)])
        end
    end
    completion_list = CompletionList(50<n,CIs)

    response =  JSONRPC.Response(get(r.id), completion_list)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end
