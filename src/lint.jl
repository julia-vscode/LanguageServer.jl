function process(r::JSONRPC.Request{Val{Symbol("julia/lint-package")},Void}, server)
    warnings = []
    if isdir(server.rootPath) && "REQUIRE" in readdir(server.rootPath)
        topfiles = []
        for (uri, doc) in server.documents
            if startswith(uri, string("file://", server.rootPath, "/src"))
                tf,ns = LanguageServer.findtopfile(uri, server)
                push!(topfiles, last(tf))
            end
        end
        topfiles = unique(topfiles)
        # get all imports and module declarations
        import_stmts = []
        datatypes = []
        functions = []
        modules = Union{Symbol,Expr}[]
        module_decl = Union{Symbol,Expr}[]
        allsymbols = []
        for uri in topfiles
            s = get_toplevel(server.documents[uri], server)
            for (v, loc, uri1) in s.symbols
                if v.t == :IMPORTS && v.id isa Expr && v.id.args[1] isa Symbol && v.id.args[1] != :.
                    push!(modules, v.id.args[1])
                    push!(import_stmts, (v, loc, uri))
                elseif v.t == :module
                    push!(module_decl, v.id)
                elseif v.t == :mutable || v.t == :immutable || v.t == :abstract || v.t == :bitstype
                    push!(datatypes, (v, loc, uri))
                elseif v.t == :Function
                    push!(functions, (v, loc, uri))
                end
            end
        end
        modules = setdiff(unique(modules), vcat([:Base, :Core], unique(module_decl)))

        # NEEDS FIX: checking pkg availability/version requires updated METADATA
        # avail = Pkg.available()
        
        req = get_REQUIRE(server)
        rmid = Int[]
        for (r, ver) in req
            if r == :julia
                # NEEDS FIX
            else
                # if !(String(r) in avail)
                #     push!(warnings, "$r declared in REQUIRE but not available in METADATA")
                # else
                #     avail_ver = Pkg.available(String(r))
                #     if !(ver in avail_ver) && ver > VersionNumber(0)
                #         push!(warnings, "$r declared in REQUIRE but version $ver not available")
                #     end
                # end
                mloc = findfirst(z-> z==r, modules)
                if mloc > 0
                    push!(rmid, mloc)
                else
                    push!(warnings, "$r declared in REQUIRE but doesn't appear to be used.")
                end
                if r == :Compat && ver == VersionNumber(0)
                    push!(warnings, "Compat specified in REQUIRE without specific version.")
                end
            end
        end
        deleteat!(modules, rmid)
        for m in modules
            push!(warnings, "$m used in code but not specified in REQUIRE")
        end
    end
    for w in warnings
        response = JSONRPC.Notification{Val{Symbol("window/showMessage")},ShowMessageParams}(ShowMessageParams(3, w))
        send(response, server)
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/lint-package")}}, params)
    return 
end


function get_REQUIRE(server)
    str = readlines(joinpath(server.rootPath, "REQUIRE"))
    req = Tuple{Symbol,VersionNumber}[]
    
    for line in str
        m = (split(line, " "))
        if length(m) == 2
            push!(req, (Symbol(m[1]), VersionNumber(m[2])))
        else
            push!(req, (Symbol(m[1]), VersionNumber(0)))
        end
    end
    return req
end


# function lint_run(x, res)  end
# function lint_run(x::EXPR, res = [])
#     lint_run(x, typeof(x.head), res)
#     res
# end
# function lint_run(x::EXPR, t, res)
#     if !CSTParser.no_iter(x)
#         for a in x.args
#             lint_run(a, res)
#         end
#     end
# end
# function lint_run(x::EXPR, ::Type{KEYWORD{Tokens.FUNCTION}}, res)
#     push!(res, x.args[1])
#     if !CSTParser.no_iter(x)
#         for a in x.args
#             lint_run(a, res)
#         end
#     end
# end



# function lint_run(x, res, server)  end
# function lint_run(x::EXPR, res, server)
#     lint_run(x, x.head, res, server)
#     res
# end
# function lint_run(x::EXPR, t, res, server)
#     if !CSTParser.no_iter(x)
#         for a in x.args
#             lint_run(a, res, server)
#         end
#     end
# end
# function lint_run(x::EXPR, T::KEYWORD{Tokens.FUNCTION}, res, server)
#     push!(res, x.args[1])
# end
# function lint_run(x::EXPR, T::HEAD{Tokens.CALL}, res, server)
#     if isincludable(x)
#         file = Expr(x.args[2])
        
#         if !isabspath(file)
#             # file = joinpath(dirname(s.current.uri), file)
#             file = joinpath("file:///home/zac/github/LanguageServer/src", file)
#         else
#             file = filepath2uri(file)
#         end
#         if file in keys(server.documents)
#             lint_run(server.documents[file].code.ast, res, server)
#         end
#     end
# end
