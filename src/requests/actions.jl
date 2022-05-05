struct ServerAction
    id::String
    desc::String
    kind::Union{CodeActionKind,Missing}
    preferred::Union{Bool,Missing}
    when::Function
    handler::Function
end

function client_support_action_kind(s::LanguageServerInstance, _::CodeActionKind=CodeActionKinds.Empty)
    if s.clientCapabilities !== missing &&
       s.clientCapabilities.textDocument !== missing &&
       s.clientCapabilities.textDocument.codeAction !== missing &&
       s.clientCapabilities.textDocument.codeAction.codeActionLiteralSupport !== missing
       s.clientCapabilities.textDocument.codeAction.codeActionLiteralSupport.codeActionKind !== missing
        # From the spec of CodeActionKind (https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#codeActionClientCapabilities):
        #
        #     The code action kind values the client supports. When this
        #     property exists the client also guarantees that it will
        #     handle values outside its set gracefully and falls back
        #     to a default value when unknown.
        #
        # so we can always return true here(?).
        return true
    else
        return false
    end
end

function client_preferred_support(s::LanguageServerInstance)::Bool
    if s.clientCapabilities !== missing &&
       s.clientCapabilities.textDocument !== missing &&
       s.clientCapabilities.textDocument.codeAction !== missing &&
       s.clientCapabilities.textDocument.codeAction.isPreferredSupport !== missing
       return s.clientCapabilities.textDocument.codeAction.isPreferredSupport
   else
       return false
    end
end

# TODO: All currently supported CodeActions in LS.jl can be converted "losslessly" to
#       Commands but this might not be true in the future so unless the client support
#       literal code actions those need to be filtered out.
function convert_to_command(ca::CodeAction)
    return ca.command
end

function textDocument_codeAction_request(params::CodeActionParams, server::LanguageServerInstance, conn)
    actions = CodeAction[]
    doc = getdocument(server, params.textDocument.uri)
    offset = index_at(doc, params.range.start)
    x = get_expr(getcst(doc), offset)
    arguments = Any[params.textDocument.uri, offset] # use the same arguments for all commands
    if x isa EXPR
        for (_, sa) in LSActions
            if sa.when(x, params)
                action = CodeAction(
                    sa.desc, # title
                    sa.kind, # kind
                    missing, # diagnostics
                    client_preferred_support(server) ? sa.preferred : missing, # isPreferred
                    missing, # edit
                    Command(sa.desc, sa.id, arguments), # command
                )
                push!(actions, action)
            end
        end
    end
    if client_support_action_kind(server)
        return actions
    else
        # TODO: Future CodeActions might have to be filtered here.
        return convert_to_command.(actions)
    end
end

function workspace_executeCommand_request(params::ExecuteCommandParams, server::LanguageServerInstance, conn)
    if haskey(LSActions, params.command)
        uri = URI(params.arguments[1])
        offset = params.arguments[2]
        doc = getdocument(server, uri)
        x = get_expr(getcst(doc), offset)
        LSActions[params.command].handler(x, server, conn)
    end
end


function find_using_statement(x::EXPR)
    for ref in refof(x).refs
        if StaticLint.is_in_fexpr(ref, x -> headof(x) === :using || headof(x) === :import)
            return parentof(ref)
        end
    end
    return nothing
end

function explicitly_import_used_variables(x::EXPR, server, conn)
    !(refof(x) isa StaticLint.Binding && refof(x).val isa SymbolServer.ModuleStore) && return
    using_stmt = find_using_statement(x)
    using_stmt isa Nothing && return

    tdes = Dict{URI,TextDocumentEdit}()
    vars = Set{String}() # names that need to be imported
    # Find uses of `x` and mark edits
    for ref in refof(x).refs
        if parentof(ref) isa EXPR && CSTParser.is_getfield_w_quotenode(parentof(ref)) && parentof(ref).args[1] == ref
            childname = parentof(ref).args[2].args[1]
            StaticLint.hasref(childname) && refof(childname) isa StaticLint.Binding && continue # check this isn't the name of something being explictly overwritten
            !haskey(refof(x).val.vals, Symbol(valof(childname))) && continue # skip, perhaps mark as missing ref ?

            file, offset = get_file_loc(ref)
            if !haskey(tdes, get_uri(file))
                tdes[get_uri(file)] = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[])
            end
            push!(tdes[get_uri(file)].edits, TextEdit(Range(file, offset .+ (0:parentof(ref).span)), valof(childname)))
            push!(vars, valof(childname))
        end
    end
    isempty(tdes) && return

    # Add `using x: vars...` statement
    if parentof(using_stmt) isa EXPR && (headof(parentof(using_stmt)) === :block || headof(parentof(using_stmt)) === :file)
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

        if !haskey(tdes, get_uri(file))
            tdes[get_uri(file)] = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[])
        end
        push!(tdes[get_uri(file)].edits, TextEdit(Range(file, insertpos .+ (0:0)), string("using ", valof(x), ": ", join(vars, ", "), "\n")))
    else
        return
    end

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, collect(values(tdes)))))
end

is_single_line_func(x) = CSTParser.defines_function(x) && headof(x) !== :function

function expand_inline_func(x, server, conn)
    func = _get_parent_fexpr(x, is_single_line_func)
    length(func) < 3 && return
    sig = func.args[1]
    op = func.head
    body = func.args[2]
    if headof(body) == :block && length(body) == 1
        file, offset = get_file_loc(func)
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
            TextEdit(Range(file, offset .+ (0:func.fullspan)), string("function ", get_text(file)[offset .+ (1:sig.span)], "\n    ", get_text(file)[offset + sig.fullspan + op.fullspan .+ (1:body.span)], "\nend\n"))
        ])
        JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    elseif (headof(body) === :begin || CSTParser.isbracketed(body)) &&
        headof(body.args[1]) === :block && length(body.args[1]) > 0
        file, offset = get_file_loc(func)
        newtext = string("function ", get_text(file)[offset .+ (1:sig.span)])
        blockoffset = offset + sig.fullspan + op.fullspan + body.trivia[1].fullspan
        for i = 1:length(body.args[1].args)
            newtext = string(newtext, "\n    ", get_text(file)[blockoffset .+ (1:body.args[1].args[i].span)])
            blockoffset += body.args[1].args[i].fullspan
        end
        newtext = string(newtext, "\nend\n")
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[TextEdit(Range(file, offset .+ (0:func.fullspan)), newtext)])
        JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    end
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
    line_offsets = get_line_offsets(get_text_document(file))
    for i = 1:length(line_offsets) - 1
        if line_offsets[i] < offset + x.span <= line_offsets[i + 1]
            insertpos = line_offsets[i + 1]
        end
    end
    return insertpos
end

function reexport_package(x::EXPR, server, conn)
    (refof(x) isa SymbolServer.ModuleStore || refof(x).type === StaticLint.CoreTypes.Module || (refof(x).val isa StaticLint.Binding && refof(x).val.type === StaticLint.CoreTypes.Module)) || (refof(x).val isa SymbolServer.ModuleStore) || return
    mod = if refof(x) isa SymbolServer.ModuleStore
        refof(x)
    elseif refof(x).val isa SymbolServer.ModuleStore
        refof(x).val
    else
        return
    end
    using_stmt = parentof(x)
    file, _ = get_file_loc(x)
    insertpos = get_next_line_offset(using_stmt)
    insertpos == -1 && return

    text_document = get_text_document(file)

    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(text_document), get_version(text_document)), TextEdit[
        TextEdit(Range(file, insertpos .+ (0:0)), string("export ", join(sort([string(n) for (n, v) in mod.vals if StaticLint.isexportedby(n, mod)]), ", "), "\n"))
    ])

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

# TODO move to StaticL  int
# to be called where typof(x) === CSTParser.ModuleH/BareModule
function find_exported_names(x::EXPR)
    exported_vars = EXPR[]
    for i in 1:length(x.args[3].args)
        expr = x.args[3].args[i]
        if headof(expr) === :export
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
    (mod_expr.args isa Nothing || length(mod_expr.args) < 3 || headof(mod_expr.args[3]) !== :block || mod_expr.args[3].args isa Nothing) && return # module expr without block
    # find export EXPR
    exported_names = find_exported_names(mod_expr)

    isempty(exported_names) && return
    file, _ = get_file_loc(x)
    insertpos = get_next_line_offset(using_stmt)
    insertpos == -1 && return
    names = filter!(s -> !isempty(s), collect(CSTParser.str_value.(exported_names)))
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
        TextEdit(Range(file, insertpos .+ (0:0)), string("export ", join(sort(names), ", "), "\n"))
    ])

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function wrap_block(x, server, type, conn) end
function wrap_block(x::EXPR, server, type, conn)
    file, offset = get_file_loc(x) # rese
    if type == :if
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
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
            for m in values(tls.modules)
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
    tls = StaticLint.retrieve_toplevel_scope(x)
    if tls.modules !== nothing
        for (n, m) in tls.modules
            if (m isa SymbolServer.ModuleStore && haskey(m, Symbol(xname))) || (m isa StaticLint.Scope && StaticLint.scopehasbinding(m, xname))
                tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
                    TextEdit(Range(file, offset .+ (0:0)), string(n, "."))
                ])
                JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
            end
        end
    end
end

function remove_farg_name(x, server, conn)
    x1 = StaticLint.get_parent_fexpr(x, x -> StaticLint.haserror(x) && StaticLint.errorof(x) == StaticLint.UnusedFunctionArgument)
    file, offset = get_file_loc(x1)
    if CSTParser.isdeclaration(x1)
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
                        TextEdit(Range(file, offset .+ (0:x1.args[1].fullspan)), "")
                    ])
    else
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
                        TextEdit(Range(file, offset .+ (0:x1.fullspan)), "_")
                    ])
    end
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function remove_unused_assignment_name(x, _, conn)
    x1 = StaticLint.get_parent_fexpr(x, x -> StaticLint.haserror(x) && StaticLint.errorof(x) == StaticLint.UnusedBinding && x isa EXPR && x.head === :IDENTIFIER)
    file, offset = get_file_loc(x1)
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
                    TextEdit(Range(file, offset .+ (0:x1.span)), "_")
                ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function double_to_triple_equal(x, _, conn)
    x1 = StaticLint.get_parent_fexpr(x, y -> StaticLint.haserror(y) && StaticLint.errorof(y) in (StaticLint.NothingEquality, StaticLint.NothingNotEq))
    file, offset = get_file_loc(x1)
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
        TextEdit(Range(file, offset .+ (0:x1.span)), StaticLint.errorof(x1) == StaticLint.NothingEquality ? "===" : "!==")
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function get_spdx_header(doc::Document)
    m = match(r"(*ANYCRLF)^# SPDX-License-Identifier:\s+((?:[\w\.-]+)(?:\s+[\w\.-]+)*)\s*$"m, get_text(doc))
    return m === nothing ? m : String(m[1])
end

function in_same_workspace_folder(server::LanguageServerInstance, file1::URI, file2::URI)
    for ws in server.workspaceFolders
        if startswith(uri2filepath(file1), ws) &&
           startswith(uri2filepath(file2), ws)
           return true
       end
    end
    return false
end

function identify_short_identifier(server::LanguageServerInstance, file::Document)
    # First look in tracked files (in the same workspace folder) for existing headers
    candidate_identifiers = Set{String}()
    for doc in getdocuments_value(server)
        in_same_workspace_folder(server, get_uri(file), get_uri(doc)) || continue
        id = get_spdx_header(doc)
        id === nothing || push!(candidate_identifiers, id)
    end
    if length(candidate_identifiers) == 1
        return first(candidate_identifiers)
    end
    # Fallback to looking for a license file in the same workspace folder
    candidate_files = String[]
    for dir in server.workspaceFolders
        for f in joinpath.(dir, ["LICENSE", "LICENSE.md"])
            if in_same_workspace_folder(server, get_uri(file), filepath2uri(f)) && safe_isfile(f)
                push!(candidate_files, f)
            end
        end
    end
    length(candidate_files) == 1 || return nothing
    license = read(first(candidate_files), String)

    # This is just a heuristic, but should be OK since this is not something automated, and
    # the programmer will see directly if the wrong license is added.
    # TODO: Add more licenses...
    if any(contains(license, x) for x in ("MIT License", "MIT \"Expat\" License"))
        return "MIT"
    end
    return nothing
end

function add_license_header(x, server::LanguageServerInstance, conn)
    file, _ = get_file_loc(x)
    get_spdx_header(file) === nothing || return # TODO: Would be nice to check this already before offering the action
    short_identifier = identify_short_identifier(server, file)
    short_identifier === nothing && return
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(get_uri(file), get_version(file)), TextEdit[
        TextEdit(Range(file, 0:0), "# SPDX-License-Identifier: $(short_identifier)\n\n")
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

# Adding a CodeAction requires defining:
# * a unique id
# * a description
# * an action kind (optionally)
# * a function (.when) called on the currently selected expression and parameters of the CodeAction call;
# * a function (.handler) called on three arguments (current expression, server and the jr connection) to implement the command.
const LSActions = Dict{String,ServerAction}()

LSActions["ExplicitPackageVarImport"] = ServerAction(
    "ExplicitPackageVarImport",
    "Explicitly import used package variables.",
    missing,
    missing,
    (x, params) -> refof(x) isa StaticLint.Binding && refof(x).val isa SymbolServer.ModuleStore,
    explicitly_import_used_variables
)

LSActions["ExpandFunction"] = ServerAction(
    "ExpandFunction",
    "Expand function definition.",
    CodeActionKinds.Refactor,
    missing,
    (x, params) -> is_in_fexpr(x, is_single_line_func),
    expand_inline_func,
)

LSActions["FixMissingRef"] = ServerAction(
    "FixMissingRef",
    "Fix missing reference",
    missing,
    missing,
    (x, params) -> is_fixable_missing_ref(x, params.context),
    applymissingreffix,
)

LSActions["ReexportModule"] = ServerAction(
    "ReexportModule",
    "Re-export package variables.",
    missing,
    missing,
    (x, params) -> StaticLint.is_in_fexpr(x, x -> headof(x) === :using || headof(x) === :import) && (refof(x) isa StaticLint.Binding && (refof(x).type === StaticLint.CoreTypes.Module || (refof(x).val isa StaticLint.Binding && refof(x).val.type === StaticLint.CoreTypes.Module) || refof(x).val isa SymbolServer.ModuleStore) || refof(x) isa SymbolServer.ModuleStore),
    reexport_package,
)

LSActions["DeleteUnusedFunctionArgumentName"] = ServerAction(
    "DeleteUnusedFunctionArgumentName",
    "Delete name of unused function argument.",
    CodeActionKinds.QuickFix,
    missing,
    (x, params) -> StaticLint.is_in_fexpr(x, x -> StaticLint.haserror(x) && StaticLint.errorof(x) == StaticLint.UnusedFunctionArgument),
    remove_farg_name,
)

LSActions["ReplaceUnusedAssignmentName"] = ServerAction(
    "ReplaceUnusedAssignmentName",
    "Replace unused assignment name with _.",
    CodeActionKinds.QuickFix,
    missing,
    (x, params) -> StaticLint.is_in_fexpr(x, x -> StaticLint.haserror(x) && StaticLint.errorof(x) == StaticLint.UnusedBinding && x isa EXPR && x.head === :IDENTIFIER),
    remove_unused_assignment_name,
)

LSActions["CompareNothingWithTripleEqual"] = ServerAction(
    "CompareNothingWithTripleEqual",
    "Change ==/!= to ===/!==.",
    CodeActionKinds.QuickFix,
    true,
    (x, _) -> StaticLint.is_in_fexpr(x, y -> StaticLint.haserror(y) && (StaticLint.errorof(y) in (StaticLint.NothingEquality, StaticLint.NothingNotEq))),
    double_to_triple_equal,
)

LSActions["AddLicenseIdentifier"] = ServerAction(
    "AddLicenseIdentifier",
    "Add SPDX license identifier.",
    missing,
    missing,
    (_, params) -> params.range.start.line == 0,
    add_license_header,
)
