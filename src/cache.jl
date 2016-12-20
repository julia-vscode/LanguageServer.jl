function modnames(m::AbstractString, top)
    s = Symbol(m)
    eval(:(using $s))
    M, exists = Base.REPLCompletions.get_value(s, Main)
    if !(s in keys(top))
        modnames(M, top)
    end
    # pdir = Pkg.dir(m)
    # if isdir(pdir)
    #     flist = readdir(pdir)
    #     if isfile(pdir*"/REQUIRE")
    #         incls = filter!(i->i!="julia",(f->match(r"^\S*",f).match).(chomp.(readlines(pdir*"/REQUIRE"))))
    #         for i in incls
    #             x, exists = Base.REPLCompletions.get_value(Symbol(i), Main)
    #             modnames(x, top)
    #             top[s][Symbol(i)] = top[Symbol(i)]
    #         end
    #     end
    # end
end

function sig(x)
    sigs = SignatureInformation[]
    locs = Location[]
    for m in methods(x).ms
        startswith(string(m.file), "REPL[") && continue
        tv, decls, file, line = Base.arg_decl_parts(m)
        file = file==Symbol("") ? "" : normpath(Base.find_source_file(string(m.file)))
        p_sigs = [isempty(i[2]) ? i[1] : i[1]*"::"*i[2] for i in decls[2:end]]
        desc = string(string(m.name), "(", join(p_sigs, ", "), ")")
        PI = map(ParameterInformation, p_sigs)
        push!(sigs, SignatureInformation(desc, "", PI))
        push!(locs, Location(is_windows() ? "file:///$(URIParser.escape(replace(file, '\\', '/')))" : "file:$(file)", m.line-1))
    end
    
    signatureHelper = SignatureHelp(sigs, 0, 0)
    return signatureHelper, locs
end

function modnames(M::Module, top)
    s = parse(string(M))
    d = Dict{Any,Any}(:EXPORTEDNAMES=>setdiff(names(M),[Symbol(M)]))
    top[s] = d
    for n in names(M, true, true)
        Base.isdeprecated(M, n) || first(string(n))=="#" && continue
        x, exists = Base.REPLCompletions.get_value(n, M)
        if exists 
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
                doc = string(Docs.doc(Docs.Binding(M, n)))
                d[n] = (t, doc, sig(x)...)
            end
        end
    end
    return d
end

# run(`julia -e "using LanguageServer; top = Dict();LanguageServer.modnames(Main, top); LanguageServer.savecache(top)"`)
# run(`julia -e "using LanguageServer; top = LanguageServer.loadcache(); for m in [$(join((m->"\"$m\"").(absentmodules),", "))]; LanguageServer.modnames(m, top); end; LanguageServer.savecache(top)"`)

function updatecache(absentmodules)
    send(Message(3, "Adding $(ex.args[1]) to cache, this may take a minute"), server)    
    run(`julia -e "using LanguageServer; top = LanguageServer.loadcache(); for m in [$(join((m->"\"$m\"").(absentmodules),", "))]; LanguageServer.modnames(m, top); end; LanguageServer.savecache(top)"`)
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