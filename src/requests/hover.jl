JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params) = TextDocumentPositionParams(params)
function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    doc = server.documents[URI2(r.params.textDocument.uri)]
    x = get_expr(getcst(doc), get_offset(doc, r.params.position), 0, true)
    documentation = get_hover(x, "", server)
    
    send(JSONRPC.Response(r.id, Hover(MarkupContent(documentation), missing)), server)
end


function get_hover(x, documentation, server) documentation end

function get_hover(x::EXPR, documentation, server)
    if parentof(x) isa EXPR  && (kindof(x) === CSTParser.Tokens.END || kindof(x) === CSTParser.Tokens.RPAREN || kindof(x) === CSTParser.Tokens.RBRACE || kindof(x) === CSTParser.Tokens.RSQUARE)
        documentation = "Closes `$(typof(parentof(x)))`` expression."
    elseif CSTParser.isidentifier(x) && StaticLint.hasref(x)
        if refof(x) isa StaticLint.Binding
            documentation = get_hover(refof(x), documentation, server)
        elseif refof(x) isa SymbolServer.SymStore
            documentation = string(documentation, "\n", refof(x).doc)
        end
    end
    return documentation
end

function get_hover(b::StaticLint.Binding, documentation, server)
    if b.val isa EXPR
        if CSTParser.defines_function(b.val)
            while true
                if b.val isa EXPR 
                    if CSTParser.defines_function(b.val)
                        documentation = string(documentation, "\n", "```julia\n", Expr(CSTParser.get_sig(b.val)), "\n```")
                    elseif CSTParser.defines_datatype(b.val)
                        documentation = string(documentation, "\n", "```julia\n", Expr(b.val), "\n```")
                    end
                elseif b.val isa SymbolServer.SymStore
                    documentation = string(documentation, "\n", b.val.doc, "\n")
                else
                    break
                end
                if b.prev isa StaticLint.Binding && b.prev != b && (b.prev.type == getsymbolserver(server)["Core"].vals["Function"] || b.prev.type == getsymbolserver(server)["Core"].vals["DataType"] || b.prev.val isa Union{SymbolServer.FunctionStore,SymbolServer.DataTypeStore})
                    b = b.prev
                else
                    break
                end
            end
        else
            documentation = string(documentation, "\n", "```julia\n", Expr(b.val), "\n```")
        end
    elseif b.val isa SymbolServer.SymStore
        documentation = string(documentation, "\n", b.val.doc, "\n")
    elseif b.val isa StaticLint.Binding
        documentation = get_hover(b.val, documentation, server)
    end
    return documentation
end
