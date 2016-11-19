function get_line(uri::AbstractString, line::Int, server::LanguageServerInstance)
    doc = server.documents[uri].data
    n = length(doc)
    i = cnt = 0
    while cnt<line && i<n
        i += 1
        if doc[i]==0x0a
            cnt += 1
        end
    end
    io = IOBuffer(doc)
    seek(io,i)
    return String(chomp(readuntil(io, '\n')))
end

function get_line(tdpp::TextDocumentPositionParams, server::LanguageServerInstance)
    return get_line(tdpp.textDocument.uri, tdpp.position.line , server)
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
    if str[1:16]=="No documentation"
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

## Position/Range to Vector{UInt8} position conversions ##

"""
    get_rangelocs(d::Array{UInt8}, range::Range)

Get the start and end `Char` position of a Range in the underlying
data of a `String`.
"""
function get_rangelocs(d::Array{UInt8}, range::Range)
    (s,e) = (range.start.line, range.stop.line)
    n = length(d)
    i = cnt = 0
    while cnt<s && i<n
        i+=1
        if d[i]==0x0a
            cnt += 1
        end
    end
    startline = i
    while cnt<e && i<n
        i+=1
        if d[i]==0x0a
            cnt += 1
        end
    end
    endline = i
    return startline, endline
end

"""
    get_pos(i0, linebreaks)

Get Position of Char at linear position `i0` given line boundaries 
at `linebreaks`.
"""
function get_pos(i0, linebreaks)
    nlb = length(linebreaks)-1
    for l in 1:nlb
        if linebreaks[l] < i0 ≤ linebreaks[l+1]
            return Position(l-1, i0-linebreaks[l]-1)
        end
    end
end

get_linebreaks(data::Vector{UInt8}) = [0; find(c->c==0x0a, data); length(data)+1]
get_linebreaks(doc::String) = get_linebreaks(doc.data) 


function should_file_be_linted(uri, server)
    uri_path = normpath(unescape(URI(uri).path))

    workspace_path = server.rootPath

    if is_windows()
        if uri_path[1]=='\\'
            uri_path = uri_path[2:end]
        end

        uri_path = lowercase(uri_path)
        workspace_path = lowercase(workspace_path)
end

    if server.rootPath==""
        return false
    else
        return startswith(uri_path, workspace_path)
    end
end


sprintrange(range::Range) = "($(range.start.line+1),$(range.start.character)):($(range.stop.line+1),$(range.stop.character+1))" 


function get_block(tdpp::TextDocumentPositionParams, server)
    for b in server.documents[tdpp.textDocument.uri].blocks
        if tdpp.position in b.range
            return b
        end
    end
    return 
end

function get_block(uri::AbstractString, str::AbstractString, server)
    for b in server.documents[uri].blocks
        if str==b.name
            return b
        end
    end
    return false
end

function get_type(sword::Vector, tdpp, server)
    t = get_type(sword[1],tdpp,server)
    for i = 2:length(sword)
        fn = get_fn(t, tdpp, server)
        if sword[i] in keys(fn)
            t = fn[sword[i]]
        else
            return ""
        end
    end
    return t
end

function get_type(word::AbstractString, tdpp::TextDocumentPositionParams, server)
    b = get_block(tdpp, server)
    if word in keys(b.localvar)
        t = string(b.localvar[word].t) 
    elseif word in (x->x.name).(server.documents[tdpp.textDocument.uri].blocks)
        t = get_block(tdpp.textDocument.uri, word, server).var.t
    elseif isdefined(Symbol(word)) 
        t = string(typeof(get_sym(word)))
    else
        t = "Any"
    end
    return t
end


"""
    get_fn(t::AbstractString, tdpp::TextDocumentPositionParams, server)

Returns the fieldnames of a type specified by `t`. Searches over types defined in the current document first then actually defined types.
"""
function get_fn(t::AbstractString, tdpp::TextDocumentPositionParams, server)
    if t in (b->b.name).(server.documents[tdpp.textDocument.uri].blocks)
        b = get_block(tdpp.textDocument.uri, t, server)
        fn = Dict(k => string(b.localvar[k].t) for k in keys(b.localvar))
    elseif isdefined(Symbol(t)) 
        sym = get_sym(t)
        if isa(sym, DataType)
            fnames = string.(fieldnames(sym))
            fn = Dict(fnames[i]=>string(sym.types[i]) for i = 1:length(fnames))
        else
            fn = Dict()
        end
    else
        fn = Dict()
    end
    return fn
end

