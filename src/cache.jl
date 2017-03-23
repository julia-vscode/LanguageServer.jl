@static if VERSION <= v"0.6.0-dev.2474"
    import Base: subtypes
    subtypes(m::Module, x::DataType) = x.abstract ? sort!(collect(_subtypes(m, x)), by=string) : DataType[]
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
    d = Dict{Any,Any}(:EXPORTEDNAMES=>setdiff(names(M), [:Function]))
    top[s] = d
    for n in names(M, true, true)
        if !Base.isdeprecated(M, n) && first(string(n))!="#" && isdefined(M, n) && n!=:Function
            x = eval(M, n)
            if isa(x, Module) && x!=M
                s = parse(string(x))
                if s in keys(top)
                    d[n] = top[s]
                else
                    d[n] = modnames(x, top)
                end
            elseif first(string(n))!='#'
                t = Symbol(isa(x, Function) ? Function :
                           isa(x, DataType) ? DataType :
                                              typeof(x))
                if isa(x, DataType) && x.abstract
                    doc = "$n <: $(x.super)"
                else
                    doc = string(Docs.doc(Docs.Binding(M, n)))
                end
                d[n] = (t, doc, sig(x))
            end
        end
    end
    return d
end

sig(x) = []
function sig(x::Union{DataType,Function})
    out = []
    for m in methods(x)
        n::Int = length(m.sig.parameters)

        p = Array(String, n-1)
        for i=2:n
            p[i-1] = string(m.sig.parameters[i])
        end

        @static if (VERSION < v"0.6.0-dev")
            push!(out, (string(m.file), m.line, m.lambda_template.slotnames[2:n], p))
        else
            push!(out, (string(m.file), m.line, m.source.slotnames[2:n], p))
        end
    end
    out
end

function get_signatures(name, entry)
    sigs = SignatureInformation[]
    for (file, line, v, t) in entry[3]
        startswith(string(file), "REPL[") && continue
        p_sigs = [v[i]==Symbol("#unused#") ? string(t[i]) : string(v[i])*"::"*string(t[i]) for i = 1:length(v)]
        
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
        push!(locs, Location(is_windows() ? "file:///$(URIParser.escape(replace(file, '\\', '/')))" : "file:$(file)", line-1))
    end
    return locs
end





updatecache(absentmodule::Symbol, server) = updatecache([absentmodule], server)

function updatecache(absentmodules::Vector{Symbol}, server)
    o,i, p = readandwrite(`$JULIA_HOME/julia -e "include(\"packages/LanguageServer/src/cache.jl\");
    top=Dict();
    for m in [$(join((m->"\"$m\"").(absentmodules),", "))];
        modnames(m, top); 
    end; 
    io = IOBuffer();
    io_base64 = Base64EncodePipe(io);
    serialize(io_base64, top);
    close(io_base64);
    str = takebuf_string(io);
    println(STDOUT, str)"`)
    
    @async begin 
        str = readline(o)
        data = base64decode(str)
        mods = deserialize(IOBuffer(data))
        for k in keys(mods)
            if !(k in keys(server.cache))
                info("added $k to cache")
                server.cache[k] = mods[k]
            end
        end
    end
end
