Base.in(loc::Int, ex) = isa(ex, Expr) && isa(ex.typ, UnitRange) && loc in ex.typ

get_names(ex::Expr, loc, scope, list, server) = get_names(Val{ex.head}, ex::Expr, loc, scope, list, server)

function get_names(ex::Expr, loc, server)
    ns=Dict{Any,Any}(:document_uri=>"", :loaded_modules=>[])
    get_names(ex, loc, :global, ns, server)
    return ns 
end

function get_names(uri::String, loc, server)
    doc = server.documents[uri]
    ns=Dict{Any,Any}(:document_uri=>(uri), :loaded_modules=>[])
    get_names(doc.blocks, loc, :global, ns, server)

    return ns
end

function get_names(uri::String, server)
    ns = get_names(uri, 1, server)
    server.documents[uri].global_namespace = ns
end



# Unhandled

get_names(ex, loc, scope, list, server) = nothing
get_names{T<:Any}(::Type{Val{T}}, ex, loc, scope, list, server) = nothing


# Special

get_names(::Type{Val{:global}}, ex::Expr, loc, scope, list, server) = get_names(ex.args[1], loc, :local, list, server)
get_names(::Type{Val{:local}}, ex::Expr, loc, scope, list, server) = get_names(ex.args[1], loc, :local, list, server)
get_names(::Type{Val{:const}}, ex::Expr, loc, scope, list, server) = get_names(ex.args[1], loc, :const, list, server)

function get_names(::Type{Val{:macrocall}}, ex::Expr, loc, scope, list, server)
    if ex.args[1] == Symbol("@doc")
        return get_names(ex.args[3], loc, scope, list, server)
    end
end



# Basic

function get_names(::Type{Val{:(=)}}, ex::Expr, loc, scope, list, server)
    if isa(ex.args[1], Symbol)
        list[ex.args[1]] = (scope, :Any, ex, list[:document_uri])
    elseif isa(ex.args[1], Expr) 
        if ex.args[1].head==:call
            list[ex.args[1].args[1]] = (scope, :Function, ex, list[:document_uri])
        elseif ex.args[1].head==:tuple
            for a in ex.args[1].args
                if isa(a, Symbol)
                    list[a] = (scope, :Any, ex, list[:document_uri])
                end
            end
        end 
    end
end

function get_names(::Type{Val{:call}}, ex::Expr, loc, scope, list, server)
    if ex.args[1]==:include
        get_names(Val{:include}, ex, loc, scope, list, server)
    end
end

function get_names(::Type{Val{:block}}, ex::Expr, loc, scope, list, server)
    if loc in ex
        for a in ex.args
            get_names(a, loc, scope, list, server)
            scope!=:global && loc in a && break 
        end
    end
end

get_names(::Type{Val{:baremodule}}, ex::Expr, loc, scope, list, server) = get_names(Val{:module}, ex, loc, scope, list, server)

function get_names(::Type{Val{:module}}, ex::Expr, loc, scope, list, server)
    list[ex.args[2]] = (scope, :Module, ex, list[:document_uri])
    if loc in ex
        for a in ex.args[3].args
            get_names(a, loc, ex.args[2], list, server)
        end
    end
end

function get_names(::Type{Val{:function}}, ex::Expr, loc, scope, list, server)
    
    fname = isa(ex.args[1], Symbol) ? ex.args[1] : 
            isa(ex.args[1].args[1], Symbol) ? ex.args[1].args[1] : 
                                    ex.args[1].args[1].args[1]
    list[fname] = (scope, :Function, ex, list[:document_uri])

    if loc in ex
        for (n,t) in parsesignature(ex.args[1])
            list[n] = (:argument, t, ex.args[1], list[:document_uri])
        end
        if loc in ex.args[2]
            for a in ex.args[2].args
                get_names(a, loc, :local, list, server)
                loc in a && break
            end
        end
    end
end

function get_names(::Type{Val{:macro}}, ex::Expr, loc, scope, list, server)
    list[ex.args[1].args[1]] = (scope, :Macro, ex, list[:document_uri])
end



# Modules, imports and includes

function get_names(::Type{Val{:include}}, ex::Expr, loc, scope, list, server)
    
    if isa(ex.args[2], String)
        luri = joinpath(dirname(list[:document_uri]), ex.args[2])
        fpath = startswith(luri, "file://") ? luri[8:end] : luri
        if isfile(fpath) && (luri in keys(server.documents))
            if isempty(server.documents[luri].blocks.args)
                parseblocks(server.documents[luri], server)
                get_names(luri, server)
            end
            for (k,v) in server.documents[luri].global_namespace
                list[k] = v
            end
        end
    end
end

function get_names(::Type{Val{:using}}, ex::Expr, loc, scope, list, server)
    if length(ex.args)==1 && isa(ex.args[1], Symbol)
        if ex.args[1] in keys(server.cache)
        elseif string(ex.args[1]) in readdir(Pkg.dir())
            updatecache(ex.args[1], server)
            # send(Message(3, "Adding $(ex.args[1]) to cache, this may take a minute"), server)
            # absentmodule = ["$(ex.args[1])"]
            # run(`julia -e "using LanguageServer;top = LanguageServer.loadcache();  LanguageServer.modnames(\"$(ex.args[1])\", top);LanguageServer.savecache(top)"`)
            # server.cache = loadcache()
            # send(Message(3, "Cache stored at $(joinpath(Pkg.dir("LanguageServer"), "cache", "docs.cache"))"), server)
        else
            return
        end
        push!(list[:loaded_modules], ex.args[1])
    end
end

function get_names(::Type{Val{:toplevel}}, ex::Expr, loc, scope, list, server)
    for a in ex.args
        get_names(a, loc, scope, list, server)
    end
end

function get_names(::Type{Val{:import}}, ex::Expr, loc, scope, list, server)
    if isa(ex.args[1], Symbol)
        if ex.args[1] in keys(server.cache)
        elseif string(ex.args[1]) in readdir(Pkg.dir())
            updatecache(ex.args[1], server)
        else
            return
        end
        if length(ex.args)==1
            list[ex.args[1]] = server.cache[ex.args[1]]
        elseif length(ex.args)==2 
            list[ex.args[2]] = server.cache[ex.args[1]][ex.args[2]]
        elseif length(ex.args)==3 && Expr(:.,ex.args[1],QuoteNode(ex.args[2])) in keys(server.cache)
            list[ex.args[3]] =  server.cache[Expr(:.,ex.args[1],QuoteNode(ex.args[2]))][ex.args[3]]
        end
    end
end


# Control Flow

get_names(::Type{Val{:while}}, ex::Expr, loc, scope, list, server) = get_names(ex.args[2], loc, scope, list, server)

function get_names(::Type{Val{:for}}, ex::Expr, loc, scope, list, server)
    if loc in ex
        if ex.args[1].head==:(=)
            if isa(ex.args[1].args[1], Symbol)
                list[ex.args[1].args[1]] = (:iterator, :Any, ex.args[1], list[:document_uri])
            elseif isa(ex.args[1].args[1], Expr) && ex.args[1].args[1].head==:tuple
                for it in ex.args[1].args[1].args
                    if isa(it, Symbol)
                        list[it] = (:iterator, :Any, ex.args[1], list[:document_uri])
                    end
                end
            end
        end
        for a in ex.args[2].args
            get_names(a, loc, :local, list, server)
            loc in a && break
        end
    end
end

function get_names(::Type{Val{:if}}, ex::Expr, loc, scope, list, server)
    for a in ex.args[2].args
        get_names(a, loc, :local, list, server)
        loc in a && return
    end
    if length(ex.args)==3
        for a in ex.args[3].args
            get_names(a, loc, :local, list, server)
            loc in a && break
        end
    end
end



# DataTypes

get_names(::Type{Val{:type}}, ex::Expr, loc, scope, list, server) = get_names(Val{:struct}, ex::Expr, loc, scope, list, server)
get_names(::Type{Val{:immutable}}, ex::Expr, loc, scope, list, server) = get_names(Val{:struct}, ex::Expr, loc, scope, list, server)
function get_names(::Type{Val{:struct}}, ex::Expr, loc, scope, list, server)
    tname = isa(ex.args[2], Symbol) ? ex.args[2] :
            isa(ex.args[2].args[1], Symbol) ? ex.args[2].args[1] : 
            isa(ex.args[2].args[1].args[1], Symbol) ? ex.args[2].args[1].args[1]: :unknown
    list[tname] = (scope, :DataType, ex, list[:document_uri])
end

function get_names(::Type{Val{:abstract}}, ex::Expr, loc, scope, list, server)
    tname = isa(ex.args[1], Symbol) ? ex.args[1] :
            isa(ex.args[1].args[1], Symbol) ? ex.args[1].args[1] : 
            isa(ex.args[1].args[1].args[1], Symbol) ? ex.args[1].args[1].args[1]: :unknown
    list[tname] = (scope, :DataType, ex, list[:document_uri])
end

function get_names(::Type{Val{:bitstype}}, ex::Expr, loc, scope, list, server)
    tname = isa(ex.args[2], Symbol) ? ex.args[2] :
            isa(ex.args[2].args[1], Symbol) ? ex.args[2].args[1] : 
            isa(ex.args[2].args[1].args[1], Symbol) ? ex.args[2].args[1].args[1]: :unknown
    list[tname] = (scope, :DataType, ex, list[:document_uri])
end





# Utilities

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
    for c in ex.args[3].args
        if isa(c, Symbol)
            push!(fields, c=>:Any)
        elseif isa(c, Expr) && c.head==:(::)
            push!(fields, c.args[1]=>striplocinfo(c.args[2]))
        end
    end
    return fields
end
