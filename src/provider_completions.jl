function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    tdpp = r.params
    line = get_line(tdpp, server)
    
    word = IOBuffer()
    for c in reverse(line[1:chr2ind(line,tdpp.position.character)])
        if c=='\\'
            write(word, c)
            break
        end
        if !(Base.is_id_char(c) || c=='.' || c=='_' || c=='^')
            break
        end
        write(word, c)
    end
    
    str = reverse(takebuf_string(word))
    prefix = str[1:findlast(str,'.')]
    comp = Base.REPLCompletions.completions(str,endof(str))[1]
    n = length(comp)
    comp = comp[1:min(length(comp),25)]
    CIs = map(comp) do label
        l, c = tdpp.position.line, tdpp.position.character
        s = get_sym(label)
        
        
        if label[1]=='\\'
            d = Base.REPLCompletions.latex_symbols[label]
            newtext = Base.REPLCompletions.latex_symbols[label]
        else
            d = ""
            d = get_docs(s)
            d = isa(d,Vector{MarkedString}) ? (x->x.value).(d) : d
            d = join(d[2:end],'\n')
            d = replace(d,'`',"")
            newtext = prefix*label
        end

        kind = isa(s, String) ? 1 :
               isa(s, Function) ? 3 :
               isa(s, DataType) ? 7 :
               isa(s, Module) ? 9 :
               isa(s, Number) ? 12 :
               isa(s, Enum) ? 13 : 6

        if endof(newtext)>=endof(str)
            return CompletionItem(label, kind, d, TextEdit(Range(tdpp.position, tdpp.position), newtext[endof(str)+1:end]), [])
        else
            return CompletionItem(label, kind, d, TextEdit(Range(l, c-endof(str)+endof(newtext), l, c), ""),[TextEdit(Range(l, c-endof(str), l, c-endof(str)+endof(newtext)), newtext)])
        end
    end
    completion_list = CompletionList(25<n,CIs)

    response =  JSONRPC.Response(get(r.id), completion_list)
    send(response, server)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end
