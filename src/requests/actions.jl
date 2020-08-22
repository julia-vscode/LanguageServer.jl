function textDocument_codeAction_request(params::CodeActionParams, server::LanguageServerInstance, conn)
    commands = Command[]
    doc = getdocument(server, URI2(params.textDocument.uri))
    offset = get_offset(doc, params.range.start)
    offset1 = get_offset(doc, params.range.stop)
    x = get_expr(getcst(doc), offset)
    arguments = Any[params.textDocument.uri, offset, offset1] # use the same arguments for all commands
    if x isa EXPR
        if refof(x) isa StaticLint.Binding && refof(x).val isa SymbolServer.ModuleStore
            push!(commands, Command("Explicitly import used package variables.", "ExplicitPackageVarImport", arguments))
        end
        if parentof(x) isa EXPR && typof(parentof(x)) === CSTParser.Using &&  refof(x) isa StaticLint.Binding
            if refof(x).type === StaticLint.CoreTypes.Module || (refof(x).val isa StaticLint.Binding && refof(x).val.type === StaticLint.CoreTypes.Module) || refof(x).val isa SymbolServer.ModuleStore
                push!(commands, Command("Re-export package variables.", "ReexportModule", arguments))
            end
        end
        if is_in_fexpr(x, is_single_line_func)
            push!(commands, Command("Expand function definition.", "ExpandFunction", arguments))
        end
        if is_in_fexpr(x, CSTParser.defines_struct)
            push!(commands, Command("Add default constructor", "AddDefaultConstructor", arguments))
        end
        if is_fixable_missing_ref(x, params.context)
            push!(commands, Command("Fix missing reference", "FixMissingRef", arguments))
        end
        # if params.range.start.line != params.range.stop.line # selection across _line_offsets
        #     push!(commands, Command("Wrap in `if` block.", "WrapIfBlock", arguments))
        # end
    end

    return commands
end

function workspace_executeCommand_request(params::ExecuteCommandParams, server::LanguageServerInstance, conn)
    uri = params.arguments[1]
    offset = params.arguments[2]
    doc = getdocument(server, URI2(uri))
    x = get_expr(getcst(doc), offset)
    if params.command == "ExplicitPackageVarImport"
        explicitly_import_used_variables(x, server, conn)
    elseif params.command == "ExpandFunction"
        expand_inline_func(x, server, conn)
    elseif params.command == "AddDefaultConstructor"
        add_default_constructor(x, server, conn)
    elseif params.command == "ReexportModule"
        if refof(x).type === StaticLint.CoreTypes.Module || (refof(x).val isa StaticLint.Binding && refof(x).val.type === StaticLint.CoreTypes.Module)
            reexport_module(x, server, conn)
        elseif refof(x).val isa SymbolServer.ModuleStore
            reexport_package(x, server, conn)
        end
    elseif params.command == "WrapIfBlock"
        wrap_block(get_expr(getcst(doc), params.arguments[2]:params.arguments[3]), server, :if, conn)
    elseif params.command == "FixMissingRef"
        applymissingreffix(x, server, conn)
    end
end


function find_using_statement(x::EXPR)
    for ref in refof(x).refs
        if parentof(ref) isa EXPR && typof(parentof(ref)) === CSTParser.Using
            return parentof(ref)
        end
    end
    return nothing
end

function explicitly_import_used_variables(x::EXPR, server, conn)
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

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, collect(values(tdes)))))
end

is_single_line_func(x) = CSTParser.defines_function(x) && typof(x) !== CSTParser.FunctionDef

function expand_inline_func(x, server, conn)
    func = _get_parent_fexpr(x, is_single_line_func)
    length(func) < 3 && return
    sig = func[1]
    op = func[2]
    body = func[3]
    if typof(body) == CSTParser.Block && length(body) == 1
        file, offset = get_file_loc(func)
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
            TextEdit(Range(file, offset .+ (0:func.fullspan)), string("function ", get_text(file)[offset .+ (1:sig.span)], "\n    ", get_text(file)[offset + sig.fullspan + op.fullspan .+ (1:body.span)], "\nend\n"))
        ])
        JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    elseif (typof(body) === CSTParser.Begin || typof(body) === CSTParser.InvisBrackets) && length(body) == 3 &&
        typof(body[2]) === CSTParser.Block && length(body[2]) > 0
        file, offset = get_file_loc(func)
        newtext = string("function ", get_text(file)[offset .+ (1:sig.span)])
        blockoffset = offset + sig.fullspan + op.fullspan + body[1].fullspan
        for i = 1:length(body[2])
            newtext = string(newtext, "\n    ", get_text(file)[blockoffset .+ (1:body[2][i].span)])
            blockoffset += body[2][i].fullspan
        end
        newtext = string(newtext, "\nend\n")
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[TextEdit(Range(file, offset .+ (0:func.fullspan)), newtext)])
        JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    end
end


function add_default_constructor(x::EXPR, server, conn)
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

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
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
    line_offsets = get_line_offsets(file)
    for i = 1:length(line_offsets) - 1
        if line_offsets[i] < offset + x.span <= line_offsets[i + 1]
            insertpos = line_offsets[i + 1]
        end
    end
    return insertpos
end

function reexport_package(x::EXPR, server, conn)
    mod::SymbolServer.ModuleStore = refof(x).val
    using_stmt = parentof(x)
    file, offset = get_file_loc(x)
    insertpos = get_next_line_offset(using_stmt)
    insertpos == -1 && return

    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
        TextEdit(Range(file, insertpos .+ (0:0)), string("export ", join(sort([string(n) for (n, v) in mod.vals if StaticLint.isexportedby(n, mod)]), ", "), "\n"))
    ])

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

# TODO move to StaticLint
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

function reexport_module(x::EXPR, server, conn)
    using_stmt = parentof(x)
    mod_expr = refof(x).val isa StaticLint.Binding ? refof(x).val.val : refof(x).val
    (mod_expr.args isa Nothing || length(mod_expr.args) < 3 || typof(mod_expr.args[3]) != CSTParser.Block || mod_expr.args[3].args isa Nothing) && return # module expr without block
    # find export EXPR
    exported_names = find_exported_names(mod_expr)

    isempty(exported_names) && return
    file, offset = get_file_loc(x)
    insertpos = get_next_line_offset(using_stmt)
    insertpos == -1 && return
    names = filter!(s -> !isempty(s), collect(CSTParser.str_value.(exported_names)))
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
        TextEdit(Range(file, insertpos .+ (0:0)), string("export ", join(sort(names), ", "), "\n"))
    ])

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function wrap_block(x, server, type, conn) end
function wrap_block(x::EXPR, server, type, conn)
    file, offset = get_file_loc(x) # rese
    l0, _ = get_position_at(file, offset)
    l1, _ = get_position_at(file, offset + x.span)
    if type == :if
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
            TextEdit(Range(file, offset .+ (0:0)), "if CONDITION\n"),
            TextEdit(Range(file, offset + x.span .+ (0:0)), "\nend")
        ])
    end

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end


function is_fixable_missing_ref(x::EXPR, cac::CodeActionContext)
    if !isempty(cac.diagnostics) && any(startswith(d.message, "Missing reference") for d::Diagnostic in cac.diagnostics) && CSTParser.isidentifier(x)
        xname = StaticLint.valofid(x)
        tls = StaticLint.retrieve_toplevel_scope(x)
        if tls isa StaticLint.Scope && tls.modules !== nothing
            for (n, m) in tls.modules
                if (m isa SymbolServer.ModuleStore && haskey(m, Symbol(xname))) || (m isa StaticLint.Scope && StaticLint.scopehasbinding(m, xname))
                    return true
                end
            end
        end
    end
    return false
end

function applymissingreffix(x, server, conn)
    xname = StaticLint.valofid(x)
    file, offset = get_file_loc(x)
    l, c = get_position_at(file, offset)
    tls = StaticLint.retrieve_toplevel_scope(x)
    if tls.modules !== nothing
        for (n, m) in tls.modules
            if (m isa SymbolServer.ModuleStore && haskey(m, Symbol(xname))) || (m isa StaticLint.Scope && StaticLint.scopehasbinding(m, xname))
                tde = TextDocumentEdit(VersionedTextDocumentIdentifier(file._uri, file._version), TextEdit[
                    TextEdit(Range(file, offset .+ (0:0)), string(n, "."))
                ])
                JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
            end
        end
    end
end
