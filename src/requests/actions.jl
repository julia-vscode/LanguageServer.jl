JSONRPC.parse_params(::Type{Val{Symbol("textDocument/codeAction")}}, params) = CodeActionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/codeAction")},CodeActionParams}, server)
    actions = CodeAction[]
    doc = server.documents[URI2(r.params.textDocument.uri)] 
    offset = get_offset(doc, r.params.range.start)
    x = get_expr(getcst(doc), offset)
    if x isa EXPR
        if refof(x) isa StaticLint.Binding && refof(x).val isa SymbolServer.ModuleStore 
            explicitly_import_used_variables(x, actions, server)
        end
        if is_in_inline_func(x)
            expand_inline_func(x, actions)
        end
    end

    send(JSONRPC.Response(r.id, actions), server)
end

function find_using_statement(x::EXPR)
    for ref in refof(x).refs
        if parentof(ref) isa EXPR && typof(parentof(ref)) === CSTParser.Using
            return parentof(ref)
        end
    end
    return nothing
end

function explicitly_import_used_variables(x::EXPR, actions, server)
    !(refof(x) isa StaticLint.Binding && refof(x).val isa SymbolServer.ModuleStore) && return
    using_stmt = find_using_statement(x)
    using_stmt isa Nothing && return
    
    tdes = Dict{String,TextDocumentEdit}()
    vars = Set{String}() # names that need to be imported

    # Find uses of `x` and mark edits
    for ref in refof(x).refs
        if parentof(ref) isa EXPR && typof(parentof(ref)) == CSTParser.BinaryOpCall && length(parentof(ref).args) == 3 && kindof(parentof(ref).args[2]) === CSTParser.Tokens.DOT && parentof(ref).args[1] == ref
            typof(parentof(ref).args[3]) !== CSTParser.Quotenode && continue # some malformed EXPR, skip
            childname = parentof(ref).args[3].args[1]
            StaticLint.hasref(childname) && refof(childname) isa StaticLint.Binding && continue # check this isn't the name of something being explictly overwritten
            !haskey(refof(x).val.vals, valof(childname)) && continue # skip, perhaps mark as missing ref ?
            
            file, offset = get_file_loc(ref)
            if !haskey(tdes, file._uri)
                tdes[file._uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[])
            end
            push!(tdes[file._uri].edits, TextEdit(Range(file, offset .+ (0:parentof(ref).span)), valof(childname)))
            push!(vars, valof(childname))
        end
    end
    isempty(tdes) && return
    
    # Add `using x: vars...` statement
    if parentof(using_stmt) isa EXPR && (typof(parentof(using_stmt)) === CSTParser.Block || typof(parentof(using_stmt)) === CSTParser.FileH)
        # this should cover all cases
        i1 = 0
        for i = 1:length(parentof(using_stmt).args)
            if using_stmt === parentof(using_stmt).args[i]
                i1 = i
                break
            end
        end
        i1 == 0 && return WorkspaceEdit(missing, missing)
        
        file, offset = get_file_loc(using_stmt)
        # get next line after using_stmt
        insertpos = -1
        for i = 1:length(file._line_offsets)-1
            if file._line_offsets[i] < offset + using_stmt.span <= file._line_offsets[i+1]
                insertpos = file._line_offsets[i+1]
            end
        end
        insertpos == -1 && return 

        if !haskey(tdes, file._uri)
            tdes[file._uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[])
        end
        push!(tdes[file._uri].edits, TextEdit(Range(file, insertpos .+ (0:0)), string("using ", valof(x), ": ", join(vars, ", "), "\n")))
    else
        return
    end
    push!(actions, CodeAction("Explicitly import package variables.", missing, missing, WorkspaceEdit(nothing, collect(values(tdes))), missing))
    return 
end

function is_in_inline_func(x::EXPR)
    if CSTParser.defines_function(x) && typof(x) !== CSTParser.FunctionDef
        return true
    elseif parentof(x) isa EXPR
        return is_in_inline_func(parentof(x))
    else
        return false
    end
end

function _get_inline_func(x::EXPR)
    if CSTParser.defines_function(x) && typof(x) !== CSTParser.FunctionDef
        return x
    elseif parentof(x) isa EXPR
        return _get_inline_func(parentof(x))
    end
end

function expand_inline_func(x, actions)
    func = _get_inline_func(x)
    sig = func.args[1]
    op = func.args[2]
    body = func.args[3]
    if typof(body) == CSTParser.Block && body.args !== nothing length(body.args) == 1
        file, offset = get_file_loc(func)
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
            TextEdit(Range(file, offset .+ (0:func.fullspan)), string("function ", get_text(file)[offset .+ (1:sig.span)], "\n    ", get_text(file)[offset + sig.fullspan + op.fullspan .+ (1:body.span)], "\nend\n"))
        ])
        push!(actions, CodeAction("Expand function definition.", missing, missing, WorkspaceEdit(nothing, TextDocumentEdit[tde]), missing))
    elseif (typof(body) === CSTParser.Begin || typof(body) === CSTParser.InvisBrackets) && body.args isa Vector{EXPR} && length(body.args) == 3 &&
        typof(body.args[2]) === CSTParser.Block && body.args[2].args isa Vector{EXPR}
        file, offset = get_file_loc(func)
        newtext = string("function ",get_text(file)[offset .+ (1:sig.span)])
        blockoffset = offset + sig.fullspan + op.fullspan + body.args[1].fullspan
        for i = 1:length(body.args[2].args)
            newtext = string(newtext, "\n    ", get_text(file)[blockoffset .+ (1:body.args[2].args[i].span)])
            blockoffset += body.args[2].args[i].fullspan
        end
        newtext = string(newtext, "\nend\n")
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[TextEdit(Range(file, offset .+ (0:func.fullspan)), newtext)])
        push!(actions, CodeAction("Expand function definition.", missing, missing, WorkspaceEdit(nothing, TextDocumentEdit[tde]), missing))
    end
end
