function parseblocks(doc::Document, server::LanguageServerInstance, first_line, first_character, last_line, last_character)
    text = get_text(doc)
    doc.blocks.typ = 0:length(text.data)

    if isempty(text)
        empty!(doc.blocks.args)
        return
    end
    isempty(doc.blocks.args) && parseblocks(doc, server)

    last_line = min(last_line, length(get_line_offsets(doc)))
    dirty = get_offset(doc, first_line, first_character):get_offset(doc, last_line, last_character)

    i = start = stop = 0
    while i<length(doc.blocks.args)
        i+=1
        if isa(doc.blocks.args[i], Expr)
            if start==0 && first(dirty)>first(doc.blocks.args[i].typ)
                start = i
            end
            if first(dirty) in doc.blocks.args[i].typ && start>0 && doc.blocks.args[start].head!=:error
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
    
    startpos = start==0 ? 0 : doc.blocks.args[start].typ[1]
    while stop<length(doc.blocks.args)
        isa(doc.blocks.args[stop+1], Expr) && break
        stop+=1
    end
    stopexpr = stop==length(doc.blocks.args) ? Expr(:nostop) : doc.blocks.args[stop+1]
    endblocks = stop>0 ? doc.blocks.args[stop+2:end] : []

    deleteat!(doc.blocks.args, max(1, start):length(doc.blocks.args))

    parseblocks(text, doc.blocks, startpos, stopexpr, endblocks)
    return
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
    doc.blocks.typ = 0:length(text.data)
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

"""
    getname(ex)

If `ex` is an expression defining a variable, returns the name of said
variable.
"""
function getname(ex)
    if isa(ex, Expr)
        if ex.head==:(=) && isa(ex.args[1], Symbol)
            if isa(ex.args[2], Expr) || isa(ex.args[2], Symbol)
                t = :Any
            else
                t = Symbol(typeof(ex.args[2])) 
            end
            return (ex.args[1], t, ex.typ)
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
    fields = Pair[]
    for c in children(ex)
        if isa(c, Symbol)
            push!(fields, c=>:Any)
        elseif isa(c, Expr) && c.head==:(::)
            push!(fields, c.args[1]=>c.args[2])
        end
    end
    return fields
end







function get_namespace(ex, i, list)
    if isa(ex, Expr)
        if ex.head==:function && i in ex.typ
            for (n,t) in parsesignature(ex.args[1])
                list[n] = (:argument, t, ex.typ, ex.args[1])
            end
        elseif ex.head==:for && ex.args[1].head==:(=) && isa(ex.args[1].args[1], Symbol)
            list[ex.args[1].args[1]] = (:iterator, :Any, ex.typ, ex.args[1])
        elseif ex.head==:let  
            for a in ex.args[2:end] 
                list[a.args[1]]= (:local, :Any, a.typ, a)
            end 
        end
        childs = children(ex)
        for j = 1:length(childs)
            a = childs[j]
            if isblock(a) && i in a.typ
                for v in (ex.head in [:global, :module] ? childs : view(childs,1:j))
                    n,t,l = getname(v)
                    scope = ex.head==:global ? :global : 
                            ex.head==:module ? ex.args[2] : :local
                    list[n] = (scope, t, l, v)
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

Base.in(a::UnitRange,b::UnitRange) = a.start≥b.start && a.stop ≤ b.stop

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
            fn = Dict(parsestruct(def))
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



function striplocinfo!(ex)
    if isa(ex, Expr)
        ex.typ = Any
        for a in ex.args
            striplocinfo!(a)
        end
    end
end
striplocinfo(ex) = (ex1 = deepcopy(ex);striplocinfo!(ex1);ex1) 