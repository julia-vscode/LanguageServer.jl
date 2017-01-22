function parseblocks(doc::Document, server::LanguageServerInstance, first_line, first_character, last_line, last_character)
    text = get_text(doc)
    doc.blocks.typ = 0:endof(text)

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
    errcnt = 0

    while !Lexer.eof(ts)
        ex = try
            JuliaParser.Parser.parse(ts)
        catch err
            Expr(:error, err)
        end
        if isa(ex, Expr) && ex.head==:error
            errcnt+=1
            errcnt>50 && return
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
    doc.blocks.typ = 0:endof(text)
    empty!(doc.blocks.args)
    parseblocks(text, doc.blocks, 1)
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


function get_type(v, ns::Scope)
    if v in keys(ns.list)
        if ns.list[v] isa Dict
            return :Module
        else
            return ns.list[v].t
        end
    elseif isdefined(Main, v)
        return typeof(getfield(Main, v))
    end
    return Any
end


function get_fields(t, ns::Scope)
    fn = Dict()
    if t in keys(ns.list)
        v = ns.list[t]
        if v isa LocalVar && v.def.head in [:immutable, :type]
            fn = Dict(parsestruct(v.def))
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

function get_type(sword::Vector{Symbol}, ns::Scope)
    t = get_type(sword[1], ns)
    for i = 2:length(sword)
        fn = get_fields(t, ns)
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

function code_loc(ex)
    if isa(ex, Expr)
        if isa(ex.typ, UnitRange{Int}) 
            return ex.typ
        else
            for a in ex.args
                l = code_loc(a)
                if l!=0:0
                    return l
                end
            end
        end
    end
    return 0:0
end