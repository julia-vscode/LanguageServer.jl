function textDocument_hover_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, params.textDocument.uri)
    env = getenv(doc, server)
    x = get_expr1(getcst(doc), get_offset(doc, params.position))
    x isa EXPR && CSTParser.isoperator(x) && resolve_op_ref(x, env)
    documentation = get_hover(x, "", server, x, env)
    documentation = get_closer_hover(x, documentation)
    documentation = get_fcall_position(x, documentation)
    documentation = sanitize_docstring(documentation)

    return isempty(documentation) ? nothing : Hover(MarkupContent(documentation), missing)
end

get_hover(x, documentation::String, server, expr, env) = documentation

function get_hover(x::EXPR, documentation::String, server, expr, env)
    if (CSTParser.isidentifier(x) || CSTParser.isoperator(x)) && StaticLint.hasref(x)
        r = refof(x)
        documentation = if r isa StaticLint.Binding
            get_hover(r, documentation, server, expr, env)
        elseif r isa SymbolServer.SymStore
            get_hover(r, documentation, server, expr, env)
        else
            documentation
        end
    end
    return documentation
end

function get_tooltip(b::StaticLint.Binding, documentation::String, server, expr = nothing, env = nothing; show_definition = false)
    if b.val isa StaticLint.Binding
        documentation = get_hover(b.val, documentation, server, expr, env)
    elseif b.val isa EXPR
        if CSTParser.defines_function(b.val) || CSTParser.defines_datatype(b.val)
            documentation = get_func_hover(b, documentation, server, expr, env)
            for r in b.refs
                method = StaticLint.get_method(r)
                if method isa EXPR
                    documentation = get_preceding_docs(method, documentation)
                    if CSTParser.defines_function(method)
                        documentation = string(ensure_ends_with(documentation), "```julia\n", to_codeobject(CSTParser.get_sig(method)), "\n```\n")
                    elseif CSTParser.defines_datatype(method)
                        documentation = string(ensure_ends_with(documentation), "```julia\n", to_codeobject(method), "\n```\n")
                    end
                elseif method isa SymbolServer.SymStore
                    documentation = get_hover(method, documentation, server, expr, env)
                end
            end
        else
            documentation = try
                if show_definition
                    documentation = string(
                        ensure_ends_with(documentation),
                        """```julia
                        $(get_typed_definition(b))
                        ```\n
                        """
                    )
                end
                documentation = if binding_has_preceding_docs(b)
                    string(documentation, to_codeobject(maybe_get_doc_expr(b.val).args[3]))
                elseif const_binding_has_preceding_docs(b)
                    string(documentation, to_codeobject(maybe_get_doc_expr(parentof(b.val)).args[3]))
                else
                    documentation
                end
            catch err
                @error "get_hover failed to convert Expr" exception = (err, catch_backtrace())
                throw(LSHoverError(string("get_hover failed to convert Expr")))
            end
        end
    elseif b.val isa SymbolServer.SymStore
        documentation = get_hover(b.val, documentation, server, expr, env)
    end
    return documentation
end

get_hover(b::StaticLint.Binding, documentation::String, server, expr, env) =
    get_tooltip(b, documentation, server, expr, env; show_definition = true)

get_typed_definition(b) = _completion_type(b)
get_typed_definition(b::StaticLint.Binding) =
    prettify_expr(maybe_insert_type_declaration(b))

function maybe_insert_type_declaration(b::StaticLint.Binding)
    if b.val isa CSTParser.EXPR
        maybe_insert_type_declaration(to_codeobject(b.val), _completion_type(b))
    else
        _completion_type(b)
    end
end

maybe_insert_type_declaration(_, type) = coalesce(type, "")
maybe_insert_type_declaration(s::Symbol, ::Missing) = s
maybe_insert_type_declaration(s::Symbol, type) = Expr(
    :(::),
    s,
    Symbol(type)
)
maybe_insert_type_declaration(ex::Expr, ::Missing) = ex
function maybe_insert_type_declaration(ex::Expr, type)
    if ex.head === :(=) && length(ex.args) >= 2
        lhs = ex.args[1]
        if !(lhs isa Expr && lhs.head === :(::))
            ex.args[1] = Expr(
                :(::),
                lhs,
                Symbol(type)
            )
        end
    end
    return ex
end

function _completion_type(b::StaticLint.Binding)
    typ = _inner_completion_type(b.type)
    typ === missing && return missing
    if startswith(typ, "Core.")
        typ = typ[6:end]
    end
    return Symbol(typ)
end
_completion_type(_) = missing

_inner_completion_type(b::SymbolServer.DataTypeStore) = sprint(print, b.name)
_inner_completion_type(b::StaticLint.Binding) = sprint(print, to_codeobject(b.name))
_inner_completion_type(_) = missing

function prettify_expr(ex::Expr)
    if ex.head === :kw && length(ex.args) == 2
        string(ex.args[1], " = ", ex.args[2])
    else
        string(ex)
    end
end

prettify_expr(ex) = string(ex)

# print(io, x::SymStore) methods are defined in SymbolServer
function get_hover(b::SymbolServer.SymStore, documentation::String, server, expr, env)
    if !isempty(b.doc)
        documentation = string(documentation, b.doc, "\n")
    end
    documentation = string(documentation, "```julia\n", b, "\n```")
end

function get_hover(f::SymbolServer.FunctionStore, documentation::String, server, expr, env)
    if !isempty(f.doc)
        documentation = string(documentation, f.doc, "\n\n")
    end

    if expr !== nothing && env !== nothing
        tls = StaticLint.retrieve_toplevel_scope(expr)
        itr = func -> StaticLint.iterate_over_ss_methods(f, tls, env, func)
    else
        itr = func -> begin
            for m in f.methods
                func(m)
            end
        end
    end

    method_count = 0
    totalio = IOBuffer()
    itr() do m
        method_count += 1

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

        path = replace(m.file, "\\" => "\\\\")
        text = string(path, ':', m.line)
        link = text

        if server.clientInfo !== missing && isabspath(m.file)
            clientname = lowercase(server.clientInfo.name)
            if occursin("code", clientname) || occursin("sublime", clientname)
                link = string(filepath2uri(m.file), "#", m.line)
                text = string(basename(path), ':', m.line)
            end
        end
        println(totalio, "$(method_count). `$(sig)` in `$(m.mod)` at [$(text)]($(link))\n")
        return false
    end

    documentation = string(
        documentation,
        "`$(f.name)` is a function with **$(method_count)** method$(method_count == 1 ? "" : "s")\n",
        String(take!(totalio))
    )

    return documentation
end

get_func_hover(x, documentation, server, expr, env) = documentation
get_func_hover(x::SymbolServer.SymStore, documentation, server, expr, env) = get_hover(x, documentation, server, expr, env)

function get_preceding_docs(expr::EXPR, documentation)
    if expr_has_preceding_docs(expr)
        string(documentation, to_codeobject(maybe_get_doc_expr(expr).args[3]))
    elseif is_const_expr(parentof(expr)) && expr_has_preceding_docs(parentof(expr))
        string(documentation, to_codeobject(maybe_get_doc_expr(parentof(expr)).args[3]))
    else
        documentation
    end
end

ensure_ends_with(s, c = "\n") = endswith(s, c) ? s : string(s, c)

binding_has_preceding_docs(b::StaticLint.Binding) = expr_has_preceding_docs(b.val)

function const_binding_has_preceding_docs(b::StaticLint.Binding)
    p = parentof(b.val)
    is_const_expr(p) && expr_has_preceding_docs(p)
end

function maybe_get_doc_expr(x)
    # The expression may be nested in any number of macros
    while CSTParser.hasparent(x) &&
        CSTParser.ismacrocall(parentof(x))
        x = parentof(x)
        headof(x.args[1]) === :globalrefdoc && return x
    end
    return x
end

expr_has_preceding_docs(x) = false
expr_has_preceding_docs(x::EXPR) = is_doc_expr(maybe_get_doc_expr(x))

is_const_expr(x) = false
is_const_expr(x::EXPR) = headof(x) === :const

is_doc_expr(x) = false
function is_doc_expr(x::EXPR)
    return CSTParser.ismacrocall(x) &&
           length(x.args) == 4 &&
           headof(x.args[1]) === :globalrefdoc &&
           CSTParser.isstring(x.args[3])
end

get_fcall_position(x, documentation, visited=nothing) = documentation

function get_fcall_position(x::EXPR, documentation, visited=Set{EXPR}())
    if x in visited                                      # TODO: remove
        throw(LSInfiniteLoop("Possible infinite loop.")) # TODO: remove
    else                                                 # TODO: remove
        push!(visited, x)                                # TODO: remove
    end                                                  # TODO: remove
    if parentof(x) isa EXPR
        if CSTParser.iscall(parentof(x))
            minargs, _, _ = StaticLint.call_nargs(parentof(x))
            arg_i = 0
            for (i, arg) in enumerate(parentof(x))
                if arg == x
                    arg_i = div(i - 1, 2)
                    break
                end
            end

            # hovering over the function name, so we might as well check the parent
            if arg_i == 0
                return get_fcall_position(parentof(x), documentation, visited)
            end

            minargs < 4 && return documentation

            fname = CSTParser.get_name(parentof(x))
            if StaticLint.hasref(fname) &&
               (refof(fname) isa StaticLint.Binding && refof(fname).val isa EXPR && CSTParser.defines_struct(refof(fname).val) && StaticLint.struct_nargs(refof(fname).val)[1] == minargs)
                dt_ex = refof(fname).val
                args = dt_ex.args[3]
                args.args === nothing || arg_i > length(args.args) && return documentation
                _fieldname = CSTParser.str_value(CSTParser.get_arg_name(args.args[arg_i]))
                documentation = string("Datatype field `$_fieldname` of $(CSTParser.str_value(CSTParser.get_name(dt_ex)))", "\n", documentation)
            elseif StaticLint.hasref(fname) && (refof(fname) isa SymbolServer.DataTypeStore || refof(fname) isa StaticLint.Binding && refof(fname).val isa SymbolServer.DataTypeStore)
                dts = refof(fname) isa StaticLint.Binding ? refof(fname).val : refof(fname)
                if length(dts.fieldnames) == minargs && arg_i <= length(dts.fieldnames)
                    documentation = string("Datatype field `$(dts.fieldnames[arg_i])`", "\n", documentation)
                end
            else
                callname = if CSTParser.is_getfield(fname)
                    CSTParser.str_value(fname.args[1]) * "." * CSTParser.str_value(CSTParser.get_rhs_of_getfield(fname))
                else
                    CSTParser.str_value(fname)
                end
                documentation = string("Argument $arg_i of $(minargs) in call to `", callname, "`\n", documentation)
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
                documentation = string(documentation, "Closes function definition for `", to_codeobject(CSTParser.get_sig(parentof(x))), "`\n")
            elseif CSTParser.defines_module(parentof(x)) && length(parentof(x).args) > 1
                documentation = string(documentation, "Closes module definition for `", to_codeobject(parentof(x).args[2]), "`\n")
            elseif CSTParser.defines_struct(parentof(x))
                documentation = string(documentation, "Closes struct definition for `", to_codeobject(CSTParser.get_sig(parentof(x))), "`\n")
            elseif headof(parentof(x)) === :for && length(parentof(x).args) > 2
                documentation = string(documentation, "Closes for-loop expression over `", to_codeobject(parentof(x).args[2]), "`\n")
            elseif headof(parentof(x)) === :while && length(parentof(x).args) > 2
                documentation = string(documentation, "Closes while-loop expression over `", to_codeobject(parentof(x).args[2]), "`\n")
            else
                documentation = "Closes `$(headof(parentof(x)))` expression."
            end
        end
    end
    return documentation
end
