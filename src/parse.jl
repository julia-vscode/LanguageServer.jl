function parseblocks(doc::Document, server::LanguageServerInstance, first_line, first_character, last_line, last_character)
    text = get_text(doc)

    if isempty(text)
        empty!(doc.blocks.args)
        return
    end
    isempty(doc.blocks.args) && parseblocks(doc, server)

    dirty = get_offset(doc, first_line, first_character):get_offset(doc, last_line, last_character)
    
    i = 0
    start = stop = 0
    while i<length(doc.blocks.args)
        i+=1
        if isa(doc.blocks.args[i], Expr)
            if start==0 && first(dirty)>first(doc.blocks.args[i].typ)
                start = i
            end
            if first(dirty) in doc.blocks.args[i].typ
                start = i
            end
            if last(dirty) in doc.blocks.args[i].typ 
                stop = i
            end
            if stop==0 && last(dirty)<last(doc.blocks.args[i].typ)
                stop = i
            end
        end
    end
    
    if start==0 && stop==0
        empty!(doc.blocks.args)
        parseblocks(text, doc.blocks, 0)
        
    elseif start>0 && stop==0
        i0 = doc.blocks.args[start].typ[1]
        for i = start:length(doc.blocks.args)
            pop!(doc.blocks.args)
        end
        parseblocks(text, doc.blocks, i0)
    elseif start==0 && stop>0
        i0 = 0
        stopexpr = stop==length(doc.blocks.args) ? Expr(:nostop) : doc.blocks.args[stop+1]
        endblocks = doc.blocks.args[stop+2:end] 
        empty!(blocks.args)
        parseblocks(text, doc.blocks, i0, stopexpr, endblocks)
    elseif start>0 && stop>0
        i0 = i1 = doc.blocks.args[start].typ[1]
        stopexpr = stop==length(doc.blocks.args) ? Expr(:nostop) : doc.blocks.args[stop+1]
        endblocks = doc.blocks.args[stop+2:end] 
        for i = start:length(doc.blocks.args)
            pop!(doc.blocks.args)
        end
        parseblocks(text, doc.blocks, i0, stopexpr, endblocks)
    end
end 

function parseblocks(text, blocks, i0, stopexpr=Expr(:nostop), endblocks = [])
    ts = Lexer.TokenStream(text)
    seek(ts.io, i0==1 ? 0 : i0)
    Lexer.peek_token(ts)

    while !Lexer.eof(ts)
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

function parseblocks(doc::Document, server)
    text = get_text(doc)
    empty!(doc.blocks.args)
    parseblocks(text, doc.blocks, 1)
end


"""
    children(ex)

Retrieves 'child' nodes of an expression.
"""
function children(ex)
    !isa(ex, Expr) && return []
    ex.head==:macrocall && ex.args[1]==Symbol("@doc") && return [ex.args[3]]
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

Checks whether an expression has character position info.
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


function parsestruct(ex::Expr)
    fields = Dict{Symbol,Any}()
    for c in children(ex)
        if isa(c, Symbol)
            fields[c] = :Any
        elseif isa(c, Expr) && c.head==:(::)
            fields[c.args[1]] = c.args[2]
        end
    end
    return fields
end







function get_namespace(ex, i, list)
    if isa(ex, Expr)
        childs = children(ex)
        for j = 1:length(childs)
            a = childs[j]
            if isblock(a) && i in a.typ
                if ex.head==:function
                    for (n,t) in parsesignature(ex.args[1])
                        list[n] = (:argument, t, ex.typ, ex.args[1])
                    end
                end
                for v in (ex.head in [:global, :module] ? childs : view(childs,1:j))
                    n,t,l = getname(v)
                    list[n] = (ex.head in [:global,:module] ? :global : :local, t, l, v)
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


function get_block(ex, i)
    if isa(ex, Expr)
        for c in children(ex)
            if isblock(c) && i in c.typ
                return get_block(c, i)
            end
        end
        if isblock(ex) && i in ex.typ
            return ex
        end
    end
    return
end

function get_type(v, ns)
    if v in keys(ns)
        return ns[v][2]
    elseif isdefined(Main, v)
        return typeof(getfield(Main, v))
    end
    return Any
end


function get_fields(t, ns, blocks)
    fn = Dict()
    if t in keys(ns)
        n, s, loc, def = ns[t]
        if def.head in [:immutable, :type]
            fn = parsestruct(def)
        end
    elseif isa(t, Symbol) && isdefined(Main, t)
        sym = getfield(Main, t)
        if isa(sym, DataType)
            fnames = fieldnames(sym)
            fn = Dict(fnames[i]=>sym.types[i] for i = 1:length(fnames))
        else
            fn = Dict()
        end
    elseif isa(t, DataType)
        fnames = fieldnames(t)
        fn = Dict(fnames[i]=>t.types[i] for i = 1:length(fnames))
    end
    return fn
end



function get_type(sword::Vector{Symbol}, ns, blocks)
    t = get_type(sword[1], ns)
    for i = 2:length(sword)
        fn = get_fields(t, ns, blocks)
        if sword[i] in keys(fn)
            t = fn[sword[i]]
        else
            return :Any
        end
    end
    return Symbol(t)
end