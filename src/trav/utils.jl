const BaseCoreNames = Set(vcat(names(Base), names(Core), :end, :new, :ccall))

"""
    isincludable(x)
Checks whether `x` is an expression that includes a file.
"""
isincludable(x) = false
function isincludable(x::EXPR{Call})
    x.args[1] isa IDENTIFIER && x.args[1].val == "include" && length(x.args) == 4 && (x.args[3] isa LITERAL{Tokens.STRING} || x.args[3] isa LITERAL{Tokens.TRIPLE_STRING})
end

"""
    isimport(x)
Checks whether `x` is an expression that imports a module.
"""
isimport(x) = false
isimport(x::EXPR{T}) where T <: Union{CSTParser.Import,CSTParser.ImportAll,CSTParser.Using} = true

"""
    ismodule(x)
Checks whether `x` is an expression that declares a module.
"""
ismodule(x) = false
ismodule(x::EXPR{T}) where T <: Union{CSTParser.ModuleH,CSTParser.BareModule} = true

"""
    findtopfile(uri::String, server, path = String[], namespace = [])

Checks for files that include `uri` then recursively finds the top of that 
tree returning the sequence of files - `path` - and any namespaces introduced - 
`namespace`.
"""
function findtopfile(uri::String, server, path = String[], namespace = [])
    follow = []
    for (uri1, doc1) in server.documents
        for (incl, ns) in doc1.code.includes
            if uri == incl
                append!(namespace, ns)
                push!(follow, uri1)
            end
        end
    end

    if isempty(follow)
        push!(path, uri)
        return path, reverse(namespace)
    else
        if length(follow) > 1
            for f in follow
                warn("$uri is included by more than one file, following the first: $f")
            end
        end
        if uri in path
            response = JSONRPC.Notification{Val{Symbol("window/showMessage")},ShowMessageParams}(ShowMessageParams(3, "Circular reference detected in : $uri"))
            send(response, server)
            return path, namespace
        end
        push!(path, uri)
        return findtopfile(first(follow), server, path, namespace)
    end
end

function _get_includes(x, files = []) end
function _get_includes(x::EXPR{Call}, files = [])
    if isincludable(x)
        push!(files, (normpath(x.args[3].val), []))
    end
    return files
end


function _get_includes(x::EXPR, files = [])
    for a in x.args
        if a isa EXPR{CSTParser.ModuleH} || a isa EXPR{CSTParser.BareModule}
            mname = Expr(a.args[2])
            files1 = _get_includes(a)
            for (f, ns) in files1
                push!(files, (f, vcat(mname, ns)))
            end
        elseif !(x isa EXPR{Call})
            _get_includes(a, files)
        end
    end
    return files
end

iserrorexpr(x::Expr) = x.head == :error
iserrorexpr(x) = false


Base.start(x::EXPR) = 1
Base.next(x::EXPR, s) = x.args[s], s + 1
Base.done(x::EXPR, s) = s > length(x.args)

Base.start(x::UnaryOpCall) = 1
Base.next(x::UnaryOpCall, s) = s == 1 ? x.op : x.arg , s + 1
Base.done(x::UnaryOpCall, s) = s > 2

Base.start(x::UnarySyntaxOpCall) = 1
Base.next(x::UnarySyntaxOpCall, s) = s == 1 ? x.arg1 : x.arg2 , s + 1
Base.done(x::UnarySyntaxOpCall, s) = s > 2

Base.start(x::BinarySyntaxOpCall) = 1
Base.next(x::BinarySyntaxOpCall, s) = getfield(x, s) , s + 1
Base.done(x::BinarySyntaxOpCall, s) = s > 3

Base.start(x::BinaryOpCall) = 1
Base.next(x::BinaryOpCall, s) = getfield(x, s) , s + 1
Base.done(x::BinaryOpCall, s) = s > 3

Base.start(x::WhereOpCall) = 1
function Base.next(x::WhereOpCall, s) 
    if s == 1
        return x.arg1, 2
    elseif s == 2
        return x.op, 3
    else
        return x.args[s - 2] , s + 1
    end
end
Base.done(x::WhereOpCall, s) = s > 2 + length(x.args)

Base.start(x::ConditionalOpCall) = 1
Base.next(x::ConditionalOpCall, s) = getfield(x, s) , s + 1
Base.done(x::ConditionalOpCall, s) = s > 5

for t in (CSTParser.IDENTIFIER, CSTParser.OPERATOR, CSTParser.LITERAL, CSTParser.PUNCTUATION, CSTParser.KEYWORD)
    Base.start(x::t) = 1
    Base.next(x::t, s) = x, s + 1
    Base.done(x::t, s) = true
end
