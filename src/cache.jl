import Base: subtypes
subtypes(m::Module, x::DataType) = x.abstract ? sort!(collect(_subtypes(m, x)), by=string) : DataType[]

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
        p = string.(collect(m.sig.parameters[2:end]))
        push!(out, (String(m.file), m.line, m.source.slotnames[2:length(p)+1], p))
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
    send(Message(3, "Adding $(join(absentmodules, ", ")) to cache, this may take a minute"), server)    
    run(`julia -e "using LanguageServer;delete!(Base.ENV, \"JULIA_PKGDIR\"); top = LanguageServer.loadcache(); for m in [$(join((m->"\"$m\"").(absentmodules),", "))]; LanguageServer.modnames(m, top); end; LanguageServer.savecache(top)"`)
    server.cache = loadcache()
    send(Message(3, "Cache stored at $(joinpath(Pkg.dir("LanguageServer"), "cache", "docs.cache"))"), server)
end

function savecache(top)
    top[:EXPORTEDNAMES] = union(top[:Base][:EXPORTEDNAMES], top[:Core][:EXPORTEDNAMES])
    io = open(joinpath(Pkg.dir("LanguageServer"), "cache", "docs.cache"), "w")
    serialize(io, top)
    close(io)
end

function loadcache()
    io = open(joinpath(Pkg.dir("LanguageServer"), "cache", "docs.cache"))
    return deserialize(io)
end