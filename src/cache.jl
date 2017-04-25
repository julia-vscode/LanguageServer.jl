@static if VERSION <= v"0.6.0-dev.2474"
    import Base: subtypes
    subtypes(m::Module, x::DataType) = x.abstract ? sort!(collect(_subtypes(m, x)), by = string) : DataType[]
end

function modnames(m::AbstractString, top)
    s = Symbol(m)
    eval(:(using $s))
    M, exists = Base.REPLCompletions.get_value(s, Main)
    if !(s in keys(top))
        modnames(M, top)
    end
end

function modnames(M::Module, top)
    s = parse(string(M))
    d = Dict{Any, Any}(:EXPORTEDNAMES => setdiff(names(M), [:Function]))
    top[s] = d
    for n in names(M, true, true)
        if !Base.isdeprecated(M, n) && first(string(n)) != '#' && isdefined(M, n) && n != :Function
            x = eval(M, n)
            if isa(x, Module) && x != M
                s = parse(string(x))
                if s in keys(top)
                    d[n] = top[s]
                else
                    d[n] = modnames(x, top)
                end
            elseif first(string(n)) != '#' && string(n) != "Module"
                if isa(x, Function)
                    doc = string(Docs.doc(Docs.Binding(M, n)))
                    d[n] = (:Function, doc, sig(x))
                    # d[n] = (:Function, doc, [])
                elseif isa(x, DataType)
                    if x.abstract
                        doc = "$n <: $(x.super)"
                    else
                        doc = string(Docs.doc(Docs.Binding(M, n)))
                    end
                    d[n] = (:DataType, doc, sig(x), [(fieldname(x, i), parse(string(fieldtype(x, i)))) for i in 1:nfields(x)])
                    # d[n] = (:DataType, doc, [], [(fieldname(x, i), parse(string(fieldtype(x, i)))) for i in 1:nfields(x)])
                else
                    doc = string(Docs.doc(Docs.Binding(M, n)))
                    d[n] = (Symbol(typeof(x)), doc, sig(x))
                    # d[n] = (Symbol(typeof(x)), doc, [])
                end
            end
        end
    end
    return d
end

sig(x) = []
# function sig(x::Union{UnionAll, DataType, Function})
#     out = []
#     for m in methods(x)
#         n = m.nargs
#         if n < 0
#             continue
#         end
#         p = m.sig
#         while p isa UnionAll
#             p = p.body
#         end
#         push!(out, (string(m.file), m.line, [parse(string(p.parameters[i])) for i = 2:n]))
#     end
#     out
# end

function sig(f::Union{UnionAll, DataType, Function})
    out = []
    t = Tuple{Vararg{Any}}
    ft = isa(f, Type) ? Type{f} : typeof(f)
    tt = isa(t, Type) ? Tuple{ft, t.parameters...} : Tuple{ft, t...}
    world = typemax(UInt)
    min = UInt[typemin(UInt)]
    max = UInt[typemax(UInt)]
    ms = ccall(:jl_matching_methods, Any, (Any, Cint, Cint, UInt, Ptr{UInt}, Ptr{UInt}), tt, -1, 1, world, min, max)::Array{Any,1}
    for (sig1, _, decl) in ms
        while sig1 isa UnionAll
            sig1 = sig1.body
        end
        ps = []
        for i = 2:decl.nargs
            push!(ps, (string(sig1.parameters[i])))
        end
        push!(out, (decl.file, decl.line, ps))
    end
    out
end

function get_signatures(name, entry)
    sigs = SignatureInformation[]
    for (file, line, t) in entry[3]
        startswith(string(file), "REPL[") && continue
        p_sigs = [string(t[i]) for i = 1:length(t)]
        
        desc = string(name, "(", join(p_sigs, ", "), ")")
        PI = map(ParameterInformation, p_sigs)
        push!(sigs, SignatureInformation(desc, "", PI))
    end
    
    signatureHelper = SignatureHelp(sigs, 0, 0)
    return signatureHelper
end

function get_definitions(name, entry)
    locs = Location[]
    for (file, line, v, t) in entry[3]
        startswith(string(file), "REPL[") && continue
        file = startswith(file, "/") ? file : Base.find_source_file(file)
        push!(locs, Location(is_windows() ? "file:///$(URIParser.escape(replace(file, '\\', '/')))" : "file:$(file)", line - 1))
    end
    return locs
end





updatecache(absentmodule::Symbol, server) = updatecache([absentmodule], server)

function updatecache(absentmodules::Vector{Symbol}, server)
    env_new = copy(ENV)
    env_new["JULIA_PKGDIR"] = server.user_pkg_dir

    cache_jl_path = replace(joinpath(dirname(@__FILE__), "cache.jl"), "\\", "\\\\")

    o, i, p = readandwrite(Cmd(`$JULIA_HOME/julia -e "include(\"$cache_jl_path\");
    top=Dict();
    for m in [$(join((m->"\"$m\"").(absentmodules),", "))];
        modnames(m, top); 
    end; 
    io = IOBuffer();
    io_base64 = Base64EncodePipe(io);
    serialize(io_base64, top);
    close(io_base64);
    str = String(take!(io));
    println(STDOUT, str);
    "`, env = env_new))
    
    @async begin 
        str = readline(o)
        data = base64decode(String(chomp(str)))
        mods = deserialize(IOBuffer(data))
        for k in keys(mods)
            if !(k in keys(server.cache))
                server.cache[k] = mods[k]
            end
        end
        # str = readline(o)
        # data = base64decode(String(chomp(str)))
        # meths = deserialize(IOBuffer(data))
        # for k in keys(meths)
        #     if (k in keys(server.cache))
        #         server.cache[k] = meths[k]
        #     end
        # end
        for m in absentmodules
            println("Loaded $m")
        end
    end
end
