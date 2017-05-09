function get_line(uri::AbstractString, line::Integer, server::LanguageServerInstance)
    doc = server.documents[uri]
    return get_line(doc, line)
end

function get_line(tdpp::TextDocumentPositionParams, server::LanguageServerInstance)
    return get_line(tdpp.textDocument.uri, tdpp.position.line + 1, server)
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


function unpack_dot(id, args = Symbol[])
    if id isa Expr && id.head == :. && id.args[2] isa QuoteNode
        if id.args[2].value isa Symbol
            unshift!(args, id.args[2].value)
            unpack_dot(id.args[1], args)
        else
            return Symbol[]
        end
    elseif id isa Symbol
        unshift!(args, id)
    else
        return Symbol[]
    end
    return args
end


repack_dot(args::Symbol) = args
function repack_dot(args::Vector)
    if length(args) == 1
        return first(args)
    else
        return repack_dot([Expr(:., first(args), QuoteNode(args[2])); args[3:end]])
    end
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


function get_cache_entry(id, server, modules = [])
    ids = unpack_dot(id)
    if !isempty(ids)
        for m in vcat([:Base, :Core], modules)
            if isdefined(Main, m)
                M = getfield(Main, m)
                if first(ids) == m
                    if length(ids) == 1
                        return get_cache_entry(ids, Main)
                    else
                        shift!(ids)
                        return get_cache_entry(ids, M)
                    end
                elseif first(ids) in names(M)
                    return get_cache_entry(ids, M)
                end
            end
        end
    end
    return nothing
end

function get_cache_entry(ids::Vector{Symbol}, M::Module)
    if isempty(ids)
        return nothing
    end
    if first(ids) in names(M, true, true)
        x = getfield(M, first(ids))
        if length(ids) == 1
            return x
        elseif x isa Module
            shift!(ids)
            return get_cache_entry(ids, x)
        else
            return nothing
        end
    end

    return nothing
end

function uri2filepath(uri::AbstractString)
    uri_path = normpath(unescape(URI(uri).path))

    if is_windows()
        if uri_path[1] == '\\'
            uri_path = uri_path[2:end]
        end

        uri_path = lowercase(uri_path)
    end
    return uri_path
end

function filepath2uri(file::String)
    string("file://", file)
end

function should_file_be_linted(uri, server)
    !server.runlinter && return false

    uri_path = uri2filepath(uri)

    workspace_path = server.rootPath

    if is_windows()
        workspace_path = lowercase(workspace_path)
    end

    if server.rootPath == ""
        return false
    else
        return startswith(uri_path, workspace_path)
    end
end


sprintrange(range::Range) = "($(range.start.line+1),$(range.start.character)):($(range.stop.line+1),$(range.stop.character+1))" 

CompletionItemKind(t) = t in [:String, :AbstractString] ? 1 : 
                                t == :Function ? 3 : 
                                t == :DataType ? 7 :  
                                t == :Module ? 9 : 6 

SymbolKind(t) = t in [:String, :AbstractString] ? 15 : 
                        t == :Function ? 12 : 
                        t == :DataType ? 5 :  
                        t == :Module ? 2 :
                        t == :Bool ? 17 : 13  

updatecache(absentmodule::Symbol, server) = updatecache([absentmodule], server)

function updatecache(absentmodules::Vector{Symbol}, server)
    for m in absentmodules
        @eval try import $m end
    end
end
