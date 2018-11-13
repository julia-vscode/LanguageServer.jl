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


str_value(x) = ""
str_value(x::T) where T <: Union{IDENTIFIER,LITERAL} = x.val
str_value(x::OPERATOR) = string(Expr(x))


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
    CSTParser.Tokens.EMPTY_TOKEN(CSTParser.Tokens.RawToken)
    CSTParser.Tokens.RawToken()
    ppt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0,0), (0,0), 1, 0, CSTParser.Tokens.NO_ERR, false)
    pt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0,0), (0,0), 1, 0, CSTParser.Tokens.NO_ERR, false)
    t = CSTParser.Tokenize.Lexers.next_token(ts)
    if offset >= length(doc._content)
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

function find_ref(doc, offset)
    for rref in doc.code.rref
        if rref.r.loc.offset == offset
            return rref 
        # elseif rref.r.loc.offset > offset
        #     break
        end
    end
    return nothing
end

function get_locations(rref::StaticLint.ResolvedRef, bindings, locations, server)
    if rref.b isa StaticLint.ImportBinding
        if rref.b.val isa StaticLint.SymbolServer.FunctionStore || rref.b.val isa StaticLint.SymbolServer.structStore
            for l in rref.b.val.methods
                push!(locations, Location(filepath2uri(l.file), l.line))
            end
        end
    elseif rref.b.t in (server.packages["Core"].vals["Function"], server.packages["Core"].vals["DataType"])
        for b in StaticLint.get_methods(rref, bindings)
            get_locations(b, bindings, locations, server)
        end
    else
        get_locations(rref.b, bindings, locations, server)
    end
end

function get_locations(b::StaticLint.Binding, bindings, locations, server)
    if b.val isa CSTParser.AbstractEXPR
        uri2 = filepath2uri(b.loc.file)
        if !(URI2(uri2) in keys(server.documents))
            uri3 = string("untitled:",b.loc.file)
            if URI2(uri3) in keys(server.documents)
                uri2 = uri3
            else 
                return
            end
        end
        doc2 = server.documents[URI2(uri2)]
        push!(locations, Location(uri2, Range(doc2, b.loc.offset .+ (0:b.val.span))))
    elseif b.val isa Function
        for m in methods(b.val)
            file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
            if (file, m.line) == DefaultTypeConstructorLoc || file == nothing
                continue
            end
            push!(locations, Location(filepath2uri(file), Range(m.line - 1, 0, m.line, 0)))
        end
    end
end
