function get_line(tdpp::TextDocumentPositionParams, server::LanguageServerInstance)
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    return get_line(doc, tdpp.position.line + 1)
end

function get_word(tdpp::TextDocumentPositionParams, server::LanguageServerInstance, offset = 0)
    io = IOBuffer(get_line(tdpp, server))
    word = Char[]
    e = 0
    while !eof(io)
        c = read(io, Char)
        e += 1
        if (Base.is_id_start_char(c) || c == '@') || (c == '.' && e < (tdpp.position.character + offset))
            if isempty(word) && !(Base.is_id_start_char(c) || c == '@')
                continue
            end
            push!(word, c)
        else
            if e <= tdpp.position.character + offset
                empty!(word)
            else
                break
            end
        end
    end
    return String(word)
end


_isdotexpr(x) = false
_isdotexpr(x::BinarySyntaxOpCall) = CSTParser.is_dot(x.op)

unpack_dot(id, args = Symbol[]) = Symbol[]

function unpack_dot(id::Symbol, args = Symbol[])
    unshift!(args, id)
    return args
end

function unpack_dot(id::Expr, args = Symbol[])
    if id isa Expr && id.head == :. && id.args[2] isa QuoteNode
        if id.args[2].value isa Symbol && ((id.args[1] isa Expr && id.args[1].head == :.) || id.args[1] isa Symbol)
            unshift!(args, id.args[2].value)
            args = unpack_dot(id.args[1], args)
        else
            return Symbol[]
        end
    end
    return args
end

function unpack_dot(x::BinarySyntaxOpCall)
    args = Any[]
    val = x
    while _isdotexpr(val)
        if val.arg2 isa EXPR{Quotenode}
            unshift!(args, val.arg2.args[1])
        else
            unshift!(args, val.arg2)
        end
        val = val.arg1
    end
    unshift!(args, val)
    return args
end

function make_name(ns, id)
    io = IOBuffer()
    for x in ns
        print(io, x)
        print(io, ".")
    end
    print(io, id)
    String(take!(io))
end

function get_module(ids::Vector{Symbol}, M = Main)
    if isempty(ids)
        return M
    elseif isdefined(M, first(ids))
        M = getfield(M, shift!(ids))
        return get_module(ids, M)
    else
        return false
    end
end

function _isdefined(x::Expr)
    ids = unpack_dot(x)
    return isempty(ids) ? false : _isdefined(ids)
end

function _isdefined(ids::Vector{Symbol}, M = Main)
    if isempty(ids)
        return true
    elseif isdefined(M, first(ids))
        M = getfield(M, shift!(ids))
        return _isdefined(ids, M)
    else
        return false
    end
end

function _getfield(names::Vector{Symbol})
    val = Main
    for i = 1:length(names)
        !isdefined(val, names[i]) && return
        val = getfield(val, names[i])
    end
    return val
end


function uri2filepath(uri::AbstractString)
    uri_path = normpath(URIParser.unescape(URIParser.URI(uri).path))

    if is_windows()
        if uri_path[1] == '\\' || uri_path[1] == '/'
            uri_path = uri_path[2:end]
        end
    end
    return uri_path
end

function filepath2uri(file::String)
    if is_windows()
        file = normpath(file)
        file = replace(file, "\\", "/")
        file = URIParser.escape(file)
        file = replace(file, "%2F", "/")
        return string("file:///", file)
    else
        file = normpath(file)
        file = URIParser.escape(file)
        file = replace(file, "%2F", "/")
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


str_value(x) = ""
str_value(x::T) where T <: Union{IDENTIFIER,LITERAL} = x.val
str_value(x::OPERATOR) = string(Expr(x))

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

function toggle_file_lint(doc, server)
    if doc._runlinter
        doc._runlinter = false
        empty!(doc.diagnostics)
    else
        doc._runlinter = true
        # L = lint(doc, server)
        # doc.diagnostics = L.diagnostics
    end
    publish_diagnostics(doc, server)
end

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
    for (uri1,f) in server.documents
        for incl in f.code.state.includes
            if doc._uri == filepath2uri(incl.file)
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
        ismatch(r, uri._uri) && push!(out, doc)
    end
    return out
end
