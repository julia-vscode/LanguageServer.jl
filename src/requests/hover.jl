function textDocument_hover_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, URI2(params.textDocument.uri))
    x = get_expr1(getcst(doc), get_offset(doc, params.position))
    x isa EXPR && CSTParser.isoperator(x) && resolve_op_ref(x, server)
    documentation = get_hover(x, "", server)
    documentation = get_closer_hover(x, documentation)
    documentation = get_fcall_position(x, documentation)
    documentation = sanitize_docstring(documentation)

    return isempty(documentation) ? nothing : Hover(MarkupContent(documentation), missing)
end

function get_hover(x, documentation::String, server) documentation end

function get_hover(x::EXPR, documentation::String, server)
    if (CSTParser.isidentifier(x) || CSTParser.isoperator(x)) && StaticLint.hasref(x)
        r = refof(x)
        documentation = if r isa StaticLint.Binding
            get_hover(r, documentation, server)
        elseif r isa SymbolServer.SymStore
            get_hover(r, documentation, server)
        else
            documentation
        end
    end
    return documentation
end

function get_hover(b::StaticLint.Binding, documentation::String, server)
    if b.val isa EXPR
        if CSTParser.defines_function(b.val) || CSTParser.defines_datatype(b.val)
            documentation = get_func_hover(b, documentation, server)
        else
            try
                documentation = if binding_has_preceding_docs(b)
                    string(documentation, Expr(parentof(b.val).args[3]))
                elseif const_binding_has_preceding_docs(b)
                    string(documentation, Expr(parentof(parentof(b.val)).args[3]))
                else
                    documentation
                end
                documentation = string(documentation, "```julia\n", Expr(b.val), "\n```\n")
            catch err
                doc1, offset1 = get_file_loc(b.val)
                throw(LSHoverError(string("get_hover failed to convert the following to coode: ", String(codeunits(get_text(doc1))[offset1 .+ (1:b.val.span)]))))
            end
        end
    elseif b.val isa SymbolServer.SymStore
        documentation = get_hover(b.val, documentation, server)
    elseif b.val isa StaticLint.Binding
        documentation = get_hover(b.val, documentation, server)
    end
    return documentation
end

# print(io, x::SymStore) methods are defined in SymbolServer
function get_hover(b::SymbolServer.SymStore, documentation::String, server)
    if !isempty(b.doc)
        documentation = string(documentation, b.doc, "\n")
    end
    documentation = string(documentation, "```julia\n", b, "\n```")
end

function get_hover(f::SymbolServer.FunctionStore, documentation::String, server)
    if !isempty(f.doc)
        documentation = string(documentation, f.doc, "\n")
    end

    documentation = string(documentation, "`$(f.name)` is a `Function`.\n")
    nm = length(f.methods)
    documentation = string(documentation, "**$(nm)** method", nm == 1 ? "" : "s", " for function ", '`', f.name, '`', '\n')
    for m in f.methods
        io = IOBuffer()
        print(io, m.name, "(")
        nsig = length(m.sig)
        for (i, sig) = enumerate(m.sig)
            if sig[1] ≠ Symbol("#unused#")
                print(io, sig[1])
            end
            print(io, "::", sig[2])
            i ≠ nsig && print(io, ", ")
        end
        print(io, ")")
        sig = String(take!(io))
        mod = m.mod
        text = string(m.file, ':', m.line)
        # VSCode markdown doesn't seem to be able to handle line number in links
        # link = string(normpath(m.file), ':', m.line)
        link = normpath(m.file)
        documentation = string(documentation, "- `$(sig)` in `$(mod)` at [$(text)]($(link))", '\n')
    end
    return documentation
end


get_func_hover(x, documentation, server, visited=nothing) = documentation
get_func_hover(x::SymbolServer.SymStore, documentation, server, visited=nothing) = get_hover(x, documentation, server)

function get_func_hover(b::StaticLint.Binding, documentation, server, visited=StaticLint.Binding[])
    if b in visited                                      # TODO: remove
        # throw(LSInfiniteLoop("Possible infinite loop.")) # TODO: remove
        # There is a cycle in the links between Bindings. Root cause is in StaticLint but there is no reason to allow it to crash the language server. If we have done a complete circuit here then we have all the information we need and can return.
        return documentation
    else                                                 # TODO: remove
        push!(visited, b)                                # TODO: remove
    end                                                  # TODO: remove
    if b.val isa EXPR
        documentation = if binding_has_preceding_docs(b)
            # Binding has preceding docs so use them..
            string(documentation, Expr(parentof(b.val).args[3]))
        elseif const_binding_has_preceding_docs(b)
            string(documentation, Expr(parentof(parentof(b.val)).args[3]))
        else
            documentation
        end
        if CSTParser.defines_function(b.val)
            documentation = string(documentation, "```julia\n", Expr(CSTParser.get_sig(b.val)), "\n```\n")
        elseif CSTParser.defines_datatype(b.val)
            documentation = string(documentation, "```julia\n", Expr(b.val), "\n```\n")
        end
    elseif b.val isa SymbolServer.SymStore
        return get_hover(b.val, documentation, server)
    end
    if b.prev isa StaticLint.Binding && (b.prev.type == StaticLint.CoreTypes.Function || b.prev.type == StaticLint.CoreTypes.DataType || b.prev.val isa Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}) || (b.prev isa SymbolServer.FunctionStore || b.prev isa SymbolServer.DataTypeStore)
        return get_func_hover(b.prev, documentation, server, visited)
    end
    return documentation
end

binding_has_preceding_docs(b::StaticLint.Binding) = expr_has_preceding_docs(b.val)

function const_binding_has_preceding_docs(b::StaticLint.Binding)
    p = parentof(b.val)
    is_const_expr(p) && expr_has_preceding_docs(p)
end

expr_has_preceding_docs(x) = false
expr_has_preceding_docs(x::EXPR) = is_doc_expr(parentof(x))

is_const_expr(x) = false
is_const_expr(x::EXPR) = headof(x) === :const

is_doc_expr(x) = false
function is_doc_expr(x::EXPR)
    return CSTParser.ismacrocall(x) &&
        length(x.args) == 3 &&
        headof(x.args[1]) === :globalrefdoc &&
        CSTParser.isstring(x.args[3])
end

get_fcall_position(x, documentation, visited=nothing) = documentation

function get_fcall_position(x::EXPR, documentation, visited=EXPR[])
    if xor in visited                                      # TODO: remove
        throw(LSInfiniteLoop("Possible infinite loop.")) # TODO: remove
    else                                                 # TODO: remove
        push!(visited, x)                                # TODO: remove
    end                                                  # TODO: remove
    if parentof(x) isa EXPR
        if CSTParser.iscall(parentof(x))
            call_counts = StaticLint.call_nargs(parentof(x))
            call_counts[1] < 5 && return documentation
            arg_i = 0
            for (i, arg) = enumerate(parentof(x))
                if arg == x
                    arg_i = div(i - 1, 2)
                    break
                end
            end
            arg_i == 0 && return documentation
            fname = CSTParser.get_name(parentof(x))
            if StaticLint.hasref(fname) &&
                (refof(fname) isa StaticLint.Binding && refof(fname).val isa EXPR && CSTParser.defines_struct(refof(fname).val) && StaticLint.struct_nargs(refof(fname).val)[1] == call_counts[1])
                dt_ex = refof(fname).val
                args = dt_ex.args[3]
                args.args === nothing || arg_i > length(args.args) && return documentation
                _fieldname = CSTParser.str_value(CSTParser.get_arg_name(args.args[arg_i]))
                documentation = string("Datatype field `$_fieldname` of $(CSTParser.str_value(CSTParser.get_name(dt_ex)))", "\n", documentation)
            elseif StaticLint.hasref(fname) && (refof(fname) isa SymbolServer.DataTypeStore || refof(fname) isa StaticLint.Binding && refof(fname).val isa SymbolServer.DataTypeStore)
                dts = refof(fname) isa StaticLint.Binding ? refof(fname).val : refof(fname)
                if length(dts.fieldnames) == call_counts[1] && arg_i <= length(dts.fieldnames)
                    documentation = string("Datatype field `$(dts.fieldnames[arg_i])`", "\n", documentation)
                end
            else
                documentation = string("Argument $arg_i of $(call_counts[1]) in call to `", CSTParser.str_value(fname), "`\n", documentation)
            end
            return documentation
        else
            return get_fcall_position(parentof(x), documentation, visited)
        end
    end
    return documentation
end

# info on what expression the current token (e.g. a ], ), `end`, etc.)
get_closer_hover(x, documentation) = documentation
function get_closer_hover(x::EXPR, documentation)
    if parentof(x) isa EXPR
        if headof(x) === :END
            if headof(parentof(x)) === :function
                documentation = string(documentation, "Closes function definition for `", Expr(CSTParser.get_sig(parentof(x))), "`\n")
            elseif CSTParser.defines_module(parentof(x)) && length(parentof(x).args) > 1
                documentation = string(documentation, "Closes module definition for `", Expr(parentof(x).args[2]), "`\n")
            elseif CSTParser.defines_struct(parentof(x))
                documentation = string(documentation, "Closes struct definition for `", Expr(CSTParser.get_sig(parentof(x))), "`\n")
            elseif headof(parentof(x)) === :for && length(parentof(x).args) > 2
                documentation = string(documentation, "Closes for-loop expression over `", Expr(parentof(x).args[2]), "`\n")
            elseif headof(parentof(x)) === :while && length(parentof(x).args) > 2
                documentation = string(documentation, "Closes while-loop expression over `", Expr(parentof(x).args[2]), "`\n")
            else
                documentation = "Closes `$(headof(parentof(x)))` expression."
            end
        elseif headof(x) === :RPAREN
            if CSTParser.iscall(parentof(x)) && length(parentof(x).args) > 0
                documentation = string(documentation, "Closes call of ", Expr(parentof(x).args[1]), "\n")
            end
        end
    end
    return documentation
end
