function process(r::JSONRPC.Request{Val{Symbol("julia/lint-package")},Void}, server)
    warnings = []
    if isdir(server.rootPath) && "REQUIRE" in readdir(server.rootPath)
        topfiles = []
        rootUri = is_windows() ? string("file:///", replace(joinpath(replace(server.rootPath, "\\", "/"), "src"), ":", "%3A")) : joinpath("file://", server.rootPath, "src")
        for (uri, doc) in server.documents
            if startswith(uri, rootUri)
                tf, ns = LanguageServer.findtopfile(uri, server)
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
            for (v, loc, uri1) in s.imports
                push!(modules, v.args[1])
                push!(import_stmts, (v, loc, uri))
            end
            for (v, loc, uri1) in s.symbols
                if v.t == :module
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
                mloc = findfirst(z -> z == r, modules)
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




const BaseCoreNames = Set(vcat(names(Base), names(Core), :end, :new, :ccall))

function process(r::JSONRPC.Request{Val{Symbol("julia/toggle-lint")},TextDocumentIdentifier}, server)
    server.documents[r.uri]._runlinter != server.documents[r.uri]._runlinter
end

function JSONRPC.parse_params(::Type{Val{Symbol("julia/toggle-lint")}}, params)
    return TextDocumentIdentifier(params["textDocument"])
end

mutable struct LintState
    istop::Bool
    ntop::Int
    ns
    diagnostics::Vector{CSTParser.Diagnostics.Diagnostic}
    symbols::Dict
    locals::Vector{Dict}
end

function add_name!(d::Dict, k)
    if haskey(d, k)
        d[k] += 1
    else
        d[k] = 1
    end
end

function remove_name!(d::Dict, k)
    if d[k] > 1
        d[k] -= 1
    else
        delete!(d, k)
    end
end

function lint(doc::Document, server)
    uri = doc._uri

    # Find top file of include tree
    path, namespace = findtopfile(uri, server)
    
    s = Scope(ScopePosition(uri, typemax(Int)), ScopePosition(last(path), 0), [], [], [], [], namespace, false, true, true, Diagnostic[])
    get_toplevel(server.documents[last(path)].code.ast, s, server)
    
    current_namespace = isempty(s.namespace) ? :NOTHING : repack_dot(s.namespace)
    s.current = ScopePosition(uri)

    Lnames = Dict{Any,Int}()
    for v in s.symbols
        add_name!(Lnames, v[1].id)
    end
    L = LintState(true, 0, current_namespace, [], Lnames, Dict{Any,Int}[])
    lint(doc.code.ast, s, L, server, true)

    return L
end

function lint(x::EXPR{CSTParser.Generator}, s::Scope, L::LintState, server, istop)
    offset = x.args[1].span + x.args[2].span
    for i = 3:length(x.args)
        r = x.args[i]
        for v in r.defs
            push!(s.symbols, (v, s.current.offset + offset + (1:r.span), s.current.uri))
            add_name!(L.symbols, v.id)
            if !isempty(L.locals)
                add_name!(last(L.locals), v.id)
            end
        end
        offset += r.span
    end
    lint(x.args[1], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Kw}, s::Scope, L::LintState, server, istop)
    s.current.offset += x.args[1].span + x.args[2].span
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{IDENTIFIER}, s::Scope, L::LintState, server, istop)
    Ex = Symbol(x.val)
    
    found = Ex in BaseCoreNames
    
    if !found
        if haskey(L.symbols, Ex)
            found = true
        end
    end
    if !found
        if haskey(L.symbols, Expr(:., L.ns, QuoteNode(Ex)))
            found = true
        end
    end

    if !found
        for (impt, loc, uri) in s.imports
            if length(impt.args) == 1
                if Ex == impt.args[1]
                    found = true
                    break
                else
                    if isdefined(Main, impt.args[1]) && getfield(Main, impt.args[1]) isa Module && Ex in names(getfield(Main, impt.args[1]))
                        found = true
                        break
                    end
                end
            else
                if Ex == impt.args[end]
                    found = true
                    break
                end
            end
        end
    end
    if !found
        loc = s.current.offset + (0:sizeof(x.val))
        push!(L.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.PossibleTypo}(loc, [], "Possible use of undeclared variable $(x.val)"))
    end
end

function lint(x::EXPR{CSTParser.Quotenode}, s::Scope, L::LintState, server, istop)
end

function lint(x::EXPR{CSTParser.Quote}, s::Scope, L::LintState, server, istop)
    # NEEDS FIX: traverse args only linting -> x isa EXPR{UnarySyntaxOpCall} && x.args[1] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.PlusOp, Tokens.EX_OR}
end


# Types
function lint(x::EXPR{T}, s::Scope, L::LintState, server, istop) where T <: Union{CSTParser.Struct,CSTParser.Mutable}
    # NEEDS FIX: allow use of undeclared parameters
end

function lint(x::EXPR{CSTParser.Abstract}, s::Scope, L::LintState, server, istop)
    # NEEDS FIX: allow use of undeclared parameters
end


function lint(x::EXPR{CSTParser.Macro}, s::Scope, L::LintState, server, istop)
    s.current.offset += x.args[1].span + x.args[2].span
    get_symbols(x.args[2], s, L)
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.x_Str}, s::Scope, L::LintState, server, istop)
    s.current.offset += x.args[1].span
    lint(x.args[2], s, L, server, istop)
end


function lint(x::EXPR{CSTParser.Const}, s::Scope, L::LintState, server, istop)
    # NEEDS FIX: skip if declaring parameterised type alias
    if x.args[2] isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[2].args[1] isa EXPR{CSTParser.Curly} && x.args[2].args[3] isa EXPR{CSTParser.Curly}
    else
        invoke(lint, Tuple{EXPR,Scope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end

function lint(x::EXPR{T}, s::Scope, L::LintState, server, istop) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
end



function lint(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::Scope, L::LintState, server, istop)
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DotOp,Tokens.DOT,false}}
        # NEEDS FIX: check whether module or field of type
        lint(x.args[1], s, L, server, istop)
    elseif x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}} 
        offset = s.current.offset
        params = CSTParser._get_fparams(x)
        for p in params
            push!(s.symbols, (Variable(p, :DataType, x.args[3]), s.current.offset + (0:x.span), s.current.uri))
            add_name!(L.symbols, p)
            if !isempty(L.locals)
                add_name!(last(L.locals), p)
            end
        end

        invoke(lint, Tuple{EXPR,Scope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    else
        invoke(lint, Tuple{EXPR,Scope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end

function lint(x::EXPR, s::Scope, L::LintState, server, istop) 
    for a in x.args
        offset = s.current.offset
        if istop
            L.ntop += length(x.defs)
        else
            get_symbols(a, s, L)
        end

        if ismodule(a)
            # get_module(a, s, server)
        elseif contributes_scope(a)
            lint(a, s, L, server, istop)
        else
            nls = length(s.symbols)
            push!(L.locals, Dict{Any,Int}())
            lint(a, s, L, server, false)
            deleteat!(s.symbols, nls + 1:length(s.symbols))
            for k in keys(pop!(L.locals))
                remove_name!(L.symbols, k)
            end
        end
        s.current.offset = offset + a.span
    end
    return 
end

function get_symbols(x, s::Scope, L::LintState) end
function get_symbols(x::EXPR, s::Scope, L::LintState)
    for v in x.defs
        push!(s.symbols, (v, s.current.offset + (1:x.span), s.current.uri))
        add_name!(L.symbols, v.id)
        if !isempty(L.locals)
            add_name!(last(L.locals), v.id)
        end
    end
end

function get_symbols(x::EXPR{T}, s::Scope, L::LintState) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    get_symbols(x, s)
end
