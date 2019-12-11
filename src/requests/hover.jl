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
    x = get_expr(getcst(doc), get_offset(doc, r.params.position), 0, true)
    
    get_hover(x, documentation, server)
    
    send(JSONRPC.Response(r.id, Hover(unique(documentation))), server)
end


function get_hover(x, documentation, server) end

function get_hover(x::EXPR, documentation, server)
    if parentof(x) isa EXPR  && (kindof(x) === CSTParser.Tokens.END || kindof(x) === CSTParser.Tokens.RPAREN || kindof(x) === CSTParser.Tokens.RBRACE || kindof(x) === CSTParser.Tokens.RSQUARE)
        push!(documentation, MarkedString("Closes $(typof(parentof(x))) expression."))
    elseif CSTParser.isidentifier(x) && StaticLint.hasref(x)
        if refof(x) isa StaticLint.Binding
            get_hover(refof(x), documentation, server)
        elseif refof(x) isa SymbolServer.SymStore
            append!(documentation, split_docs(refof(x).doc))
        end
    end
end

function get_hover(b::StaticLint.Binding, documentation, server)
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
                if b.prev isa StaticLint.Binding && b.prev != b && (b.prev.type == getsymbolserver(server)["Core"].vals["Function"] || b.prev.type == getsymbolserver(server)["Core"].vals["DataType"])
                    b = b.prev
                else
                    break
                end
            end
        else
            push!(documentation, MarkedString(Expr(b.val)))
        end
    elseif b.val isa SymbolServer.SymStore
        append!(documentation, split_docs(b.val.doc))
    elseif b.val isa StaticLint.Binding
        get_hover(b.val, documentation, server)
    end
end

"""
    split_docs(s::String)

Returns an array of Union{String,MarkedString} by separating code blocks (denoted by ```sometext```) within s.
"""
function split_docs(s::String)
    out = Any[]
    locs = Int[]
    i = 1
    while i < length(s)
        m = match(r"```", s, i)
        if m isa Nothing
            isempty(out) && push!(out, s)
            break
        else
            push!(locs, m.offset)
            i = m.offset + 3
        end
    end
    if length(locs) > 0 && iseven(length(locs))
        if locs[1] !== 1
            push!(out, s[1:locs[1]-1])
        end
        for i = 1:2:length(locs)
            push!(out, LanguageServer.MarkedString("julia", replace(s[locs[i]+3:locs[i+1]-1], "jldoctest"=>"")))
            if i + 1 == length(locs)
                push!(out, s[locs[i+1]+3:end])
            else
                push!(out, s[locs[i+1]+3:locs[i+2]-1])
            end
        end
    end
    return out
end
