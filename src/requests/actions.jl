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
        if parentof(x) isa EXPR && typof(parentof(x)) === CSTParser.Using &&  refof(x) isa StaticLint.Binding
            if refof(x).type === StaticLint.CoreTypes.Module || refof(x).val isa StaticLint.Binding && refof(x).val.type === StaticLint.CoreTypes.Module
                reexport_module(x, actions, server)
            elseif refof(x).val isa SymbolServer.ModuleStore 
                reexport_package(x, actions, server)
            end
        end
        if is_in_fexpr(x, is_single_line_func)
            expand_inline_func(x, actions)
        end
        if is_in_fexpr(x, CSTParser.defines_struct)
            add_default_constructor(x, actions)
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
        insertpos = get_next_line_offset(using_stmt)
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

is_single_line_func(x) = CSTParser.defines_function(x) && typof(x) !== CSTParser.FunctionDef

function expand_inline_func(x, actions)
    func = _get_parent_fexpr(x, is_single_line_func)
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


function add_default_constructor(x::EXPR, actions)
    sexpr = _get_parent_fexpr(x, CSTParser.defines_struct)
    !(sexpr.args isa Vector{EXPR}) && return
    ismutable = length(sexpr.args) == 5
    name = CSTParser.get_name(sexpr)
    sig = sexpr.args[2 + ismutable]
    block = sexpr.args[3 + ismutable]

    isempty(block.args) && return
    any(CSTParser.defines_function(a) for a in block.args) && return # constructor already exists

    newtext = string("\n    function $(valof(name))(args...)\n\n        new")
    # if DataType is parameterised do something here

    newtext = string(newtext, "(")
    for i in 1:length(block.args)
        newtext = string(newtext, "", valof(CSTParser.get_arg_name(block.args[i])))
        newtext = string(newtext, i < length(block.args) ? ", " : ")\n    end")
    end
    file, offset = get_file_loc(last(block.args))
    offset += last(block.args).span
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[TextEdit(Range(file, offset:offset), newtext)])
    push!(actions, CodeAction("Add default constructor.", missing, missing, WorkspaceEdit(nothing, TextDocumentEdit[tde]), missing))
end

function is_in_fexpr(x::EXPR, f)
    if f(x)
        return true
    elseif parentof(x) isa EXPR
        return is_in_fexpr(parentof(x), f)
    else
        return false
    end
end

function _get_parent_fexpr(x::EXPR, f)
    if f(x)
        return x
    elseif parentof(x) isa EXPR
        return _get_parent_fexpr(parentof(x), f)
    end
end
function get_next_line_offset(x)
    file, offset = get_file_loc(x)
    # get next line after using_stmt
    insertpos = -1
    for i = 1:length(file._line_offsets)-1
        if file._line_offsets[i] < offset + x.span <= file._line_offsets[i+1]
            insertpos = file._line_offsets[i+1]
        end
    end
    return insertpos
end

function reexport_package(x::EXPR, actions, server)
    using_stmt = parentof(x)
    file, offset = get_file_loc(x)
    insertpos = get_next_line_offset(using_stmt)
    insertpos == -1 && return 
    
    tde =TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
        TextEdit(Range(file, insertpos .+ (0:0)), string("export ", join(sort(collect(refof(x).val.exported)), ", "), "\n"))
    ])
    push!(actions, CodeAction("Re-export package variables.", missing, missing, WorkspaceEdit(nothing, TextDocumentEdit[tde]), missing))
end

#TODO move to StaticLint
# to be called where typof(x) === CSTParser.ModuleH/BareModule 
function find_exported_names(x::EXPR)
    exported_vars = EXPR[]
    for i in 1:length(x.args[3].args)
        expr = x.args[3].args[i]
        if typof(expr) == CSTParser.Export && 
            for j = 2:length(expr)
                if CSTParser.isidentifier(expr.args[j]) && StaticLint.hasref(expr.args[j])
                    push!(exported_vars, expr.args[j])
                end
            end
        end
    end
    return exported_vars
end

function reexport_module(x::EXPR, actions, server)
    using_stmt = parentof(x)
    mod_expr = refof(x).val isa StaticLint.Binding ? refof(x).val.val : refof(x).val
    (mod_expr.args isa Nothing || length(mod_expr.args) < 3 || typof(mod_expr.args[3]) != CSTParser.Block || mod_expr.args[3].args isa Nothing) && return # module expr without block
    # find export EXPR
    exported_names = find_exported_names(mod_expr)
    
    isempty(exported_names) && return
    file, offset = get_file_loc(x)
    insertpos = get_next_line_offset(using_stmt)
    insertpos == -1 && return 
    names = filter!(s->!isempty(s), collect(CSTParser.str_value.(exported_names)))
    tde =TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
        TextEdit(Range(file, insertpos .+ (0:0)), string("export ", join(sort(names), ", "), "\n"))
    ])
    push!(actions, CodeAction("Re-export package variables.", missing, missing, WorkspaceEdit(nothing, TextDocumentEdit[tde]), missing))
end