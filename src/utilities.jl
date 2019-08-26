function uri2filepath(uri::AbstractString)
    uri_path = normpath(URIParser.unescape(URIParser.URI(uri).path))

    if Sys.iswindows()
        if uri_path[1] == '\\' || uri_path[1] == '/'
            uri_path = uri_path[2:end]
        end
    end
    return uri_path
end

function filepath2uri(file::String)
    if Sys.iswindows()
        file = normpath(file)
        file = replace(file, "\\" => "/")
        file = URIParser.escape(file)
        file = replace(file, "%2F" => "/")
        return string("file:///", file)
    else
        file = normpath(file)
        file = URIParser.escape(file)
        file = replace(file, "%2F" => "/")
        return string("file://", file)
    end
end

function joinuriwithpath(uri::AbstractString, path::AbstractString)
    left_file_path = uri2filepath(uri)
    combined_path = joinpath(left_file_path, path)
    return filepath2uri(combined_path)
end

function should_file_be_linted(uri, server)
    !server.runlinter && return false

    uri_path = uri2filepath(uri)

    if length(server.workspaceFolders)==0
        return false
    else
        return any(i->startswith(uri_path, i), server.workspaceFolders)
    end
end

CompletionItemKind(t) = t in [:String, :AbstractString] ? 1 : 
                                t == :Function ? 3 : 
                                t == :DataType ? 7 :  
                                t == :Module ? 9 : 6 

SymbolKind(t) = t in [:String, :AbstractString] ? 15 : 
                        t == :Function ? 12 : 
                        t == :DataType ? 5 :  
                        t == :Module ? 2 :
                        t == :Bool ? 17 : 13  




# Find location of default datatype constructor
const DefaultTypeConstructorLoc= let def = first(methods(Int))
    Base.find_source_file(string(def.file)), def.line
end

function is_ignored(uri, server)
    fpath = uri2filepath(uri)
    fpath in server.ignorelist && return true
    for ig in server.ignorelist
        if !endswith(ig, ".jl")        
            if startswith(fpath, ig)
                return true
            end
        end
    end
    return false
end

is_ignored(uri::URI2, server) = is_ignored(uri._uri, server)

# function toggle_file_lint(doc, server)
#     if doc._runlinter
#         doc._runlinter = false
#         empty!(doc.diagnostics)
#     else
#         doc._runlinter = true
#         # L = lint(doc, server)
#         # doc.diagnostics = L.diagnostics
#     end
#     publish_diagnostics(doc, server)
# end

function remove_workspace_files(root, server)
    for (uri, doc) in server.documents
        fpath = uri2filepath(uri._uri)
        doc._open_in_editor && continue
        if startswith(fpath, fpath)
            for folder in server.workspaceFolders
                if startswith(fpath, folder)
                    continue
                end
                delete!(server.documents, uri)
            end
        end
    end
end

function find_root(doc::Document, server)
    path = uri2filepath(doc._uri)
    for (uri1,f) in server.documents
        for incl in f.code.state.includes
            if path == incl.file
                if doc.code.index != incl.index
                    doc.code.index = incl.index
                    doc.code.nb = incl.pos
                end

                return find_root(f, server)
            end
        end
    end
    return doc
end



function Base.getindex(server::LanguageServerInstance, r::Regex)
    out = []
    for (uri,doc) in server.documents
        occursin(r, uri._uri) && push!(out, doc)
    end
    return out
end

function _offset_unitrange(r::UnitRange{Int}, first = true)
    return r.start-1:r.stop
end

function get_toks(doc, offset)
    ts = CSTParser.Tokenize.tokenize(doc._content)
    ppt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0,0), (0,0), 1, 0, CSTParser.Tokens.NO_ERR, false)
    pt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0,0), (0,0), 1, 0, CSTParser.Tokens.NO_ERR, false)
    t = CSTParser.Tokenize.Lexers.next_token(ts)
    if offset > length(doc._content)
        offset = sizeof(doc._content) - 1 
    end

    while t.kind != CSTParser.Tokenize.Tokens.ENDMARKER
        if t.startbyte < offset <= t.endbyte + 1
            break
        end
        ppt = pt
        pt = t
        t = CSTParser.Tokenize.Lexers.next_token(ts)
    end
    return ppt, pt, t
end

function isvalidjlfile(path)
    isfile(path) && 
    endswith(path, ".jl") && 
    validchars(path)
end

function validchars(path)
    io = open(path)
    while !eof(io)
        c = read(io, Char)
        Base.ismalformed(c) && return false
    end
    close(io)
    return true
end

function goto_loc(x::EXPR, offset::Int, pos = 0)
    if x.args isa Vector{EXPR}
        for a in x.args
            if pos <= offset < pos + a.fullspan
                return goto_loc(a, offset, pos)
            else
                pos += a.fullspan
            end
        end
    end
    if offset == x.fullspan && !(x.parent isa EXPR)
        return last(x.args)
    end
    return x
end

function get_expr(x, offset, pos = 0)
    if pos > offset
        return nothing
    end
    if x.args !== nothing
        for a in x.args
            if pos < offset <= (pos + a.fullspan)
                return get_expr(a, offset, pos)
            end
            pos += a.fullspan
        end
    elseif (pos < offset <= (pos + x.fullspan)) || pos == 0
        return x
    end
end

function get_identifier(x, offset, pos = 0)
    if pos > offset
        return nothing
    end
    if x.args !== nothing
        for a in x.args
            if pos <= offset <= (pos + a.span)
                return get_identifier(a, offset, pos)
            end
            pos += a.fullspan
        end
    elseif x.typ === CSTParser.IDENTIFIER && (pos <= offset <= (pos + x.span)) || pos == 0
        return x
    end
end

@static if Sys.iswindows() && VERSION < v"1.3"
    function _splitdir_nodrive(a::String, b::String)
        m = match(r"^(.*?)([/\\]+)([^/\\]*)$",b)
        m === nothing && return (a,b)
        a = string(a, isempty(m.captures[1]) ? m.captures[2][1] : m.captures[1])
        a, String(m.captures[3])
    end
    
    function _dirname(path::String)
        m = match(r"^([^\\]+:|\\\\[^\\]+\\[^\\]+|\\\\\?\\UNC\\[^\\]+\\[^\\]+|\\\\\?\\[^\\]+:|)(.*)$"s, path)
        a, b = String(m.captures[1]), String(m.captures[2])
        _splitdir_nodrive(a,b)[1]
    end
else
    _dirname = dirname
end
