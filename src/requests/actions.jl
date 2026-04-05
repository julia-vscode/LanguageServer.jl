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
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    meta_dict, _ = get_meta_data(server, uri)
    offset = index_at(st, params.range.start)
    x = get_expr(jw_cst(server, uri), offset)
    arguments = Any[params.textDocument.uri, offset] # use the same arguments for all commands
    if x isa EXPR
        for (_, sa) in LSActions
            if sa.when(x, params, meta_dict)
                kind = sa.kind
                if sa.kind !== missing && sa.kind == CodeActionKinds.SourceOrganizeImports &&
                    server.clientInfo !== missing && occursin("code", lowercase(server.clientInfo.name))
                    # SourceOrganizeImports doesn't show up in the VS Code UI, so make this a
                    # RefactorRewrite instead
                    kind = CodeActionKinds.RefactorRewrite
                end
                action = CodeAction(
                    sa.desc, # title
                    kind,    # kind
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
        meta_dict, _ = get_meta_data(server, uri)
        x = get_expr(jw_cst(server, uri), offset)
        LSActions[params.command].handler(x, server, conn, meta_dict)
    end
end


function find_using_statement(x::EXPR, meta_dict)
    for ref in refof(x, meta_dict).refs
        if StaticLint.is_in_fexpr(ref, x -> headof(x) === :using || headof(x) === :import)
            return parentof(ref)
        end
    end
    return nothing
end

function explicitly_import_used_variables(x::EXPR, server, conn, meta_dict)
    !(refof(x, meta_dict) isa StaticLint.Binding && refof(x, meta_dict).val isa SymbolServer.ModuleStore) && return
    using_stmt = find_using_statement(x, meta_dict)
    using_stmt isa Nothing && return

    tdes = Dict{URI,TextDocumentEdit}()
    vars = Set{String}() # names that need to be imported
    # Find uses of `x` and mark edits
    for ref in refof(x, meta_dict).refs
        if parentof(ref) isa EXPR && CSTParser.is_getfield_w_quotenode(parentof(ref)) && parentof(ref).args[1] == ref
            childname = parentof(ref).args[2].args[1]
            hasref(childname, meta_dict) && refof(childname, meta_dict) isa StaticLint.Binding && continue # check this isn't the name of something being explictly overwritten
            !haskey(refof(x, meta_dict).val.vals, Symbol(valof(childname))) && continue # skip, perhaps mark as missing ref ?

            loc = get_file_loc(ref, server)
            loc === nothing && continue
            uri, offset = loc
            if !haskey(tdes, uri)
                tdes[uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[])
            end
            push!(tdes[uri].edits, TextEdit(jw_range(server, uri, offset .+ (0:parentof(ref).span)), valof(childname)))
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

        loc = get_file_loc(using_stmt, server)
        loc === nothing && return
        uri, offset = loc
        insertpos = get_next_line_offset(using_stmt, server)
        insertpos == -1 && return

        if !haskey(tdes, uri)
            tdes[uri] = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[])
        end
        push!(tdes[uri].edits, TextEdit(jw_range(server, uri, insertpos .+ (0:0)), string("using ", valof(x), ": ", join(vars, ", "), "\n")))
    else
        return
    end

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, collect(values(tdes)))))
end

is_single_line_func(x) = CSTParser.defines_function(x) && headof(x) !== :function

function expand_inline_func(x, server, conn, meta_dict)
    func = _get_parent_fexpr(x, is_single_line_func)
    length(func) < 3 && return
    sig = func.args[1]
    op = func.head
    body = func.args[2]
    if headof(body) == :block && length(body) == 1
        loc = get_file_loc(func, server)
        loc === nothing && return
        uri, offset = loc
        text = jw_text(server, uri)
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
            TextEdit(jw_range(server, uri, offset .+ (0:func.span)), string("function ", text[offset .+ (1:sig.span)], "\n    ", text[offset + sig.fullspan + op.fullspan .+ (1:body.span)], "\nend"))
        ])
        JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    elseif (headof(body) === :begin || CSTParser.isbracketed(body)) &&
        headof(body.args[1]) === :block && length(body.args[1]) > 0
        loc = get_file_loc(func, server)
        loc === nothing && return
        uri, offset = loc
        text = jw_text(server, uri)
        newtext = string("function ", text[offset .+ (1:sig.span)])
        blockoffset = offset + sig.fullspan + op.fullspan + body.trivia[1].fullspan
        for i = 1:length(body.args[1].args)
            newtext = string(newtext, "\n    ", text[blockoffset .+ (1:body.args[1].args[i].span)])
            blockoffset += body.args[1].args[i].fullspan
        end
        newtext = string(newtext, "\nend")
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[TextEdit(jw_range(server, uri, offset .+ (0:func.span)), newtext)])
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
function get_next_line_offset(x, server)
    loc = get_file_loc(x, server)
    loc === nothing && return -1
    uri, offset = loc
    text = jw_text(server, uri)
    # get next line after the expression
    insertpos = -1
    pos = 0
    for line in eachline(IOBuffer(text); keep=true)
        nextpos = pos + sizeof(line)
        if pos < offset + x.span <= nextpos
            insertpos = nextpos
            break
        end
        pos = nextpos
    end
    return insertpos
end

function reexport_package(x::EXPR, server, conn, meta_dict)
    (refof(x, meta_dict) isa SymbolServer.ModuleStore || refof(x, meta_dict).type === StaticLint.CoreTypes.Module || (refof(x, meta_dict).val isa StaticLint.Binding && refof(x, meta_dict).val.type === StaticLint.CoreTypes.Module)) || (refof(x, meta_dict).val isa SymbolServer.ModuleStore) || return
    mod = if refof(x, meta_dict) isa SymbolServer.ModuleStore
        refof(x, meta_dict)
    elseif refof(x, meta_dict).val isa SymbolServer.ModuleStore
        refof(x, meta_dict).val
    else
        return
    end
    using_stmt = parentof(x)
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, _ = loc
    insertpos = get_next_line_offset(using_stmt, server)
    insertpos == -1 && return

    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, insertpos .+ (0:0)), string("export ", join(sort([string(n) for (n, v) in mod.vals if StaticLint.isexportedby(n, mod)]), ", "), "\n"))
    ])

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

# TODO move to StaticL  int
# to be called where typof(x) === CSTParser.ModuleH/BareModule
function find_exported_names(x::EXPR, meta_dict)
    exported_vars = EXPR[]
    for i in 1:length(x.args[3].args)
        expr = x.args[3].args[i]
        if headof(expr) === :export
            for j = 2:length(expr)
                if CSTParser.isidentifier(expr.args[j]) && hasref(expr.args[j], meta_dict)
                    push!(exported_vars, expr.args[j])
                end
            end
        end
    end
    return exported_vars
end

function reexport_module(x::EXPR, server, conn, meta_dict)
    using_stmt = parentof(x)
    mod_expr = refof(x, meta_dict).val isa StaticLint.Binding ? refof(x, meta_dict).val.val : refof(x, meta_dict).val
    (mod_expr.args isa Nothing || length(mod_expr.args) < 3 || headof(mod_expr.args[3]) !== :block || mod_expr.args[3].args isa Nothing) && return # module expr without block
    # find export EXPR
    exported_names = find_exported_names(mod_expr, meta_dict)

    isempty(exported_names) && return
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, _ = loc
    insertpos = get_next_line_offset(using_stmt, server)
    insertpos == -1 && return
    names = filter!(s -> !isempty(s), collect(CSTParser.str_value.(exported_names)))
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, insertpos .+ (0:0)), string("export ", join(sort(names), ", "), "\n"))
    ])

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function wrap_block(x, server, type, conn) end
function wrap_block(x::EXPR, server, type, conn)
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, offset = loc
    if type == :if
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
            TextEdit(jw_range(server, uri, offset .+ (0:0)), "if CONDITION\n"),
            TextEdit(jw_range(server, uri, offset + x.span .+ (0:0)), "\nend")
        ])
    end

    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end


function is_fixable_missing_ref(x::EXPR, cac::CodeActionContext, meta_dict)
    if !isempty(cac.diagnostics) && any(startswith(d.message, "Missing reference") for d::Diagnostic in cac.diagnostics) && CSTParser.isidentifier(x)
        xname = StaticLint.valofid(x)
        tls = retrieve_toplevel_scope(x, meta_dict)
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

function applymissingreffix(x, server, conn, meta_dict)
    xname = StaticLint.valofid(x)
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, offset = loc
    tls = retrieve_toplevel_scope(x, meta_dict)
    if tls.modules !== nothing
        for (n, m) in tls.modules
            if (m isa SymbolServer.ModuleStore && haskey(m, Symbol(xname))) || (m isa StaticLint.Scope && StaticLint.scopehasbinding(m, xname))
                tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
                    TextEdit(jw_range(server, uri, offset .+ (0:0)), string(n, "."))
                ])
                JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
                return # TODO: This should probably offer multiple actions instead of just inserting the first hit
            end
        end
    end
end

function remove_farg_name(x, server, conn, meta_dict)
    x1 = StaticLint.get_parent_fexpr(x, x -> haserror(x, meta_dict) && errorof(x, meta_dict) == StaticLint.UnusedFunctionArgument)
    loc = get_file_loc(x1, server)
    loc === nothing && return
    uri, offset = loc
    if CSTParser.isdeclaration(x1)
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
                        TextEdit(jw_range(server, uri, offset .+ (0:x1.args[1].fullspan)), "")
                    ])
    else
        tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
                        TextEdit(jw_range(server, uri, offset .+ (0:x1.fullspan)), "_")
                    ])
    end
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function remove_unused_assignment_name(x, server, conn, meta_dict)
    x1 = StaticLint.get_parent_fexpr(x, x -> haserror(x, meta_dict) && errorof(x, meta_dict) == StaticLint.UnusedBinding && x isa EXPR && x.head === :IDENTIFIER)
    loc = get_file_loc(x1, server)
    loc === nothing && return
    uri, offset = loc
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
                    TextEdit(jw_range(server, uri, offset .+ (0:x1.span)), "_")
                ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function double_to_triple_equal(x, server, conn, meta_dict)
    x1 = StaticLint.get_parent_fexpr(x, y -> haserror(y, meta_dict) && errorof(y, meta_dict) in (StaticLint.NothingEquality, StaticLint.NothingNotEq))
    loc = get_file_loc(x1, server)
    loc === nothing && return
    uri, offset = loc
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, offset .+ (0:x1.span)), errorof(x1, meta_dict) == StaticLint.NothingEquality ? "===" : "!==")
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function get_spdx_header(server::LanguageServerInstance, uri::URI)
    # note the multiline flag - without that, we'd try to match the end of the _document_
    # instead of the end of the line.
    m = match(r"(*ANYCRLF)^# SPDX-License-Identifier:\h+((?:[\w\.-]+)(?:\h+[\w\.-]+)*)\h*$"m, jw_text(server, uri))
    return m === nothing ? m : String(m[1])
end

function in_same_workspace_folder(server::LanguageServerInstance, file1::URI, file2::URI)
    file1_str = uri2filepath(file1)
    file2_str = uri2filepath(file2)
    (file1_str === nothing || file2_str === nothing) && return false
    for ws in server.workspaceFolders
        if startswith(file1_str, ws) &&
           startswith(file2_str, ws)
           return true
       end
    end
    return false
end

function identify_short_identifier(server::LanguageServerInstance, file_uri::URI)
    # First look in tracked files (in the same workspace folder) for existing headers
    candidate_identifiers = Set{String}()
    for uri in JuliaWorkspaces.get_text_files(server.workspace)
        in_same_workspace_folder(server, file_uri, uri) || continue
        id = get_spdx_header(server, uri)
        id === nothing || push!(candidate_identifiers, id)
    end
    if length(candidate_identifiers) == 1
        return first(candidate_identifiers)
    else
        numerous = iszero(length(candidate_identifiers)) ? "no" : "multiple"
        @warn "Found $numerous candidates for the SPDX header from open files, falling back to LICENSE" Candidates=candidate_identifiers
    end

    # Fallback to looking for a license file in the same workspace folder
    candidate_files = String[]
    for dir in server.workspaceFolders
        for f in joinpath.(dir, ["LICENSE", "LICENSE.md"])
            if in_same_workspace_folder(server, file_uri, filepath2uri(f)) && safe_isfile(f)
                push!(candidate_files, f)
            end
        end
    end

    num_candidates = length(candidate_files)
    if num_candidates != 1
        iszero(num_candidates) && @warn "No candidate for licenses found, can't add identifier!"
        num_candidates > 1 && @warn "More than one candidate for licenses found, choose licensing manually!"
        return nothing
    end

    # This is just a heuristic, but should be OK since this is not something automated, and
    # the programmer will see directly if the wrong license is added.
    license_text = read(first(candidate_files), String)

    # Some known different spellings of some licences
    if contains(license_text, r"^\s*MIT\s+(\"?Expat\"?\s+)?Licen[sc]e")
        return "MIT"
    elseif contains(license_text, r"^\s*EUROPEAN\s+UNION\s+PUBLIC\s+LICEN[CS]E\s+v\."i)
        # the first version should be the EUPL version
        version = match(r"\d\.\d", license_text).match
        return "EUPL-$version"
    end

    @warn "A license was found, but could not be identified! Consider adding its licence identifier once to a file manually so that LanguageServer.jl can find it automatically next time." Location=first(candidate_files)
    return nothing
end

function add_license_header(x, server::LanguageServerInstance, conn, meta_dict)
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, _ = loc
    # does the current file already have a header?
    get_spdx_header(server, uri) === nothing || return # TODO: Would be nice to check this already before offering the action
    # no, so try to find one
    short_identifier = identify_short_identifier(server, uri)
    short_identifier === nothing && return
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, 0:0), "# SPDX-License-Identifier: $(short_identifier)\n\n")
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function organize_import_block(x, server, conn, meta_dict)
    if !StaticLint.is_in_fexpr(x, x -> headof(x) === :using || headof(x) === :import)
        return
    end

    # Collect all sibling blocks that are also using/import expressions
    siblings = EXPR[]
    using_stmt = StaticLint.get_parent_fexpr(x, y -> headof(y) === :using || headof(y) === :import)
    push!(siblings, using_stmt)
    block = using_stmt.parent
    if block !== nothing
        myidx = findfirst(x -> x === using_stmt, block.args)
        # Find older and younger siblings
        for direction in (-1, 1)
            i = direction
            while true
                s = get(block.args, myidx + i, nothing)
                if s isa EXPR && (s.head === :using || s.head === :import)
                    (direction == 1 ? push! : pushfirst!)(siblings, s)
                    i += direction
                else
                    break
                end
            end
        end
    end

    # Collect all modules and symbols
    using_mods = Set{String}()
    using_syms = Dict{String,Set{String}}()
    import_mods = Set{String}()
    import_syms = Dict{String,Set{String}}()

    # Joins e.g. [".", ".", "Foo", "Bar"] (from "using ..Foo.Bar") to "..Foo.Bar"
    function module_join(x)
        io = IOBuffer()
        for y in x.args[1:end-1]
            print(io, y.val)
            y.val == "." && continue
            print(io, ".")
        end
        print(io, x.args[end].val)
        return String(take!(io))
    end

    for s in siblings
        isusing = s.head === :using
        for a in s.args
            if CSTParser.is_colon(a.head)
                mod = module_join(a.args[1])
                set = get!(Set, isusing ? using_syms : import_syms, mod)
                for i in 2:length(a.args)
                    push!(set, join(y.val for y in a.args[i]))
                end
            elseif CSTParser.is_dot(a.head)
                push!(isusing ? using_mods : import_mods, module_join(a))
            elseif !isusing && headof(a) === :as
                push!(import_mods, join((module_join(a.args[1]), "as", a.args[2].val), " "))
            else
                error("Unexpected using/import expression.")
            end
        end
    end

    # Rejoin and sort
    # TODO: Currently regular string sorting is used, which roughly will correspond to
    #       BlueStyle (modules, types, ..., functions) since usually CamelCase is used for
    #       modules, types, etc, but possibly this can be improved by using information
    #       available from SymbolServer
    function sort_with_self_first(set, self)
        self′ = pop!(set, self, nothing)
        x = sort!(collect(set))
        if self′ !== nothing
            @assert self == self′
            pushfirst!(x, self)
        end
        return x
    end
    import_lines = String[]
    for m in import_mods
        push!(import_lines, "import " * m)
    end
    for (m, s) in import_syms
        push!(import_lines, "import " * m * ": " * join(sort_with_self_first(s, m), ", "))
    end
    using_lines = String[]
    for m in using_mods
        push!(using_lines, "using " * m)
    end
    for (m, s) in using_syms
        push!(using_lines, "using " * m * ": " * join(sort_with_self_first(s, m), ", "))
    end
    io = IOBuffer()
    join(io, sort!(import_lines), "\n")
    length(import_lines) > 0 && print(io, "\n\n")
    join(io, sort!(using_lines), "\n")
    str_to_fmt = String(take!(io))

    # Format the new string
    # TODO: Fetch user configuration?
    formatted = JuliaFormatter.format_text(str_to_fmt; join_lines_based_on_source=true)

    # Compute range of original blocks
    first_loc = get_file_loc(first(siblings), server)
    last_loc = get_file_loc(last(siblings), server)
    (first_loc === nothing || last_loc === nothing) && return
    uri, firstoffset = first_loc
    _, lastoffset = last_loc
    lastoffset += last(siblings).span

    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, firstoffset:lastoffset), formatted)
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
end

function is_string_literal(x::EXPR; inraw::Bool=false)
    if headof(x) === :STRING # CSTParser.isstringliteral(x) # TODO: """/raw""" strings not supported yet
        if x.parent isa EXPR && x.parent.head === :string
            # x is part of a string with interpolation
            return false
        end
        # Special handling if the string was found inside a macro
        if x.parent isa EXPR && CSTParser.ismacrocall(x.parent)
            if x.parent.args[1] isa EXPR && headof(x.parent.args[1]) === :IDENTIFIER &&
               endswith(x.parent.args[1].val, "_str") &&
               ncodeunits(x.parent.args[1].val) - ncodeunits("@_str") == x.parent.args[1].span
                # Disable for literal string macros, foo"...", but allow @foo_str "..."
                return inraw ? x.parent.args[1].val == "@raw_str" : false
            elseif x.parent.args[1] isa EXPR && headof(x.parent.args[1]) === :globalrefdoc
                # Disable action for docstrings
                return false
            else
                # Just some other macro, e.g. @show "hello", allow
            end
        end
        return inraw ? false : true
    end
    return false
end

if isdefined(Base, :escape_raw_string)
    using Base: escape_raw_string
else
    # https://github.com/JuliaLang/julia/pull/35309
    function escape_raw_string(io, str::AbstractString)
        escapes = 0
        for c in str
            if c == '\\'
                escapes += 1
            else
                if c == '"'
                    escapes = escapes * 2 + 1
                end
                while escapes > 0
                    write(io, '\\')
                    escapes -= 1
                end
                escapes = 0
                write(io, c)
            end
        end
        while escapes > 0
            write(io, '\\')
            write(io, '\\')
            escapes -= 1
        end
    end
end

function convert_to_raw(x, server, conn, meta_dict)
    is_string_literal(x) || return
    loc = get_file_loc(x, server)
    loc === nothing && return
    uri, offset = loc
    quotes = headof(x) === :TRIPLESTRING ? "\"\"\"" : "\"" # TODO: """ not supported yet
    raw = string("raw", quotes, sprint(escape_raw_string, valof(x)), quotes)
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, offset .+ (0:x.span)), raw)
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    return nothing
end

function convert_from_raw(x, server, conn, meta_dict)
    is_string_literal(x; inraw = true) || return
    xparent = x.parent
    loc = get_file_loc(xparent, server)
    loc === nothing && return
    uri, offset = loc
    quotes = headof(x) === :TRIPLESTRING ? "\"\"" : "" # TODO: raw""" not supported yet
    regular = quotes * repr(valof(x)) * quotes
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, offset .+ (0:xparent.span)), regular)
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    return nothing
end

# Checks if parent is a parent/grandparent/... of child
function is_parent_of(parent::EXPR, child::EXPR)
    while child isa EXPR
        if child == parent
            return true
        end
        child = child.parent
    end
    return false
end

function is_in_function_signature(x::EXPR, params, meta_dict=nothing; with_docstring=false)
    func = _get_parent_fexpr(x, CSTParser.defines_function)
    func === nothing && return false
    sig = func.args[1]
    if x.head === :FUNCTION || is_parent_of(sig, x)
        hasdoc = func.parent isa EXPR && func.parent.head === :macrocall && func.parent.args[1] isa EXPR &&
                 func.parent.args[1].head === :globalrefdoc
        return with_docstring == hasdoc
    end
    return false
end

function add_docstring_template(x, server, conn, meta_dict)
    is_in_function_signature(x, nothing) || return
    func = _get_parent_fexpr(x, CSTParser.defines_function)
    func === nothing && return
    func_loc = get_file_loc(func, server)
    func_loc === nothing && return
    uri, func_offset = func_loc
    sig = func.args[1]
    sig_loc = get_file_loc(sig, server)
    sig_loc === nothing && return
    _, sig_offset = sig_loc
    text = jw_text(server, uri)
    docstr = "\"\"\"\n    " * text[sig_offset .+ (1:sig.span)] * "\n\nTBW\n\"\"\"\n"
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, func_offset:func_offset), docstr)
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    return
end

function is_in_docstring_for_function(x::EXPR, params, meta_dict=nothing)
    return CSTParser.isstringliteral(x) && x.parent isa EXPR && headof(x.parent) === :macrocall &&
       length(x.parent.args) == 4 && x.parent.args[1] isa EXPR &&
       headof(x.parent.args[1]) === :globalrefdoc && CSTParser.defines_function(x.parent.args[4])
end

function update_docstring_sig(x, server, conn, meta_dict)
    if is_in_function_signature(x, nothing; with_docstring=true)
        func = _get_parent_fexpr(x, CSTParser.defines_function)
    elseif is_in_docstring_for_function(x, nothing)
        # The validity of this access is verified in is_in_docstring_for_function
        func = x.parent.args[4]
    else
        return
    end
    # Current docstring
    docstr_expr = func.parent.args[3]
    docstr = valof(docstr_expr)
    docstr_loc = get_file_loc(docstr_expr, server)
    docstr_loc === nothing && return
    uri, docstr_offset = docstr_loc
    text = jw_text(server, uri)
    # New signature in the code
    sig = func.args[1]
    sig_loc = get_file_loc(sig, server)
    sig_loc === nothing && return
    _, sig_offset = sig_loc
    sig_str = text[sig_offset .+ (1:sig.span)]
    # Heuristic for finding a signature in the current docstring
    reg = r"\A    .*$"m
    if (m = match(reg, valof(docstr_expr)); m !== nothing)
        docstr = replace(docstr, reg => string("    ", sig_str))
    else
        docstr = string("    ", sig_str, "\n\n", docstr)
    end
    newline = endswith(docstr, "\n") ? "" : "\n"
    # Rewrap in """"
    docstr = string("\"\"\"\n", docstr, newline, "\"\"\"")
    tde = TextDocumentEdit(VersionedTextDocumentIdentifier(uri, jw_version(server, uri)), TextEdit[
        TextEdit(jw_range(server, uri, docstr_offset .+ (0:docstr_expr.span)), docstr)
    ])
    JSONRPC.send(conn, workspace_applyEdit_request_type, ApplyWorkspaceEditParams(missing, WorkspaceEdit(missing, TextDocumentEdit[tde])))
    return
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
    (x, params, meta_dict) -> refof(x, meta_dict) isa StaticLint.Binding && refof(x, meta_dict).val isa SymbolServer.ModuleStore,
    explicitly_import_used_variables
)

LSActions["ExpandFunction"] = ServerAction(
    "ExpandFunction",
    "Expand function definition.",
    CodeActionKinds.Refactor,
    missing,
    (x, params, meta_dict) -> is_in_fexpr(x, is_single_line_func),
    expand_inline_func,
)

LSActions["FixMissingRef"] = ServerAction(
    "FixMissingRef",
    "Fix missing reference",
    missing,
    missing,
    (x, params, meta_dict) -> is_fixable_missing_ref(x, params.context, meta_dict),
    applymissingreffix,
)

LSActions["ReexportModule"] = ServerAction(
    "ReexportModule",
    "Re-export package variables.",
    missing,
    missing,
    (x, params, meta_dict) -> StaticLint.is_in_fexpr(x, x -> headof(x) === :using || headof(x) === :import) && (refof(x, meta_dict) isa StaticLint.Binding && (refof(x, meta_dict).type === StaticLint.CoreTypes.Module || (refof(x, meta_dict).val isa StaticLint.Binding && refof(x, meta_dict).val.type === StaticLint.CoreTypes.Module) || refof(x, meta_dict).val isa SymbolServer.ModuleStore) || refof(x, meta_dict) isa SymbolServer.ModuleStore),
    reexport_package,
)

LSActions["DeleteUnusedFunctionArgumentName"] = ServerAction(
    "DeleteUnusedFunctionArgumentName",
    "Delete name of unused function argument.",
    CodeActionKinds.QuickFix,
    missing,
    (x, params, meta_dict) -> StaticLint.is_in_fexpr(x, x -> haserror(x, meta_dict) && errorof(x, meta_dict) == StaticLint.UnusedFunctionArgument),
    remove_farg_name,
)

LSActions["ReplaceUnusedAssignmentName"] = ServerAction(
    "ReplaceUnusedAssignmentName",
    "Replace unused assignment name with _.",
    CodeActionKinds.QuickFix,
    missing,
    (x, params, meta_dict) -> StaticLint.is_in_fexpr(x, x -> haserror(x, meta_dict) && errorof(x, meta_dict) == StaticLint.UnusedBinding && x isa EXPR && x.head === :IDENTIFIER),
    remove_unused_assignment_name,
)

LSActions["CompareNothingWithTripleEqual"] = ServerAction(
    "CompareNothingWithTripleEqual",
    "Change ==/!= to ===/!==.",
    CodeActionKinds.QuickFix,
    true,
    (x, _, meta_dict) -> StaticLint.is_in_fexpr(x, y -> haserror(y, meta_dict) && (errorof(y, meta_dict) in (StaticLint.NothingEquality, StaticLint.NothingNotEq))),
    double_to_triple_equal,
)

LSActions["AddLicenseIdentifier"] = ServerAction(
    "AddLicenseIdentifier",
    "Add SPDX license identifier.",
    missing,
    missing,
    (_, params, meta_dict) -> params.range.start.line == 0,
    add_license_header,
)

LSActions["OrganizeImports"] = ServerAction(
    "OrganizeImports",
    "Organize `using` and `import` statements.",
    CodeActionKinds.SourceOrganizeImports,
    missing,
    (x, _, meta_dict) -> StaticLint.is_in_fexpr(x, x -> headof(x) === :using || headof(x) === :import),
    organize_import_block,
)

LSActions["RewriteAsRawString"] = ServerAction(
    "RewriteAsRawString",
    "Rewrite as raw string",
    CodeActionKinds.RefactorRewrite,
    missing,
    (x, _, meta_dict) -> is_string_literal(x),
    convert_to_raw,
)

LSActions["RewriteAsRegularString"] = ServerAction(
    "RewriteAsRegularString",
    "Rewrite as regular string",
    CodeActionKinds.RefactorRewrite,
    missing,
    (x, _, meta_dict) -> is_string_literal(x; inraw=true),
    convert_from_raw,
)

LSActions["AddDocstringTemplate"] = ServerAction(
    "AddDocstringTemplate",
    "Add docstring template for this method",
    missing,
    missing,
    is_in_function_signature,
    add_docstring_template,
)

LSActions["UpdateDocstringSignature"] = ServerAction(
    "UpdateDocstringSignature",
    "Update method signature in docstring",
    missing,
    missing,
    (args...) -> is_in_function_signature(args...; with_docstring=true) || is_in_docstring_for_function(args...),
    update_docstring_sig,
)
