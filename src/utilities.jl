function get_line(uri::AbstractString, line::Integer, server::LanguageServerInstance)
    doc = server.documents[uri]
    return get_line(doc, line)
end

function get_line(tdpp::TextDocumentPositionParams, server::LanguageServerInstance)
    return get_line(tdpp.textDocument.uri, tdpp.position.line+1, server)
end

function get_word(tdpp::TextDocumentPositionParams, server::LanguageServerInstance, offset=0)
    line = IOBuffer(get_line(tdpp, server))
    word = Char[]
    e = s = 0
    c = ' '
    while position(line) < tdpp.position.character+offset
        e += 1
        c = read(line, Char)
        push!(word, c)
        if !(Base.is_id_char(c) || c=='.')
            word = Char[]
            s = e
        end
    end
    while !eof(line) && Base.is_id_char(c)
        e += 1
        c = read(line, Char)
        Base.is_id_char(c) && push!(word, c)
    end
    for i = 1:5 # Delete junk at front
        !isempty(word) && (word[1] in [' ','.','!'] || '0'≤word[1]≤'9') && deleteat!(word, 1)
    end
    isempty(word) && return ""
    return String(word)
end

function get_sym(str::AbstractString)
    name = split(str, '.')
    try
        x = getfield(Main, Symbol(name[1]))
        for i = 2:length(name)
            x = getfield(x, Symbol(name[i]))
        end
        return x
    catch
        return nothing
    end
end

function get_docs(x)
    str = string(Docs.doc(x))
    if str[1:min(16, length(str))]=="No documentation"
        s = last(search(str, "\n\n```\n"))+1
        e = first(search(str, "\n```",s))-1
        if isa(x, DataType) && x!=Any && x!=Function
            d = MarkedString.(split(chomp(sprint(dump, x)), '\n'))
        elseif isa(x, Function)
            d = split(str[s:e], '\n')
            s = last(search(str, "\n\n"))+1
            e = first(search(str, "\n\n",s))-1
            d = MarkedString.(map(dd->(dd = dd[1:first(search(dd, " in "))-1]),d))
            d[1] = MarkedString(str[s:e])
        elseif isa(x, Module)
            d = [split(str, '\n')[3]]
        else
            d = []
        end
    else
        d = split(str, "\n\n", limit = 2)
    end
    return d
end


function get_docs(tdpp::TextDocumentPositionParams, server::LanguageServerInstance)
    word = get_word(tdpp,server)
    if search(word,'.')==0
        if isdefined(Main, Symbol(word))
            return [string(Docs.doc(Docs.Binding(Main, Symbol(word))))]
        end
    end

    word in keys(server.DocStore) && (return server.DocStore[word])
    sym = get_sym(word)
    d=[""]
    if sym!=nothing
        d = get_docs(sym)
        # Only keep 100 records
        if length(server.DocStore)>100
            for k in take(keys(server.DocStore), 10)
                delete!(server.DocStore, k)
            end
        end
        server.DocStore[word] = d
    end
    return d
end

function uri2filepath(uri::AbstractString)
    uri_path = normpath(unescape(URI(uri).path))

    if is_windows()
        if uri_path[1]=='\\'
            uri_path = uri_path[2:end]
        end

        uri_path = lowercase(uri_path)
    end
    return uri_path
end

function should_file_be_linted(uri, server)
    !server.runlinter && return false

    uri_path = uri2filepath(uri)

    workspace_path = server.rootPath

    if is_windows()
        workspace_path = lowercase(workspace_path)
    end

    if server.rootPath==""
        return false
    else
        return startswith(uri_path, workspace_path)
    end
end


sprintrange(range::Range) = "($(range.start.line+1),$(range.start.character)):($(range.stop.line+1),$(range.stop.character+1))" 
