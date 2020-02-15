function get_signatures(b, sigs, server) end

function get_signatures(b::StaticLint.Binding, sigs, server)
    if b.type == StaticLint.CoreTypes.Function
        if b.val isa EXPR && CSTParser.defines_function(b.val)
            sig = CSTParser.rem_where_decl(CSTParser.get_sig(b.val))
            args = []
            if sig.args !== nothing
                for i = 2:length(sig.args)
                    if bindingof(sig.args[i]) !== nothing 
                        push!(args, bindingof(sig.args[i]))
                    end
                end
            end
            params = (a->ParameterInformation(valof(a.name) isa String ? valof(a.name) : "", missing)).(args)
            push!(sigs, SignatureInformation(string(Expr(sig)), "", params))
        end
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("textDocument/signatureHelp")}}, params) = TextDocumentPositionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/signatureHelp")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/signatureHelp for non-existing document.")
    end
    doc = server.documents[URI2(r.params.textDocument.uri)] 
    sigs = SignatureInformation[]
    offset = get_offset(doc, r.params.position)
    rng = Range(doc, offset:offset)
    x = get_expr(getcst(doc), offset)
    arg = 0

    if x isa EXPR && parentof(x) isa EXPR && typof(parentof(x)) === CSTParser.Call
        if typof(parentof(x).args[1]) === CSTParser.IDENTIFIER
            call_name = parentof(x).args[1]
        elseif typof(parentof(x).args[1]) === CSTParser.Curly && typof(parentof(x).args[1].args[1]) === CSTParser.IDENTIFIER
            call_name = parentof(x).args[1].args[1]
        elseif typof(parentof(x).args[1]) === CSTParser.BinaryOpCall && kindof(parentof(x).args[1].args[2]) === CSTParser.Tokens.DOT && length(parentof(x).args[1].args) == 3 && length(parentof(x).args[1].args[3]) == 1
            call_name = parentof(x).args[1].args[3].args[1]
        else
            call_name = nothing
        end
        if call_name !== nothing && StaticLint.hasref(call_name)
            f_binding = refof(call_name)
            while f_binding isa StaticLint.Binding || f_binding isa SymbolServer.FunctionStore
                if f_binding isa StaticLint.Binding && f_binding.type == StaticLint.CoreTypes.Function
                    get_signatures(f_binding, sigs, server)
                    f_binding = f_binding.prev
                elseif refof(call_name) isa SymbolServer.FunctionStore
                    for m in refof(call_name).methods
                        sig = string(call_name.val, "(", join([a[2] for a in m.args], ", "),")")
                        params = (a->ParameterInformation(a[1], missing)).(m.args)
                        push!(sigs, SignatureInformation(sig, "", params))
                    end
                    break
                else
                    break
                end
            end
        end
    end
    if (isempty(sigs) || (typof(x) === CSTParser.PUNCTUATION  && kindof(x) === CSTParser.Tokens.RPAREN))
        return SignatureHelp(SignatureInformation[], 0, 0)
    end

    if typof(x) === CSTParser.Tokens.LPAREN
        arg = 0
    else
        arg = sum(!(typof(a) === CSTParser.PUNCTUATION) for a in parentof(x).args) - 1
    end
    return SignatureHelp(filter(s->length(s.parameters) > arg, sigs), 0, arg)
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/definition")}}, params) = TextDocumentPositionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/definition")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/definition for non-existing document.")
    end
    locations = Location[]
    doc = server.documents[URI2(r.params.textDocument.uri)]
    offset = get_offset(doc, r.params.position)
    x = get_expr1(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x)
        b = refof(x)
        if b isa SymbolServer.FunctionStore || b isa SymbolServer.DataTypeStore
            for m in b.methods
                if isfile(m.file)
                    push!(locations, Location(filepath2uri(m.file), Range(m.line - 1, 0, m.line -1, 0)))
                end
            end
        elseif b isa StaticLint.Binding && b.val isa StaticLint.Binding
            b = b.val
        end

        while b isa StaticLint.Binding
            if b.val isa EXPR
                doc1, o = get_file_loc(b.val)
                if doc1 isa Document
                    push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:b.val.span))))
                end
            elseif b.val isa SymbolServer.FunctionStore
                for m in b.val.methods
                    file = isabspath(string(m.file)) ? string(m.file) : Base.find_source_file(string(m.file))
                    ((file, m.line) == DefaultTypeConstructorLoc || file == nothing) && continue
                    push!(locations, Location(filepath2uri(file), Range(m.line - 1, 0, m.line, 0)))
                end
            end
            if b.type == StaticLint.CoreTypes.Function && b.prev isa StaticLint.Binding && (b.prev.type == Function || b.prev.type == StaticLint.CoreTypes.DataType)
                b = b.prev
            else
                b = nothing
            end
        end
    elseif x isa EXPR && typof(x) === CSTParser.LITERAL && (kindof(x) === Tokens.STRING || kindof(x) === Tokens.TRIPLE_STRING)
        if sizeof(valof(x)) < 256 # AUDIT: OK
            if isfile(valof(x))
                push!(locations, Location(filepath2uri(valof(x)), Range(0, 0, 0, 0)))
            elseif isfile(joinpath(dirname(uri2filepath(doc._uri)), valof(x)))
                push!(locations, Location(filepath2uri(joinpath(dirname(uri2filepath(doc._uri)), valof(x))), Range(0, 0, 0, 0)))
            end
        end
    end
    
    return locations
end

function get_file_loc(x::EXPR, offset = 0, c  = nothing)
    if c !== nothing
        for a in x.args
            a == c && break
            offset += a.fullspan
        end
    end
    if parentof(x) !== nothing
        return get_file_loc(parentof(x), offset, x)
    elseif typof(x) === CSTParser.FileH && StaticLint.hasmeta(x)
        # return x.ref, offset
        return x.meta.error, offset
    else
        return nothing, offset
    end
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/formatting")}}, params) = DocumentFormattingParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/formatting")},DocumentFormattingParams}, server::LanguageServerInstance)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/formatting for non-existing document.")
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    newcontent = DocumentFormat.format(get_text(doc), server.format_options)
    end_l, end_c = get_position_at(doc, sizeof(get_text(doc))) # AUDIT: OK
    lsedits = TextEdit[TextEdit(Range(0, 0, end_l, end_c), newcontent)]

    return lsedits
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentLink")}}, params) = DocumentLinkParams(params) 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentLink")},DocumentLinkParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/documentLink for non-existing document.")
    end
    links = Tuple{String,UnitRange{Int}}[]

    return links
end


function find_references(textDocument::TextDocumentIdentifier, position::Position, server)
    locations = Location[]
    doc = server.documents[URI2(textDocument.uri)] 
    offset = get_offset(doc, position)
    x = get_expr1(getcst(doc), offset)
    if x isa EXPR && StaticLint.hasref(x) && refof(x) isa StaticLint.Binding
        for r in refof(x).refs
            !(r isa EXPR) && continue
            doc1, o = get_file_loc(r)
            if doc1 isa Document
                push!(locations, Location(doc1._uri, Range(doc1, o .+ (0:r.span))))
            end
        end
    end
    return locations
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/references")}}, params) = ReferenceParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/references")},ReferenceParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/references for non-existing document.")
    end
    locations = find_references(r.params.textDocument, r.params.position, server)
    return locations
end

JSONRPC.parse_params(::Type{Val{Symbol("textDocument/rename")}}, params) = RenameParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/rename")},RenameParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/rename for non-existing document.")
    end
    tdes = Dict{String,TextDocumentEdit}()
    locations = find_references(r.params.textDocument, r.params.position, server)
    
    for loc in locations
        if loc.uri in keys(tdes)
            push!(tdes[loc.uri].edits, TextEdit(loc.range, r.params.newName))
        else
            tdes[loc.uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(loc.uri, server.documents[URI2(loc.uri)]._version), [TextEdit(loc.range, r.params.newName)])
        end
    end
    
    return WorkspaceEdit(nothing, collect(values(tdes)))
end


JSONRPC.parse_params(::Type{Val{Symbol("textDocument/documentSymbol")}}, params) = DocumentSymbolParams(params) 
function process(r::JSONRPC.Request{Val{Symbol("textDocument/documentSymbol")},DocumentSymbolParams}, server) 
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        error("Received 'textDocument/documentSymbol for non-existing document.")
    end
    syms = SymbolInformation[]
    uri = r.params.textDocument.uri 
    doc = server.documents[URI2(uri)]

    bs = collect_bindings_w_loc(getcst(doc))
    for x in bs
        p,b = x[1], x[2]
        !(b.val isa EXPR) && continue
        (valof(b.name) === nothing || isempty(valof(b.name))) && typof(b.name) !== CSTParser.OPERATOR && continue
        push!(syms, SymbolInformation(typof(b.name) === CSTParser.OPERATOR ? string(Expr(b.name)) : valof(b.name), _binding_kind(b, server), false, Location(doc._uri, Range(doc, p)), nothing))
    end
    return syms
end

function collect_bindings_w_loc(x::EXPR, pos = 0, bindings = Tuple{UnitRange{Int},StaticLint.Binding}[])
    if bindingof(x) !== nothing
        push!(bindings, (pos .+ (0:x.span), bindingof(x)))
    end
    if x.args !== nothing
        for a in x.args
            collect_bindings_w_loc(a, pos, bindings)
            pos += a.fullspan
        end
    end
    return bindings
end

function collect_toplevel_bindings_w_loc(x::EXPR, pos = 0, bindings = Tuple{UnitRange{Int},StaticLint.Binding}[]; query = "")
    # if bindingof(x) isa StaticLint.Binding && !isempty(valof(bindingof(x).name)) && bindingof(x).val isa EXPR && startswith(valof(bindingof(x).name), query)
    if bindingof(x) isa StaticLint.Binding && valof(bindingof(x).name) isa String && bindingof(x).val isa EXPR && startswith(valof(bindingof(x).name), query)
        push!(bindings, (pos .+ (0:x.span), bindingof(x)))
    end
    if scopeof(x) !== nothing && !(typof(x) === CSTParser.FileH || typof(x) === CSTParser.ModuleH || typof(x) === CSTParser.BareModule)
        return bindings
    end
    if x.args !== nothing
        for a in x.args
            collect_toplevel_bindings_w_loc(a, pos, bindings, query = query)
            pos += a.fullspan
        end
    end
    return bindings
end

function _binding_kind(b ,server)
    if b isa StaticLint.Binding
        if b.type == nothing
            return 13
        elseif b.type == StaticLint.CoreTypes.Module
            return 2
        elseif b.type == StaticLint.CoreTypes.Function
            return 12
        elseif b.type == StaticLint.CoreTypes.String
            return 15
        elseif b.type == StaticLint.CoreTypes.Int || b.type == StaticLint.CoreTypes.Float64
            return 16
        elseif b.type == StaticLint.CoreTypes.DataType
            return 23
        else 
            return 13
        end
    elseif b isa SymbolServer.ModuleStore
        return 2
    elseif b isa SymbolServer.MethodStore
        return 6        
    elseif b isa SymbolServer.FunctionStore
        return 12
    elseif b isa SymbolServer.DataTypeStore
        return 23
    else 
        return 13
    end
end
