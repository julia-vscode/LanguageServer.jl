JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params) = TextDocumentPositionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    x = get_expr(getcst(doc), get_offset(doc, r.params.position), 0, true)
    documentation = get_hover(x, "", server)
    documentation = get_fcall_position(x, documentation)

    send(JSONRPC.Response(r.id, Hover(MarkupContent(documentation), missing)), server)
end


function get_hover(x, documentation, server) documentation end

function get_hover(x::EXPR, documentation, server)
    if parentof(x) isa EXPR  && (kindof(x) === CSTParser.Tokens.END || kindof(x) === CSTParser.Tokens.RPAREN || kindof(x) === CSTParser.Tokens.RBRACE || kindof(x) === CSTParser.Tokens.RSQUARE)
        documentation = "Closes `$(typof(parentof(x)))` expression."
    elseif CSTParser.isidentifier(x) && StaticLint.hasref(x)
        if refof(x) isa StaticLint.Binding
            documentation = get_hover(refof(x), documentation, server)
        elseif refof(x) isa SymbolServer.SymStore
            documentation = string(documentation, refof(x).doc)
        end
    end
    return documentation
end

function get_hover(b::StaticLint.Binding, documentation, server)
    if b.val isa EXPR
        if CSTParser.defines_function(b.val)
            while true
                if b.val isa EXPR 
                    if parentof(b.val) isa EXPR && typof(parentof(b.val)) === CSTParser.MacroCall && length(parentof(b.val).args) == 3 && typof(parentof(b.val).args[1]) === CSTParser.GlobalRefDoc && CSTParser.isstring(parentof(b.val).args[2])
                        # Binding has preceding docs so use them..
                        documentation = string(documentation, Expr(parentof(b.val).args[2]))
                    elseif CSTParser.defines_function(b.val)
                        documentation = string(documentation, "```julia\n", Expr(CSTParser.get_sig(b.val)), "\n```\n")
                    elseif CSTParser.defines_datatype(b.val)
                        documentation = string(documentation, "```julia\n", Expr(b.val), "\n```\n")
                    end
                elseif b.val isa SymbolServer.SymStore
                    documentation = string(documentation, b.val.doc)
                else
                    break
                end
                if b.prev isa StaticLint.Binding && b.prev != b && (b.prev.type == StaticLint.CoreTypes.Function || b.prev.type == StaticLint.CoreTypes.DataType || b.prev.val isa Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore})
                    b = b.prev
                else
                    break
                end
            end
        else
            documentation = string(documentation, "```julia\n", Expr(b.val), "\n```\n")
        end
    elseif b.val isa SymbolServer.SymStore
        documentation = string(documentation, b.val.doc)
    elseif b.val isa StaticLint.Binding
        documentation = get_hover(b.val, documentation, server)
    end
    return documentation
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
                _fieldname = CSTParser.str_value(CSTParser.get_arg_name(args.args[arg_i]))
                documentation = string("Datatype field `$_fieldname` of $(CSTParser.str_value(CSTParser.get_name(dt_ex)))", "\n", documentation)
            elseif StaticLint.hasref(fname) && (refof(fname) isa SymbolServer.DataTypeStore || refof(fname) isa StaticLint.Binding && refof(fname).val isa SymbolServer.DataTypeStore)
                dts = refof(fname) isa StaticLint.Binding ? refof(fname).val : refof(fname)
                if length(dts.fields) == call_counts[1]
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
