JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params) = TextDocumentPositionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    doc = getdocument(server, URI2(r.params.textDocument.uri))
    x = get_expr1(getcst(doc), get_offset(doc, r.params.position))
    documentation = get_hover(x, "", server)
    documentation = get_closer_hover(x, documentation)
    documentation = get_fcall_position(x, documentation)
    documentation = sanitize_docstring(documentation)

    return Hover(MarkupContent(documentation), missing)
end

function get_hover(x, documentation::String, server) documentation end

function get_hover(x::EXPR, documentation::String, server)
    if CSTParser.isidentifier(x) && StaticLint.hasref(x)
        if refof(x) isa StaticLint.Binding
            documentation = get_hover(refof(x), documentation, server)
        elseif refof(x) isa SymbolServer.SymStore
            documentation = get_hover(refof(x), documentation, server)
        end
    end
    return documentation
end

function get_hover(b::StaticLint.Binding, documentation::String, server)
    if b.val isa EXPR
        if CSTParser.defines_function(b.val)
            while true
                if b isa SymbolServer.SymStore
                    documentation = get_hover(b, documentation, server)
                    break
                elseif b.val isa EXPR 
                    if parentof(b.val) isa EXPR && typof(parentof(b.val)) === CSTParser.MacroCall && length(parentof(b.val).args) == 3 && typof(parentof(b.val).args[1]) === CSTParser.GlobalRefDoc && CSTParser.isstring(parentof(b.val).args[2])
                        # Binding has preceding docs so use them..
                        documentation = string(documentation, Expr(parentof(b.val).args[2]))
                    elseif CSTParser.defines_function(b.val)
                        documentation = string(documentation, "```julia\n", Expr(CSTParser.get_sig(b.val)), "\n```\n")
                    elseif CSTParser.defines_datatype(b.val)
                        documentation = string(documentation, "```julia\n", Expr(b.val), "\n```\n")
                    end
                elseif b.val isa SymbolServer.SymStore
                    documentation = get_hover(b.val, documentation, server)
                else
                    break
                end
                if b.prev isa StaticLint.Binding && b.prev != b && (b.prev.type == StaticLint.CoreTypes.Function || b.prev.type == StaticLint.CoreTypes.DataType || b.prev.val isa Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore}) || (b.prev isa SymbolServer.FunctionStore || b.prev isa SymbolServer.DataTypeStore)
                    b = b.prev
                else
                    break
                end
            end
        else
            documentation = string(documentation, "```julia\n", Expr(b.val), "\n```\n")
        end
    elseif b.val isa SymbolServer.SymStore
        documentation = get_hover(b.val, documentation, server)
    elseif b.val isa StaticLint.Binding
        documentation = get_hover(b.val, documentation, server)
    end
    return documentation
end

function get_hover(b::SymbolServer.SymStore, documentation::String, server)
    if !isempty(b.doc)
        documentation = string(documentation, b.doc, "\n")
    end
    documentation = string(documentation, "```julia\n", b, "\n```")
    # print(io, x::SymStore) methods are defined in SymbolServer
end

get_fcall_position(x, documentation) = documentation
function get_fcall_position(x::EXPR, documentation)
    while parentof(x) isa EXPR
        if typof(parentof(x)) === CSTParser.Call
            call_counts = StaticLint.call_nargs(parentof(x))
            call_counts[1] < 5 && return documentation
            arg_i = 0
            for i = 1:length(parentof(x).args)
                arg = parentof(x).args[i]
                if arg == x
                    arg_i = div(i-1, 2)
                end
            end
            arg_i == 0 && return documentation
            fname = CSTParser.get_name(parentof(x))
            if StaticLint.hasref(fname) && 
                (refof(fname) isa StaticLint.Binding && refof(fname).val isa EXPR && CSTParser.defines_struct(refof(fname).val) && StaticLint.struct_nargs(refof(fname).val)[1] == call_counts[1])
                dt_ex = refof(fname).val
                args = CSTParser.defines_mutable(dt_ex) ? dt_ex.args[4] : dt_ex.args[3]
                args.args === nothing || arg_i > length(args.args) && return documentation
                _fieldname = CSTParser.str_value(CSTParser.get_arg_name(args.args[arg_i]))
                documentation = string("Datatype field `$_fieldname` of $(CSTParser.str_value(CSTParser.get_name(dt_ex)))", "\n", documentation)
            elseif StaticLint.hasref(fname) && (refof(fname) isa SymbolServer.DataTypeStore || refof(fname) isa StaticLint.Binding && refof(fname).val isa SymbolServer.DataTypeStore)
                dts = refof(fname) isa StaticLint.Binding ? refof(fname).val : refof(fname)
                if length(dts.fields) == call_counts[1] && arg_i <= length(dts.fields)
                    documentation = string("Datatype field `$(dts.fields[arg_i])`", "\n", documentation)
                end
            else
                documentation = string("Argument $arg_i of $(call_counts[1]) in call to `", CSTParser.str_value(fname), "`\n", documentation)
            end
            return documentation
        end
        x = parentof(x)
    end
    return documentation
end

# info on what expression the current token (e.g. a ], ), `end`, etc.)
get_closer_hover(x, documentation) = documentation
function get_closer_hover(x::EXPR, documentation)
    if parentof(x) isa EXPR 
        if kindof(x) === CSTParser.Tokens.END
            if typof(parentof(x)) === CSTParser.FunctionDef
                documentation = string(documentation, "Closes function definition for `", Expr(CSTParser.get_sig(parentof(x))), "`\n")
            elseif (typof(parentof(x)) === CSTParser.ModuleH || typof(parentof(x)) === CSTParser.ModuleH) && length(parentof(x).args) > 1
                    documentation = string(documentation, "Closes module definition for `", Expr(parentof(x).args[2]), "`\n")
            elseif typof(parentof(x)) === CSTParser.Struct
                documentation = string(documentation, "Closes struct definition for `", Expr(CSTParser.get_sig(parentof(x))), "`\n")
            elseif typof(parentof(x)) === CSTParser.Mutable
                documentation = string(documentation, "Closes mutable struct definition for `", Expr(CSTParser.get_sig(parentof(x))), "`\n")
            elseif typof(parentof(x)) === CSTParser.For && length(parentof(x).args) > 2
                documentation = string(documentation, "Closes for-loop expression over `", Expr(parentof(x).args[2]), "`\n")
            elseif typof(parentof(x)) === CSTParser.While && length(parentof(x).args) > 2
                documentation = string(documentation, "Closes while-loop expression over `", Expr(parentof(x).args[2]), "`\n")
            else
                documentation = "Closes `$(typof(parentof(x)))` expression."
            end
        elseif kindof(x) === CSTParser.Tokens.RPAREN
            if typof(parentof(x)) === CSTParser.Call && length(parentof(x).args) > 0
                documentation = string(documentation, "Closes call of ", Expr(parentof(x).args[1]), "\n")
            end
        elseif kindof(x) === CSTParser.Tokens.RBRACE || kindof(x) === CSTParser.Tokens.RSQUARE
        end
    end
    return documentation
end
