function parseblocks(uri::String, server::LanguageServerInstance, dirty)
    doc = String(server.documents[uri].data)
    blocks = server.documents[uri].blocks
    n = last(blocks.typ)
    
    i = 0
    start = stop = 0
    while i<length(blocks.args)
        i+=1
        if isa(blocks.args[i], Expr)
            if start==0 && first(dirty)>first(blocks.args[i].typ)
                start = i
            end
            if first(dirty) in blocks.args[i].typ
                start = i
            end
            if last(dirty) in blocks.args[i].typ 
                stop = i
            end
            if stop==0 && last(dirty)<last(blocks.args[i].typ)
                stop = i
            end
        end
    end
    
    if start==0 && stop==0
        return parseallblocks(uri, server)
    elseif start>0 && stop==0
        i0 = blocks.args[start].typ[1]
        for i = start:length(blocks.args)
            pop!(blocks.args)
        end
        stopexpr = Expr(:nostop)
    elseif start==0 && stop>0
        i0 = 0
        stopexpr = stop==length(blocks.args) ? Expr(:nostop) : blocks.args[stop+1]
        endblocks = blocks.args[stop+2:end] 
        empty!(blocks.args)
    elseif start>0 && stop>0
        i0 = i1 = blocks.args[start].typ[1]
        stopexpr = stop==length(blocks.args) ? Expr(:nostop) : blocks.args[stop+1]
        endblocks = blocks.args[stop+2:end] 
        for i = start:length(blocks.args)
            pop!(blocks.args)
        end
    end

    ts = Lexer.TokenStream(doc)
    seek(ts.io, i0)

    while 0 ≤ i0 < n
        ex = try 
            JuliaParser.Parser.parse(ts)
        catch err
            Expr(:error, err)
        end
        if isa(ex, Expr) && ex.head==:error 
            seek(ts.io,i0)
            Lexer.next_token(ts)
            Lexer.skip_to_eol(ts)
            Lexer.take_token(ts)
            ex.typ = i0:position(ts)-1
            push!(blocks.args, ex)
            i1 = position(ts)
        else 
            i1=position(ts)
            isa(ex, Expr) && (ex.typ = i0:i1-1)
            ex!=nothing && push!(blocks.args, ex)
        end
        if ex==stopexpr
            d = first(ex.typ)-first(stopexpr.typ)
            for i  = 1:length(endblocks)
                shiftloc!(endblocks[i], d)
                push!(blocks.args,endblocks[i])
            end
            break
        end
        i0 = i1
    end
end 


function parseallblocks(uri::String, server::LanguageServerInstance)
    doc = String(server.documents[uri].data)
    n = length(doc.data)
    blocks = server.documents[uri].blocks
    empty!(blocks.args)
    blocks.typ = 0:n

    doc == "" && return

    ts = Lexer.TokenStream(doc)
    i0 = i1 = 0

    while 0 ≤ i1 < n
        ex = try 
            JuliaParser.Parser.parse(ts)
        catch err
            Expr(:error, err)
        end
        if isa(ex, Expr) && ex.head==:error 
            seek(ts.io,i0)
            Lexer.next_token(ts)
            Lexer.skip_to_eol(ts)
            Lexer.take_token(ts)
            ex.typ = i0:position(ts)
            push!(blocks.args, ex)
            i1 = position(ts)
        else
            i1=position(ts)
            isa(ex, Expr) && (ex.typ = i0:i1-1)
            ex!=nothing && push!(blocks.args, ex)
        end
        i0 = i1
    end 
end 



"""
    children(ex)

Retrieves 'child' nodes of an expression.
"""
function children(ex)
    !isa(ex, Expr) && return []
    ex.head==:function && return length(ex.args)==1  ? nothing : ex.args[2].args
    ex.head==:(=) && isa(ex.args[1], Expr) && ex.args[1].head==:call && return ex.args[2].args
    ex.head in [:begin, :block, :global] && return ex.args
    ex.head in [:while, :for] && return ex.args[2].args
    ex.head in [:module, :baremodule, :type, :immutable] && return ex.args[3].args
    ex.head==:let && return ex.args[1].args
    ex.head==:if && return ex.args[2:end]

    return []
end

"""
    isblock(ex)

Checks whether an experssion has character position info.
"""
isblock(ex) = isa(ex, Expr) && isa(ex.typ, UnitRange)

"""
    shiftloc!(ex, i::Int)

Shift the character location of `ex` and all children by `i`.
"""
function shiftloc!(ex, i::Int)
    if isa(ex, Expr)
        if isa(ex.typ, UnitRange)
            ex.typ += i
        end
        for a in ex.args
            shiftloc!(a, i)
        end
    end
end

get_linebreaks(doc) = [0;find(c->c==0x0a,doc);length(doc)+1]

function getname(ex)
    if isa(ex, Expr)
        if ex.head==:(=) && isa(ex.args[1], Symbol)
            return (ex.args[1], :Any, ex.typ)
        elseif ex.head ==:(=) && isa(ex.args[1], Expr) && ex.args[1].head==:call
            return (ex.args[1].args[1],:Function, ex.typ)
        elseif ex.head==:function
            name = ex.args[1].args[1]
            name = isa(name, Symbol) ? name : name.args[1]
            return (name, :Function, ex.typ)
        elseif ex.head in [:type,:immutable]
            return (isa(ex.args[2], Symbol) ? ex.args[2] : ex.args[2].args[1], :DataType, ex.typ)
        elseif ex.head==:macro
            return (ex.args[1].args[1], :macro, ex.typ)
        elseif ex.head==:module
            return (ex.args[2], :Module, ex.typ)
        end
        return :nothing, :Any, ex.typ
    end
    return :nothing, :Any, 0:0
end

function parsesignature(sig::Expr)
    out = []
    for a in sig.args[2:end]
        if isa(a, Symbol)
            push!(out, (a, :Any))
        elseif a.head==:(::)
            if length(a.args)>1
                push!(out, (a.args[1], a.args[2]))
            else # handles ::Type{T}
                push!(out, (a.args[1], :DataType))
            end
        elseif a.head==:kw
            if isa(a.args[1], Symbol)
                push!(out, (a.args[1], :Any))
            elseif a.args[1].head==:(::)
                push!(out, (a.args[1].args[1], a.args[1].args[2]))
            end 
        elseif a.head==:parameters
            for sub_a in a.args
                if isa(sub_a, Symbol)
                    push!(out,(sub_a, :Any))
                elseif sub_a.head==:...
                    push!(out,(sub_a.args[1], :Any))
                elseif sub_a.head==:kw
                    if isa(sub_a.args[1], Symbol)
                        push!(out,(sub_a.args[1], :Any))
                    elseif sub_a.args[1].head==:(::)
                        push!(out,(sub_a.args[1].args[1], sub_a.args[1].args[2]))
                    end
                end
            end
        end
    end
    return out
end





function get_namespace(ex, i, list)
    if isa(ex, Expr)
        childs = children(ex)
        for j = 1:length(childs)
            a = childs[j]
            if isblock(a) && i in a.typ
                if ex.head==:function
                    for (n,t) in parsesignature(ex.args[1])
                        list[n] = (:argument, t, ex.typ)
                    end
                end
                for v in (ex.head==:module ? childs : view(childs,1:j))
                    n,t,l = getname(v)
                    list[n] = (ex.head in [:global,:module] ? :global : :local, t, l)
                end
                ret =  get_namespace(a, i, list)
                ret!=nothing && return ret
            end
        end
        if isa(ex.typ, UnitRange) && i in ex.typ
            return ex
        end
    end
    return
end
get_namespace(ex::Expr, i) = (list=Dict();ret = get_namespace(ex, i, list);(ret, list))
