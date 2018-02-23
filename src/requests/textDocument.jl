function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.isrunning = true
    uri = r.params.textDocument.uri
    server.documents[URI2(uri)] = Document(uri, r.params.textDocument.text, false)
    doc = server.documents[URI2(uri)]
    if any(i->startswith(uri, filepath2uri(i)), server.workspaceFolders)
        doc._workspace_file = true
    end
    set_open_in_editor(doc, true)
    if is_ignored(uri, server)
        doc._runlinter = false
    end
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    !haskey(server.documents, URI2(uri)) && return
    doc = server.documents[URI2(uri)]
    empty!(doc.diagnostics)
    publish_diagnostics(doc, server)
    if !is_workspace_file(doc)
        delete!(server.documents, URI2(uri))
    else
        set_open_in_editor(doc, false)
    end
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[URI2(r.params.textDocument.uri)]
    doc._version = r.params.textDocument.version
    isempty(r.params.contentChanges) && return
    # dirty = get_offset(doc, last(r.params.contentChanges).range.start.line + 1, last(r.params.contentChanges).range.start.character + 1):get_offset(doc, first(r.params.contentChanges).range.stop.line + 1, first(r.params.contentChanges).range.stop.character + 1)
    # for c in r.params.contentChanges
    #     update(doc, c.range.start.line + 1, c.range.start.character + 1, c.rangeLength, c.text)
    # end
    doc._content = last(r.params.contentChanges).text
    doc._line_offsets = Nullable{Vector{Int}}()
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    return DidSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    uri = r.params.textDocument.uri
    doc = server.documents[URI2(uri)]
    parse_all(doc, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSave")}}, params)
    return WillSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSave")},WillSaveTextDocumentParams}, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/willSaveWaitUntil")}}, params)
    return WillSaveTextDocumentParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/willSaveWaitUntil")},WillSaveTextDocumentParams}, server)
    response = JSONRPC.Response(get(r.id), TextEdit[])
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/codeAction")}}, params)
    return CodeActionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/codeAction")},CodeActionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    commands = Command[]
    range = r.params.range
    range_loc = get_offset(doc, range.start.line + 1, range.start.character):get_offset(doc, range.stop.line + 1, range.stop.character)
    
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
    action_type = Any
    tdeall = TextDocumentEdit(VersionedTextDocumentIdentifier(doc._uri, doc._version), [])
    for d in doc.diagnostics
        if first(d.loc) <= first(range_loc) <= last(range_loc) <= last(d.loc) && typeof(d).parameters[1] isa LintCodes && !isempty(d.actions) 
            action_type = typeof(d).parameters[1]
            for a in d.actions
                start_l, start_c = get_position_at(doc, first(a.range))
                end_l, end_c = get_position_at(doc, last(a.range))
                push!(tde.edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), a.text))
            end
        end
    end
    file_actions = []
    for d in doc.diagnostics
        if typeof(d).parameters[1] == action_type && !isempty(d.actions) 
            for a in d.actions
                push!(file_actions, a)
                
            end
        end
    end
    sort!(file_actions, lt = (a, b) -> last(b.range) < first(a.range))
    for a in file_actions
        start_l, start_c = get_position_at(doc, first(a.range))
        end_l, end_c = get_position_at(doc, last(a.range))
        push!(tdeall.edits, TextEdit(Range(start_l - 1, start_c, end_l - 1, end_c), a.text))
    end

    if !isempty(tde.edits)
        push!(commands, Command("Fix deprecation", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tde])]))
    end
    if !isempty(tdeall.edits)
        push!(commands, Command("Fix all similar deprecations in file", "language-julia.applytextedit", [WorkspaceEdit(nothing, [tdeall])]))
    end
    response = JSONRPC.Response(get(r.id), commands)
    send(response, server)
end

function get_partial(str, l, c)
    ts = CSTParser.tokenize(str)
    lt = CSTParser.Tokenize.Tokens.Token()
    t = CSTParser.Tokenize.Lexers.next_token(ts)
    while !(l ≤ t.endpos[1]  && c ≤ t.endpos[2]) && t.kind != CSTParser.Tokenize.Tokens.ENDMARKER
        lt = t
        t = CSTParser.Tokenize.Lexers.next_token(ts)
    end
    if t.kind == CSTParser.Tokenize.Tokens.IDENTIFIER || CSTParser.Tokenize.Tokens.iskeyword(t.kind)
        val = CSTParser.Tokenize.Tokens.untokenize(t)
        pos = t.endpos[2] - c
        return val[1:end - pos], t.kind == CSTParser.Tokenize.Tokens.BACKSLASH
    else
        return "", false
    end
end

# function get_partial(str, offset)
#     ts = CSTParser.tokenize(str)
#     t = CSTParser.Tokenize.Lexers.next_token(ts)
#     while offset >= t.endbyte + 1 && t.kind != Tokens.ENDMARKER
#         t = CSTParser.Tokenize.Lexers.next_token(ts)
#     end
#     info("tok", t.kind, "  ", t.endbyte, "  ", offset)
#     if t.kind == CSTParser.Tokenize.Tokens.IDENTIFIER || CSTParser.Tokenize.Tokens.iskeyword(t.kind)
#         val = CSTParser.Tokenize.Tokens.untokenize(t)
#         pos = offset - t.startbyte
#         return val[1:pos], pos
#     else
#         return "", 0
#     end
# end

# function get_offset1(str, l, c)
#     offset, l1, c1 = 0, 0, 0
#     io = IOBuffer(str)
#     while !(l1 == l && c1 == c)
#         ch = read(io, Char)
#         offset+=1
#         if ch == '\n'
#             l1 += 1
#             c1 = 0
#         else
#             c1 += 1
#         end
#     end
    
#     return offset, position(io)
# end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/completion")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/completion")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    doc = server.documents[URI2(r.params.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    td = server.documents[URI2(last(findtopfile(tdpp.textDocument.uri, server)[1]))]
    S = StaticLint.trav(td, server, StaticLint.Location(uri2filepath(tdpp.textDocument.uri), offset))

    stack = get_stack(doc.code.ast, offset)
    cs = get_scope(S.current_scope, offset)
    
    l, c = tdpp.position.line, tdpp.position.character
    partial, islatex = get_partial(doc._content, l, c)
    
    entries = Tuple{Symbol,Int,String}[]
    CIs = CompletionItem[]
    
    if islatex
        # push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(l, c - endof(partial) + endof(newtext), l, c), ""), [TextEdit(Range(l, c - endof(partial), l, c - endof(partial) + endof(newtext)), newtext)]))
    else
        # keywords
        if partial in ("end", "else", "elseif", "catch", "finally")
            push!(entries, (partial, 6, partial))
        end

        # declared/imported names
        for b in get_names(cs)
            if b != "using" && startswith(b, partial)
                push!(CIs, CompletionItem(b, 6, b, TextEdit(Range(tdpp.position, tdpp.position), b[length(partial) + 1:end]), []))
            end
        end
        # using'ed names
        tops = cs
        while tops.parent !=nothing && !haskey(tops.names, "using")
            tops = tops.parent
        end
        if haskey(tops.names, "using")
            for n in tops.names["using"]
                for b in StaticLint.SymbolServer.server[n].exported
                    if startswith(string(b), partial)
                        push!(CIs, CompletionItem(b, 6, b, TextEdit(Range(tdpp.position, tdpp.position), b[length(partial) + 1:end]), []))
                    end
                end
            end
        end
    end
        
    # for (comp, k, documentation) in entries
    #     newtext = string(comp)
    #     if startswith(documentation, "\\")
    #         label  = strip(documentation, '\\')
    #         documentation = newtext
    #         length(newtext) > 1 && (newtext = newtext[1:1])
    #     elseif k == 17 # file completion
    #         label = comp
    #         documentation = ""
    #     else
    #         label  = last(split(newtext, "."))
    #         documentation = replace(documentation, r"(`|\*\*)", "")
    #         documentation = replace(documentation, "\n\n", "\n")
    #     end

    #     if k == 1
    #         push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(l, c - endof(partial) + endof(newtext), l, c), ""), [TextEdit(Range(l, c - endof(partial), l, c - endof(partial) + endof(newtext)), newtext)]))
    #     else
    #         push!(CIs, CompletionItem(label, k, documentation, TextEdit(Range(tdpp.position, tdpp.position), newtext[length(partial) + 1:end]), []))
    #     end
    # end

    response =  JSONRPC.Response(get(r.id), CompletionList(true, unique(CIs)))
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    doc = server.documents[URI2(r.params.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    td = server.documents[URI2(last(findtopfile(tdpp.textDocument.uri, server)[1]))]
    
    S = StaticLint.trav(td, server, StaticLint.Location(uri2filepath(tdpp.textDocument.uri), offset))
    stack = get_stack(doc.code.ast, offset)
    
    locations = Location[]

    path = uri2filepath(tdpp.textDocument.uri)
    ref = find_ref(S, path, offset)
    if ref isa StaticLint.Reference && ref.b isa StaticLint.Binding
        if ref.b.val isa CSTParser.AbstractEXPR # get definitions for user defined code
            b = ref.b
            uri2 = filepath2uri(b.loc.path)
            doc2 = server.documents[URI2(uri2)]
            push!(locations, Location(uri2, Range(doc2, first(b.loc.offset) - 1:last(b.loc.offset))))
            while b.t == :Function && b.overwrites isa StaticLint.Binding && b.overwrites.t == :Function
                b = b.overwrites
                uri2 = filepath2uri(b.loc.path)
                doc2 = server.documents[URI2(uri2)]
                push!(locations, Location(uri2, Range(doc2, first(b.loc.offset) - 1:last(b.loc.offset))))
            end
        else # definitions for imported methods
            for m in methods(ref.b.val)
                file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
                if (file, m.line) == DefaultTypeConstructorLoc || file == nothing
                    continue
                end
                push!(locations, Location(filepath2uri(file), Range(m.line - 1, 0, m.line, 0)))
            end
        end
    end
    
    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/formatting")}}, params)
    return DocumentFormattingParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/formatting")},DocumentFormattingParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    newcontent = DocumentFormat.format(doc._content)
    end_l, end_c = get_position_at(doc, sizeof(doc._content))
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l - 1, end_c), newcontent)]

    response = JSONRPC.Response(get(r.id), lsedits)
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[URI2(uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character + 1)
    td = server.documents[URI2(last(findtopfile(uri, server)[1]))]

    S = StaticLint.trav(td, server, StaticLint.Location(uri2filepath(r.params.textDocument.uri), offset))

    stack = get_stack(doc.code.ast, offset)
    cs = get_scope(S.current_scope, offset)
    documentation = Any[]
    if isempty(stack)
    elseif last(stack) isa IDENTIFIER
        ref = find_ref(S, uri2filepath(uri), offset)
        if ref isa StaticLint.Reference && !(ref.b isa StaticLint.MissingBinding) # found solid reference
            if ref.b.val isa CSTParser.AbstractEXPR
                push!(documentation, string(ref.b.t))
            else
                push!(documentation, string(Docs.doc(ref.b.val)))
            end
        end
    elseif last(stack) isa LITERAL
        push!(documentation, MarkedString(string(Expr(last(stack)), "::", CSTParser.infer_t(last(stack)))))
    elseif last(stack) isa KEYWORD
        if last(stack).kind == Tokens.END && length(stack) > 1
            expr_type = Expr(stack[end-1].args[1])
            push!(documentation, MarkedString("Closes `$expr_type` expression"))
        else
            push!(documentation, MarkedString(string(Docs.docm(Expr(last(stack))))))
        end
    elseif CSTParser.is_rparen(last(stack)) && length(stack) > 1
        last_ex = stack[end-1]
        if last_ex isa EXPR{Call}
            push!(documentation, MarkedString("Closes `$(Expr(last_ex.args[1]))` call"))
        elseif last_ex isa EXPR{CSTParser.TupleH}
            push!(documentation, MarkedString("Closes a tuple"))
        end
    elseif !(last(stack) isa PUNCTUATION)
        push!(documentation, string(Expr(last(stack))))
    end
    if server.debug_mode
        push!(documentation, string(keys(cs.names)))
        while cs.parent !=nothing
            cs = cs.parent
            push!(documentation, string(keys(cs.names)))
        end
    end
   

    response = JSONRPC.Response(get(r.id), Hover(unique(documentation)))
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentLink")}}, params)
    return DocumentLinkParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentLink")},DocumentLinkParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]
    links = Tuple{String,UnitRange{Int}}[]
    # get_links(doc.code.ast, 0, uri, server, links)
    doclinks = DocumentLink[]
    for (uri2, loc) in links
        rng = Range(Position(get_position_at(doc, first(loc))..., one_based = true), Position(get_position_at(doc, last(loc))..., one_based = true))
        push!(doclinks, DocumentLink(rng, uri2))
    end

    response = JSONRPC.Response(get(r.id), links) 
    send(response, server) 
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params)
    return ReferenceParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    tdpp = r.params
    uri = tdpp.textDocument.uri
    doc = server.documents[URI2(tdpp.textDocument.uri)]
    offset = get_offset(doc, tdpp.position.line + 1, tdpp.position.character)
    td = server.documents[URI2(last(findtopfile(uri, server)[1]))]
    S = StaticLint.trav(td, server)

    locations = similar_refs(uri2filepath(uri), offset, S, server)

    response = JSONRPC.Response(get(r.id), locations)
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/rename")}}, params)
    return RenameParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/rename")},RenameParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    rp = r.params
    uri = rp.textDocument.uri
    doc = server.documents[URI2(uri)]
    offset = get_offset(doc, rp.position.line + 1, rp.position.character)
    
    td = server.documents[URI2(last(findtopfile(uri, server)[1]))]
    S = StaticLint.trav(td, server)

    locations = similar_refs(uri2filepath(uri), offset, S, server)

    tdes = Dict{String,TextDocumentEdit}()
    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, rp.newName))
        else
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, server.documents[URI2(loc.uri)]._version), [TextEdit(loc.range, rp.newName)])
        end
    end

    we = WorkspaceEdit(nothing, collect(values(tdes)))
    response = JSONRPC.Response(get(r.id), we)
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    y,s = scope(r.params, server)
    if CSTParser.is_rparen(y)
        return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    elseif length(s.stack) > 0 && last(s.stack) isa EXPR{Call}
        fcall = s.stack[end]
        fname = CSTParser.get_name(last(s.stack))
        x = get_cache_entry(fname, server, s)
    elseif length(s.stack) > 1 && CSTParser.is_comma(s.stack[end]) && s.stack[end-1] isa EXPR{Call}
        fcall = s.stack[end-1]
        fname = CSTParser.get_name(fcall)
        x = get_cache_entry(fname, server, s)
    else
        return send(JSONRPC.Response(get(r.id), CancelParams(Dict("id" => get(r.id)))), server)
    end
    arg = sum(!(a isa PUNCTUATION) for a in fcall.args) - 1

    sigs = SignatureHelp(SignatureInformation[], 0, 0)

    for m in methods(x)
        args = Base.arg_decl_parts(m)[2]
        p_sigs = [join(string.(p), "::") for p in args[2:end]]
        desc = string(m)
        PI = map(ParameterInformation, p_sigs)
        push!(sigs.signatures, SignatureInformation(desc, "", PI))
    end
    
    
    nsEy = join(vcat(s.namespace, str_value(fname)), ".")
    if haskey(s.symbols, nsEy)
        for vl in s.symbols[nsEy]
            if vl.v.t == :function
                sig = CSTParser.get_sig(vl.v.val)
                if sig isa CSTParser.BinarySyntaxOpCall && CSTParser.is_decl(sig.op)
                    sig = sig.arg1
                end
                Ps = ParameterInformation[]
                for j = 2:length(sig.args)
                    if sig.args[j] isa EXPR{CSTParser.Parameters}
                        for parg in sig.args[j].args
                            if !(sig.args[j] isa PUNCTUATION)
                                arg_id = str_value(CSTParser._arg_id(sig.args[j]))
                                arg_t = CSTParser.get_t(sig.args[j])
                                push!(Ps, ParameterInformation(string(arg_id,"::",arg_t)))
                            end
                        end
                    else
                        if !(sig.args[j] isa PUNCTUATION)
                            arg_id = str_value(CSTParser._arg_id(sig.args[j]))
                            arg_t = CSTParser.get_t(sig.args[j])
                            push!(Ps, ParameterInformation(string(arg_id,"::",arg_t)))
                        end
                    end
                end
                push!(sigs.signatures, SignatureInformation(string(Expr(sig)), "", Ps))
            end
        end
    end
    

    signatureHelper = SignatureHelp(filter(s -> length(s.parameters) > arg, sigs.signatures), 0, arg)
    response = JSONRPC.Response(get(r.id), signatureHelper)
    
    send(response, server)
end


function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params)
    return DocumentSymbolParams(params) 
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(get(r.id), CancelParams(get(r.id))), server)
        return
    end
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]
    S = StaticLint.trav(doc, server, StaticLint.Location(uri2filepath(uri), -1))
    syms = SymbolInformation[]
    
    for (name, bindings) in S.current_scope.names
        for binding in bindings
            push!(syms, SymbolInformation(name, SymbolKind(binding.t), Location(uri, Range(doc, binding.loc.offset))))
        end
    end
    
    response = JSONRPC.Response(get(r.id), syms) 
    send(response, server) 
end

