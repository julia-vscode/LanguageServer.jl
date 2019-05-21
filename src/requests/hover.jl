function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/hover")}}, params)
    return TextDocumentPositionParams(params)
end

function process(r::JSONRPC.Request{Val{Symbol("textDocument/hover")},TextDocumentPositionParams}, server)
    if !haskey(server.documents, URI2(r.params.textDocument.uri))
        send(JSONRPC.Response(r.id, CancelParams(r.id)), server)
        return
    end
    documentation = Any[]
    doc = server.documents[URI2(r.params.textDocument.uri)]
    x = get_expr(getcst(doc), get_offset(doc, r.params.position))
    
    get_hover(x, documentation, server)
    
    send(JSONRPC.Response(r.id, Hover(unique(documentation))), server)
end


function get_hover(x, documentation, server) end

function get_hover(x::EXPR, documentation, server)
    if x.parent isa EXPR  && (x.kind === CSTParser.Tokens.END || x.kind === CSTParser.Tokens.RPAREN || x.kind === CSTParser.Tokens.RBRACE || x.kind === CSTParser.Tokens.RSQUARE)
        push!(documentation, MarkedString("Closes $(x.parent.typ) expression."))
    elseif CSTParser.isidentifier(x) && StaticLint.hasref(x)
        if x.ref isa StaticLint.Binding
            get_hover(x.ref, documentation, server)
        elseif x.ref isa SymbolServer.SymStore
            push!(documentation, MarkedString(x.ref.doc))
        end
    end
end

function get_hover(b::CSTParser.Binding, documentation, server)
    if b.val isa EXPR
        if CSTParser.defines_function(b.val)
            while true
                if b.val isa EXPR 
                    if CSTParser.defines_function(b.val)
                        pushfirst!(documentation, MarkedString(Expr(CSTParser.get_sig(b.val))))
                    elseif CSTParser.defines_datatype(b.val)
                        pushfirst!(documentation, MarkedString(Expr(b.val)))
                    end
                elseif b.val isa SymbolServer.SymStore
                    push!(documentation, b.val.doc)
                else
                    break
                end
                if b.overwrites isa CSTParser.Binding && b.overwrites != b && (b.overwrites.t == getsymbolserver(server)["Core"].vals["Function"] || b.overwrites.t == getsymbolserver(server)["Core"].vals["DataType"])
                    b = b.overwrites
                else
                    break
                end
            end
        else
            push!(documentation, MarkedString(Expr(b.val)))
        end
    elseif b.val isa SymbolServer.SymStore
        push!(documentation, MarkedString(b.val.doc))
    elseif b.val isa CSTParser.Binding
        get_hover(b.val, documentation, server)
    end
end

