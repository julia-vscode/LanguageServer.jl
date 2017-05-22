function lint_func(x::EXPR, s::Scope, server)
    
end

function get_REQUIRE(server)
    if "REQUIRE" in readdir(server.rootPath)
        str = readlines(joinpath(server.rootPath, "REQUIRE"))
        req = Symbol[]
        for line in str
            m = Symbol(split(line, " ")[1])
            if !(m in [:julia])
                push!(req, m)
            end
        end
        return req
    else
        return Symbol[]
    end
end

function lint_REQUIRE(server)
    if "REQUIRE" in readdir(server.rootPath)
        modules = Union{Symbol,Expr}[]
        for (uri, doc) in server.documents
            if startswith(uri, string("file://", server.rootPath, "/src"))
                s = get_toplevel(doc, server, false)
                for (v, loc, uri1) in s.symbols
                    if v.t == :IMPORTS && v.id isa Expr && v.id.args[1] isa Symbol && v.id.args[1] != :.
                        push!(modules, v.id.args[1])
                    end
                end
            end
        end
        modules = setdiff(unique(modules), [:Base, :Core])
        
    end
end
using CSTParser



function lint_run(x, res)  end
function lint_run(x::EXPR, res = [])
    lint_run(x, typeof(x.head), res)
    res
end
function lint_run(x::EXPR, t, res)
    if !CSTParser.no_iter(x)
        for a in x.args
            lint_run(a, res)
        end
    end
end
function lint_run(x::EXPR, ::Type{KEYWORD{Tokens.FUNCTION}}, res)
    push!(res, x.args[1])
    if !CSTParser.no_iter(x)
        for a in x.args
            lint_run(a, res)
        end
    end
end

@time res = lint_run(x);
@benchmark lint_run(x)


function lint_run(x, res, server)  end
function lint_run(x::EXPR, res, server)
    lint_run(x, x.head, res, server)
    res
end
function lint_run(x::EXPR, t, res, server)
    if !CSTParser.no_iter(x)
        for a in x.args
            lint_run(a, res, server)
        end
    end
end
function lint_run(x::EXPR, T::KEYWORD{Tokens.FUNCTION}, res, server)
    push!(res, x.args[1])
end
function lint_run(x::EXPR, T::HEAD{Tokens.CALL}, res, server)
    if isinclude(x)
        file = Expr(x.args[2])
        
        if !isabspath(file)
            # file = joinpath(dirname(s.current.uri), file)
            file = joinpath("file:///home/zac/github/LanguageServer/src", file)
        else
            file = filepath2uri(file)
        end
        if file in keys(server.documents)
            lint_run(server.documents[file].code.ast, res, server)
        end
    end
end

uri = "file:///home/zac/github/LanguageServer/src/LanguageServer.jl"
x = server.documents[uri].code.ast

res = []
@time lint_run(x, res, server);
@benchmark lint_run(x, [], server);

using LanguageServer
s = LanguageServer.Scope(uri)
@time LanguageServer.get_toplevel(x, s, server)
