const fallbackpkgdir = joinpath(homedir(), ".julia", "v$(VERSION.major).$(VERSION.minor)")

type LocalVar
    t::Union{Symbol,Expr}
    def::Expr
    uri::String
    methods::Vector
end
LocalVar(t, def, uri) = LocalVar(t, def, uri, [])

⊆(loc::Int, ex) = isa(ex, Expr) && isa(ex.typ, UnitRange) && loc in ex.typ

get_names(ex::Expr, scope, ns, server) = get_names(Val{ex.head}, ex::Expr, scope, ns, server)

function get_names(ex::Expr, loc, server)
    ns = Scope("", [], Dict(), loc)
    get_names(ex, :global, ns, server)
    return ns
end

function get_names(uri::String, loc, server)
    doc = server.documents[uri]
    ns = Scope(uri, [], Dict(), loc)
    get_names(doc.blocks, :global, ns, server)
    return ns
end

function get_names(uri::String, server)
    ns = get_names(uri, 1, server)
    server.documents[uri].global_namespace = ns
end



# Unhandled

get_names(ex, scope, ns, server) = nothing
get_names{T<:Any}(::Type{Val{T}}, ex, scope, ns, server) = nothing


# Special

get_names(::Type{Val{:global}}, ex::Expr, scope, ns, server) = get_names(ex.args[1], :local, ns, server)
get_names(::Type{Val{:local}}, ex::Expr, scope, ns, server) = get_names(ex.args[1], :local, ns, server)
get_names(::Type{Val{:const}}, ex::Expr, scope, ns, server) = get_names(ex.args[1], :const, ns, server)

function get_names(::Type{Val{:macrocall}}, ex::Expr, scope, ns, server)
    if ex.args[1] == Symbol("@doc")
        return get_names(ex.args[3], scope, ns, server)
    end
end



# Basic

function get_names(::Type{Val{:(=)}}, ex::Expr, scope, ns, server)
    if isa(ex.args[1], Symbol) # Extending inference should start here
        t = isa(ex.args[2], Number) ? :Number :
            isa(ex.args[2], AbstractString) ? :String : :Any
        ns.list[ex.args[1]] = LocalVar(t, ex, ns.uri)
        if ns.loc ⊆ ex.args[2]
            get_names(ex.args[2], scope, ns, server)
        end
    elseif isa(ex.args[1], Expr) 
        if ex.args[1].head==:call
            fname = isa(ex.args[1].args[1], Symbol) ? ex.args[1].args[1] : 
            isa(ex.args[1].args[1].args[1], Symbol) ? ex.args[1].args[1].args[1] : 
                                                      ex.args[1].args[1].args[1].args[1]
            if fname in keys(ns.list) && isa(ns.list[fname], LocalVar)
                push!(ns.list[fname].methods, (ex, ns.uri))
            else
                ns.list[ex.args[1].args[1]] = LocalVar(:Function, ex, ns.uri)
            end
        elseif ex.args[1].head==:tuple
            for a in ex.args[1].args
                if isa(a, Symbol)
                    ns.list[a] = LocalVar(:Any, ex, ns.uri)
                end
            end
        end 
    end
end

function get_names(::Type{Val{:call}}, ex::Expr, scope, ns, server)
    if ex.args[1]==:include
        get_names(Val{:include}, ex, scope, ns, server)
    end
end

function get_names(::Type{Val{:block}}, ex::Expr, scope, ns, server)
    if ns.loc ⊆ ex
        for a in ex.args
            get_names(a, scope, ns, server)
            scope!=:global && ns.loc ⊆ a && break 
        end
    end
end

get_names(::Type{Val{:baremodule}}, ex::Expr, scope, ns, server) = get_names(Val{:module}, ex, scope, ns, server)

function get_names(::Type{Val{:module}}, ex::Expr, scope, ns, server)
    ns.list[ex.args[2]] = LocalVar(:Module, ex, ns.uri)
    if ns.loc ⊆ ex
        for a in ex.args[3].args
            get_names(a, ex.args[2], ns, server)
        end
    end
end

function get_names(::Type{Val{:function}}, ex::Expr, scope, ns, server)
    fname = func_name(ex.args[1])
    if fname in keys(ns.list) && isa(ns.list[fname], LocalVar) 
        push!(ns.list[fname].methods, (ex, ns.uri))
    else                                    
        ns.list[fname] = LocalVar(:Function, ex, ns.uri)
    end

    length(ex.args)==1 && return

    if ns.loc ⊆ ex
        for (n,t) in parsesignature(ex.args[1])
            ns.list[n] = LocalVar(t, ex.args[1], ns.uri)
        end
        if ns.loc ⊆ ex.args[2]
            for a in ex.args[2].args
                get_names(a, :local, ns, server)
                ns.loc ⊆ a && break
            end
        end
    end
end

function get_names(::Type{Val{:macro}}, ex::Expr, scope, ns, server)
    ns.list[ex.args[1].args[1]] = LocalVar(:Macro, ex, ns.uri)
end



# Modules, imports and includes

function get_names(::Type{Val{:include}}, ex::Expr, scope, ns, server)
    if isa(ex.args[2], String)
        luri = joinpath(dirname(ns.uri), ex.args[2])
        fpath = startswith(luri, "file://") ? luri[8:end] : luri
        if isfile(fpath) && (luri in keys(server.documents))
            if isempty(server.documents[luri].blocks.args)
                parseblocks(server.documents[luri], server)
            end
            if isempty(server.documents[luri].global_namespace.list)
                get_names(luri, server)
            end
            for (k,v) in server.documents[luri].global_namespace.list
                ns.list[k] = v
            end
            for m in server.documents[luri].global_namespace.modules
                if !(m in ns.modules)
                    push!(ns.modules, m)
                end
            end
        end
    end
end

function get_names(::Type{Val{:using}}, ex::Expr, scope, ns, server)
    if length(ex.args)==1 && isa(ex.args[1], Symbol)
        if ex.args[1] in keys(server.cache)
        elseif string(ex.args[1]) in readdir(fallbackpkgdir)
            put!(server.user_modules, ex.args[1])
            # updatecache(ex.args[1], server)
        else
            return
        end
        push!(ns.modules, ex.args[1])
    end
end

function get_names(::Type{Val{:toplevel}}, ex::Expr, scope, ns, server)
    for a in ex.args
        get_names(a, scope, ns, server)
    end
end

function get_names(::Type{Val{:import}}, ex::Expr, scope, ns, server)
    if isa(ex.args[1], Symbol)
        if ex.args[1] in keys(server.cache)
        elseif string(ex.args[1]) in readdir(server.user_pkgdir)
            put!(server.user_modules, ex.args[1])
            # updatecache(ex.args[1], server)
            # if !(ex.args[1] in keys(server.cache))
            #     info("Error, couldn't load $(ex.args)")
            # end
        else
            return
        end

        if !(ex.args[1] in keys(server.cache))
            return
        elseif length(ex.args)==1 
            ns.list[ex.args[1]] = server.cache[ex.args[1]]
        elseif length(ex.args)==2 && ex.args[1] in keys(server.cache) && ex.args[2] in keys(server.cache[ex.args[1]])
            ns.list[ex.args[2]] = server.cache[ex.args[1]][ex.args[2]]
        elseif length(ex.args)==3 && Expr(:.,ex.args[1],QuoteNode(ex.args[2])) in keys(server.cache) && ex.args[3] in keys(server.cache[Expr(:.,ex.args[1],QuoteNode(ex.args[2]))])
            ns.list[ex.args[3]] =  server.cache[Expr(:.,ex.args[1],QuoteNode(ex.args[2]))][ex.args[3]]
        end
    end
end


# Control Flow

get_names(::Type{Val{:while}}, ex::Expr, scope, ns, server) = get_names(ex.args[2], scope, ns, server)

function get_names(::Type{Val{:for}}, ex::Expr, scope, ns, server)
    if ns.loc ⊆ ex
        if ex.args[1].head==:(=)
            if isa(ex.args[1].args[1], Symbol)
                ns.list[ex.args[1].args[1]] = LocalVar(:Any, ex.args[1], ns.uri)
            elseif isa(ex.args[1].args[1], Expr) && ex.args[1].args[1].head==:tuple
                for it in ex.args[1].args[1].args
                    if isa(it, Symbol)
                        ns.list[it] = LocalVar(:Any, ex.args[1], ns.uri)
                    end
                end
            end
        end
        for a in ex.args[2].args
            get_names(a, :local, ns, server)
            ns.loc ⊆ a && break
        end
    end
end

function get_names(::Type{Val{:if}}, ex::Expr, scope, ns, server)
    get_names(ex.args[2], :local, ns, server)
    # for a in ex.args[2].args
    #     get_names(a, :local, ns, server)
    #     ns.loc ⊆ a && return
    # end
    if length(ex.args)==3
        get_names(ex.args[3], :local, ns, server)
    end
end

function get_names(::Type{Val{:let}}, ex::Expr, scope, ns, server)
    if ns.loc ⊆ ex
        for a in ex.args[2:end]
            get_names(a, :local, ns, server)
        end
        for a in ex.args[1].args
            get_names(a, :local, ns, server)
            ns.loc ⊆ a && return
        end
    end
end



# DataTypes

get_names(::Type{Val{:type}}, ex::Expr, scope, ns, server) = get_names(Val{:struct}, ex::Expr, scope, ns, server)
get_names(::Type{Val{:immutable}}, ex::Expr, scope, ns, server) = get_names(Val{:struct}, ex::Expr, scope, ns, server)
function get_names(::Type{Val{:struct}}, ex::Expr, scope, ns, server)
    tname = isa(ex.args[2], Symbol) ? ex.args[2] :
            isa(ex.args[2].args[1], Symbol) ? ex.args[2].args[1] : 
            isa(ex.args[2].args[1].args[1], Symbol) ? ex.args[2].args[1].args[1]: :unknown
    ns.list[tname] = LocalVar(:DataType, ex, ns.uri)
end

function get_names(::Type{Val{:abstract}}, ex::Expr, scope, ns, server)
    tname = isa(ex.args[1], Symbol) ? ex.args[1] :
            isa(ex.args[1].args[1], Symbol) ? ex.args[1].args[1] : 
            isa(ex.args[1].args[1].args[1], Symbol) ? ex.args[1].args[1].args[1]: :unknown
    ns.list[tname] = LocalVar(:DataType, ex, ns.uri)
end

function get_names(::Type{Val{:bitstype}}, ex::Expr, scope, ns, server)
    tname = isa(ex.args[2], Symbol) ? ex.args[2] :
            isa(ex.args[2].args[1], Symbol) ? ex.args[2].args[1] : 
            isa(ex.args[2].args[1].args[1], Symbol) ? ex.args[2].args[1].args[1]: :unknown
    ns.list[tname] = LocalVar(:DataType, ex, ns.uri)
end





# Utilities

function func_name(sig)
    # sig1 = striplocinfo(sig)
    # if sig isa Expr
    #     for i = 2:length(sig1.args)
    #         if sig1.args[i] isa Symbol
    #             sig1.args[i] = :Any
    #         elseif sig1.args[i].head == :(::) && length(sig1.args[i].args) == 1
    #             sig1.args[i] = sig1.args[i].args[1]
    #         elseif sig1.args[i].head == :(::)
    #             sig1.args[i] = sig1.args[i].args[2]
    #         end
    #     end
    #     return sig1
    # end
    isa(sig, Symbol) && return sig
    isa(sig.args[1], Symbol) && return sig.args[1]
    sig.args[1].head==:curly && return sig.args[1].args[1]
end

function parsesignature(sig)
    out = []
    isa(sig, Symbol) && return out
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
    for c in ex.args[3].args
        if isa(c, Symbol)
            push!(fields, c=>:Any)
        elseif isa(c, Expr) && c.head==:(::)
            push!(fields, c.args[1]=>striplocinfo(c.args[2]))
        end
    end
    return fields
end
