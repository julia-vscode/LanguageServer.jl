function get_line(uri::AbstractString, line::Integer, server::LanguageServerInstance)
    doc = server.documents[uri]
    return get_line(doc, line)
end

function get_line(tdpp::TextDocumentPositionParams, server::LanguageServerInstance)
    return get_line(tdpp.textDocument.uri, tdpp.position.line+1, server)
end

function get_word(tdpp::TextDocumentPositionParams, server::LanguageServerInstance, offset=0)
    text = get_line(tdpp, server)
    word = Char[]
    for e = 1:length(text)
        c = text[chr2ind(text, e)]
        if Lexer.is_identifier_char(c) || (c=='.' && e<(tdpp.position.character+offset))
            if isempty(word) && !Lexer.is_identifier_start_char(c)
                continue
            end
            push!(word, c)
        else
            if e<=tdpp.position.character+offset
                empty!(word)
            else
                break
            end
        end
    end
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

function get_cache_entry(word, server, modules=[])
    allmod = vcat([:Base, :Core], modules)
    entry = (:EMPTY, "", [])
    if search(word, ".")!=0:-1
        sword = split(word, ".")
        modname = parse(join(sword[1:end-1], "."))
        if modname in allmod && modname in keys(server.cache) && Symbol(last(sword)) in keys(server.cache[modname])
            entry = server.cache[modname][Symbol(last(sword))]
        end
    else
        for m in allmod
            if Symbol(word) in server.cache[m][:EXPORTEDNAMES]
                entry = server.cache[m][Symbol(word)]
            end
        end
    end

    if isa(entry, Dict)
        entry = (parse(word), "Module: $word", SignatureHelp(SignatureInformation[], 0, 0), Location[]) 
    end
    return entry
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

CompletionItemKind(t) = t in [:String, :AbstractString] ? 1 : 
                                t == :Function ? 3 : 
                                t == :DataType ? 7 :  
                                t == :Module ? 9 : 6 

SymbolKind(t) = t in [:String, :AbstractString] ? 15 : 
                        t == :Function ? 12 : 
                        t == :DataType ? 5 :  
                        t == :Module ? 2 :
                        t == :Bool ? 17 : 13  