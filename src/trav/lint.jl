@enum(LintCodes,
DuplicateArgumentName,
ArgumentFunctionNameConflict,
SlurpingPosition,
KWPosition,
ImportInFunction,
DuplicateArgument,
LetNonAssignment,
RangeNonAssignment,
CondAssignment,
DeadCode,
DictParaMisSpec,
DictGenAssignment,
MisnamedConstructor,
LoopOverSingle,
AssignsToFuncName,
PossibleTypo,

Deprecation,
functionDeprecation,
typeDeprecation,
immutableDeprecation,
abstractDeprecation,
bitstypeDeprecation,
typealiasDeprecation,
parameterisedDeprecation)

mutable struct LintState
    ns::Vector{Union{Symbol,EXPR}}
    diagnostics::Vector{LSDiagnostic}
    locals::Vector{Set{String}}
end

function lint(doc::Document, server)
    uri = doc._uri
    server.debug_mode && (info("linting $uri"); tic())
    # Find top file of include tree
    path, namespace = findtopfile(uri, server)

    s = TopLevelScope(ScopePosition(uri, typemax(Int)), ScopePosition(last(path), 0), false, Dict(), EXPR[], Symbol[], true, true, Dict("toplevel" => []), [])
    toplevel(server.documents[last(path)].code.ast, s, server)

    current_namespace = isempty(s.namespace) ? "toplevel" : join(reverse(s.namespace), ".")
    
    s.current = ScopePosition(uri)
    s.namespace = namespace

    L = LintState(reverse(namespace), [], [])
    lint(doc.code.ast, s, L, server, true)
    server.debug_mode && info("linting $uri: done ($(toq()))")
    return L
end

function lint(x::EXPR, s::TopLevelScope, L::LintState, server, istop) 
    for a in x.args
        offset = s.current.offset
        if istop
        else
            get_symbols(a, s, L)
        end

        if contributes_scope(a)
            lint(a, s, L, server, istop)
        else
            if ismodule(a)
                push!(s.namespace, a.args[2].val)
            end
            # Add new local scope
            if !(a isa EXPR{IDENTIFIER})
                push!(L.locals, Set{String}())
            end
            lint(a, s, L, server, ismodule(a))
            
            # Delete local scope
            if !(a isa EXPR{IDENTIFIER})
                for k in pop!(L.locals)
                    remove_symbol(s.symbols, k)
                end
            end
            if ismodule(a)
                pop!(s.namespace)
            end
        end
        s.current.offset = offset + a.fullspan
    end
    return
end

function lint(x::EXPR{IDENTIFIER}, s::TopLevelScope, L::LintState, server, istop)
    Ex = Symbol(x.val)
    nsEx = make_name(s.namespace, x.val)
    found = Ex in BaseCoreNames

    if x.val == "FloatRange" && !(nsEx in keys(s.symbols))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.fullspan), "StepRangeLen")], "Use of deprecated `FloatRange`, use `StepRangeLen` instead."))
    end

    if !found
        if haskey(s.symbols, x.val)
            found = true
        end
    end
    if !found
        if haskey(s.symbols, nsEx)
            found = true
        end
    end
    
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")

    if !found && haskey(s.imports, ns)
        for (impt, loc, uri) in s.imports[ns]
            if Ex == impt.args[1]
                found = true
                break
            elseif length(impt.args) == 1
                if Ex == impt.args[1]
                    found = true
                    break
                else
                    if isdefined(Main, impt.args[1]) && getfield(Main, impt.args[1]) isa Module && Ex in names(getfield(Main, impt.args[1]))
                        found = true
                        break
                    end
                end
            elseif Ex == impt.args[end]
                found = true
                break
            elseif impt.head == :using && length(impt.args) == 2 && isdefined(Main, impt.args[1]) && isdefined(Main, impt.args[2])
                m = getfield(Main, impt.args[1])
                m = getfield(m, impt.args[2])
                if m isa Module && Ex in names(m)
                    found = true
                    break
                end
            elseif impt.head == :using && length(impt.args) == 3 && isdefined(Main, impt.args[1]) && isdefined(Main, impt.args[2]) && isdefined(Main, impt.args[3])
                m = getfield(Main, impt.args[1])
                m = getfield(m, impt.args[2])
                m = getfield(m, impt.args[3])
                if m isa Module && Ex in names(m)
                    found = true
                    break
                end
            end
        end
    end
    if !found
        loc = s.current.offset + (0:sizeof(x.val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Possible use of undeclared variable $(x.val)"))
    end
end



function lint(x::EXPR{CSTParser.Call}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa EXPR{IDENTIFIER}
        nsEx = make_name(s.namespace, x.val)
        # l127 : 1 arg version of `write`
        if x.args[1].val == "write" && length(x.args) == 4 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [], "Use of deprecated function form"))

            # may need fixing for triple quoted strgins
            arg = CSTParser.isstring(x.args[3]) ? string('\"', x.args[3].val, '\"') : Expr(x.args[3])
            
            push!(last(L.diagnostics).actions, TextEdit(s.current.offset + (0:x.fullspan), string("write(STDOUT, ", arg, ")")))
        # l129 : 3 arg version of `delete!`
        elseif x.args[1].val == "delete!" && length(x.args) == 8 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "pop!")], "`delete!(ENV, k, def)` should be replaced with `pop!(ENV, k, def)`. Be aware that `pop!` returns `k` or `def`, while `delete!` returns `ENV` or `def`."))
        # l372 : ipermutedims
        elseif x.args[1].val == "ipermutedims" && length(x.args) == 6 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:4) + (0:x.args[5].fullspan), string("invperm(", Expr(x.args[5]), ")")),
                DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "permutedims")
            ], "Use of deprecated function"))
        # l381 : is(a, b) -> a === b
        elseif x.args[1].val == "is" && length(x.args) == 6 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:5) + (0:x.args[6].fullspan), ""),
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:3) + (0:x.args[4].fullspan), " === "),
                DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "")
            ], "Use of deprecated function"))
        # l465
        elseif x.args[1].val == "den" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "denominator")], "Use of deprecated function"))
        # l466
        elseif x.args[1].val == "num" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "numerator")], "Use of deprecated function"))
        # l471
        elseif x.args[1].val == "takebuf_array" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "take!")], "Use of deprecated function"))
        # l472
        elseif x.args[1].val == "takebuf_string" && length(x.args) == 4 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:3) + (0:x.args[4].fullspan), "))"),
                DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "String(take!")
            ], "Use of deprecated function"))
        # l527/528 : sumabs(args...) -> sum(abs, args...)
        elseif x.args[1].val == "sumabs" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "sum(abs, ")], "Use of deprecated function"))
        # l529/530 : sumabs2(args...) -> sum(abs2, args...)
        elseif x.args[1].val == "sumabs2" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "sum(abs2, ")], "Use of deprecated function"))
        # l531/532 : minabs(args...) -> minimum(abs, args...)
        elseif x.args[1].val == "minabs" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "minimum(abs, ")], "Use of deprecated function"))
        # l533/534 : maxabs(args...) -> maximum(abs, args...)
        elseif x.args[1].val == "maxabs" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "maximum(abs, ")], "Use of deprecated function"))
        elseif x.args[1].val == "quadgk" && !(nsEx in keys(s.symbols))
            ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
            isimported = false
            if haskey(s.imports, ns)
                for (impt, loc, uri) in s.imports[ns]
                    if (impt.head == :using && impt.args[1] == :QuadGK) || (impt.head == :import && last(impt.args) == :quadgk)
                        isimported = true
                    end
                end
            end
            if !isimported
                push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [], "`quadgk` has been moved to the package QuadGK.jl.\nRun Pkg.add(\"QuadGK\") to install QuadGK on Julia v0.6 and later, and then run `using QuadGK`."))
            end
        elseif x.args[1].val == "bitbroadcast" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "broadcast")], "Use of deprecated function"))
        elseif x.args[1].val == "include"
            file = x.args[3].val
            uri = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), normpath(file))
            if !(isincludable(x) && uri in keys(server.documents))
                tws = CSTParser.trailing_ws_length(CSTParser.get_last_token(x))
                push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.fullspan - tws), [], "Could not include $file"))
            end
        end
    end

    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.ModuleH}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].fullspan + x.args[2].fullspan
    lint(x.args[3], s, L, server, istop)
end

function _lint_sig(sig1, s, L, fname, offset)
    sig = sig1
    while sig isa EXPR{CSTParser.BinarySyntaxOpCall} && (sig.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DeclarationOp,Tokens.DECLARATION,false}} || sig.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}})
        sig = sig.args[1]
    end
    if sig isa EXPR{Call} && sig.args[1] isa EXPR{CSTParser.Curly} && !(sig.args[1].args[1] isa EXPR{CSTParser.InvisBrackets} && sig.args[1].args[1].args[2] isa EXPR{CSTParser.UnarySyntaxOpCall} && sig.args[1].args[1].args[2].args[1] isa EXPR{CSTParser.OPERATOR{CSTParser.DeclarationOp,Tokens.DECLARATION,false}})
        push!(L.diagnostics, LSDiagnostic{parameterisedDeprecation}((offset + sig.args[1].args[1].fullspan):(offset + sig.args[1].fullspan), [], "Use of deprecated parameter syntax"))
        
        trailingws = last(sig.args) isa EXPR{CSTParser.PUNCTUATION{Tokens.RPAREN}} ? last(sig.args).fullspan - 1 : 0
        loc1 = offset + sig.fullspan - trailingws

        push!(last(L.diagnostics).actions, DocumentFormat.TextEdit(loc1:loc1, string(" where {", join((Expr(t) for t in sig.args[1].args[2:end] if !(t isa EXPR{P} where P <: CSTParser.PUNCTUATION) ), ","), "}")))
        push!(last(L.diagnostics).actions, DocumentFormat.TextEdit((offset + sig.args[1].args[1].fullspan):(offset + sig.args[1].fullspan), ""))
    end

    firstkw = 0
    argnames = []
    for i = 2:length(sig.args)
        arg = sig.args[i]
        if !(arg isa EXPR{P} where P <: CSTParser.PUNCTUATION)
            arg_id = CSTParser._arg_id(arg).val

            if arg_id in argnames
                tws = CSTParser.trailing_ws_length(CSTParser.get_last_token(sig))
                push!(L.diagnostics, LSDiagnostic{DuplicateArgumentName}(offset + (0:sig.fullspan - tws), [], "Use of duplicate argument names"))
            end

            push!(argnames, arg_id)
            if fname != "" && fname in argnames
                tws = CSTParser.trailing_ws_length(CSTParser.get_last_token(sig))
                push!(L.diagnostics, LSDiagnostic{DuplicateArgumentName}(offset + (0:sig.fullspan - tws), [], "Use of function name as argument name"))
            end
            if firstkw > 0 && i > firstkw && !(arg isa EXPR{CSTParser.Kw})

            end
        end
    end
end

function lint(x::EXPR{CSTParser.FunctionDef}, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    fname = CSTParser._get_fname(x).val
    s.current.offset += x.args[1].fullspan
    _fsig_scope(x.args[2], s, server, last(L.locals))
    _lint_sig(x.args[2], s, L, fname, s.current.offset)

    s.current.offset = offset
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Macro}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX
    offset = s.current.offset
    fname = string("@", CSTParser._get_fname(x.args[2]).val)
    s.current.offset += x.args[1].fullspan
    _fsig_scope(x.args[2], s, server, last(L.locals))
    # _lint_sig(x.args[2], s, L, fname, s.current.offset + x.args[1].fullspan)
    s.current.offset += x.args[2].fullspan
    lint(x.args[3], s, L, server, istop)
    # invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Try}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX
    offset = s.current.offset
    s.current.offset += x.args[1].fullspan
    push!(L.locals, Set{String}())
    lint(x.args[2], s, L, server, istop)
    for k in pop!(L.locals)
        remove_symbol(s.symbols, k)
    end
    s.current.offset = offset + sum(x.args[i].fullspan for i = 1:3)
    push!(L.locals, Set{String}())
    _try_scope(x, s, server)
    for i = 4:length(x.args)
        s.current.offset = offset + sum(x.args[j].fullspan for j = 1:i - 1)
        lint(x.args[i], s, L, server, istop)
    end
    for k in pop!(L.locals)
        remove_symbol(s.symbols, k)
    end
end

function lint(x::EXPR{CSTParser.Kw}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].fullspan + x.args[2].fullspan
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Generator}, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    for i = 3:length(x.args)
        r = x.args[i]
        _for_scope(r, s, server, last(L.locals))
        offset += r.fullspan
    end
    s.current.offset = offset
    lint(x.args[1], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Quotenode}, s::TopLevelScope, L::LintState, server, istop)
end

function lint(x::EXPR{CSTParser.Quote}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: traverse args only linting -> x isa EXPR{UnarySyntaxOpCall} && x.args[1] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.PlusOp, Tokens.EX_OR}
end

function lint(x::EXPR{CSTParser.StringH}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: StringH constructor must track whether initial token is 
    # a STRING or TRIPLE_STRING in order to calculate offsets.
end


# Types
function lint(x::EXPR{CSTParser.Mutable}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa EXPR{CSTParser.KEYWORD{Tokens.TYPE}}
        push!(L.diagnostics, LSDiagnostic{typeDeprecation}(s.current.offset + (0:4), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "mutable struct ")], "Use of deprecated `type` syntax"))

        name = CSTParser.get_id(x.args[2])
        nsEx = make_name(s.namespace, name.val)
        if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
            loc = s.current.offset + x.args[1].fullspan + (0:sizeof(name.val))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
        end
        offset = s.current.offset + x.args[1].fullspan + x.args[2].fullspan
        for a in x.args[3].args
            if CSTParser.declares_function(a)
                fname = CSTParser._get_fname(CSTParser._get_fsig(a))
                if fname.val != name.val && !(fname isa EXPR{CSTParser.InvisBrackets} && fname.args[2] isa EXPR{CSTParser.UnarySyntaxOpCall} && fname.args[2].args[1] isa EXPR{CSTParser.OPERATOR{CSTParser.DeclarationOp,Tokens.DECLARATION,false}})
                    push!(L.diagnostics, LSDiagnostic{MisnamedConstructor}(offset + (0:a.fullspan), [], "Constructor name does not match type name"))
                end
            end
            offset += a.fullspan
        end
    else
        name = CSTParser.get_id(x.args[3])
        nsEx = make_name(s.namespace, name.val)
        if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
            loc = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + (0:sizeof(name.val))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
        end
        offset = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + x.args[3].fullspan
        for a in x.args[4].args
            if CSTParser.declares_function(a)
                fname = CSTParser._get_fname(CSTParser._get_fsig(a))
                if fname.val != name.val
                    push!(L.diagnostics, LSDiagnostic{MisnamedConstructor}(offset + (0:a.fullspan), [], "Constructor name does not match type name"))
                end
            end
            offset += a.fullspan
        end
    end
end

function lint(x::EXPR{CSTParser.Struct}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa EXPR{CSTParser.KEYWORD{Tokens.IMMUTABLE}}
        push!(L.diagnostics, LSDiagnostic{immutableDeprecation}(s.current.offset + (0:9), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "struct ")], "Use of deprecated `immutable` syntax"))
    end
    name = CSTParser.get_id(x.args[2])
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + x.args[1].fullspan + (0:sizeof(name.val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end
    offset = s.current.offset + x.args[1].fullspan + x.args[2].fullspan
    for a in x.args[3].args
        if CSTParser.declares_function(a)
            fname = CSTParser._get_fname(CSTParser._get_fsig(a))
            if fname.val != name.val
                push!(L.diagnostics, LSDiagnostic{MisnamedConstructor}(offset + (0:a.fullspan), [], "Constructor name does not match type name"))
            end
        end
        offset += a.fullspan
    end
end

function lint(x::EXPR{CSTParser.ERROR}, s::TopLevelScope, L::LintState, server, istop)
end

function lint(x::EXPR{CSTParser.Abstract}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: allow use of undeclared parameters
    if length(x.args) == 2 # deprecated syntax
        offset = x.args[1].fullspan
        l_pos = s.current.offset + x.fullspan - trailing_ws_length(get_last_token(x))
        decl = x.args[2]
        push!(L.diagnostics, LSDiagnostic{abstractDeprecation}(s.current.offset + (0:8), [DocumentFormat.TextEdit(l_pos:l_pos, " end"), DocumentFormat.TextEdit(s.current.offset + (0:offset), "abstract type ")], "This specification for abstract types is deprecated"))
    else
        offset = x.args[1].fullspan + x.args[2].fullspan
        decl = x.args[3]
    end
    name = CSTParser.get_id(decl)
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + offset + (0:sizeof(name.val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end
end

function lint(x::EXPR{CSTParser.Bitstype}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].fullspan + x.args[2].fullspan
    
    push!(L.diagnostics, LSDiagnostic{bitstypeDeprecation}(s.current.offset + (0:8), [DocumentFormat.TextEdit(s.current.offset + (0:(x.fullspan)), string("primitive type ", Expr(x.args[3]), " ", Expr(x.args[2]), " end"))], "This specification for primitive types is deprecated"))
    
    name = CSTParser.get_id(x.args[3])
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + offset + (0:sizeof(name.val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end

    if x.args[2] isa EXPR{CSTParser.LITERAL{Tokens.INTEGER}} && mod(Expr(x.args[2]), 8) != 0
        loc = s.current.offset + x.args[1].fullspan + (0:sizeof(x.args[2].val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Invalid number of bits in primitive type $(name.val)"))
    end
end

function lint(x::EXPR{CSTParser.Primitive}, s::TopLevelScope, L::LintState, server, istop)
    name = CSTParser.get_id(x.args[3])
    nsEx = make_name(s.namespace, name.val)
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx])[2]) == s.current.offset)
        loc = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + (0:sizeof(name.val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end

    if x.args[4] isa EXPR{CSTParser.LITERAL{Tokens.INTEGER}} && mod(Expr(x.args[4]), 8) != 0
        loc = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + x.args[3].fullspan + (0:sizeof(x.args[4].val))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Invalid number of bits in primitive type $(name.val)"))
    end
end

function lint(x::EXPR{CSTParser.TypeAlias}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].fullspan
    lt = CSTParser.get_last_token(x)
    tws = CSTParser.trailing_ws_length(lt)
    push!(L.diagnostics, LSDiagnostic{typealiasDeprecation}(s.current.offset + (0:9), [DocumentFormat.TextEdit(s.current.offset + (0:(x.fullspan - tws)), string("const ", Expr(x.args[2]), " = ", Expr(x.args[3])))], "This specification for type aliases is deprecated"))
end

# function lint(x::EXPR{CSTParser.Macro}, s::TopLevelScope, L::LintState, server, istop)
#     s.current.offset += x.args[1].fullspan + x.args[2].fullspan
#     mname = CSTParser._get_fname(x).val
#     _lint_sig(x.args[2], s, L, mname, s.current.offset)
#     lint(x.args[3], s, L, server, istop)
# end

function lint(x::EXPR{CSTParser.x_Str}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].fullspan
    lint(x.args[2], s, L, server, istop)
end


function lint(x::EXPR{CSTParser.Const}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: skip if declaring parameterised type alias
    if x.args[2] isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[2].args[1] isa EXPR{CSTParser.Curly} && x.args[2].args[3] isa EXPR{CSTParser.Curly}
    else
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end

function lint(x::EXPR{CSTParser.For}, s::TopLevelScope, L::LintState, server, istop)
    s.current.offset += x.args[1].fullspan
    _for_scope(x.args[2], s, server, last(L.locals))
    if x.args[2] isa EXPR{Block}
        for r in x.args[2].args
            _lint_range(r, s, L)
            s.current.offset += r.fullspan
        end
    else
        _lint_range(x.args[2], s, L)
        get_symbols(x.args[2], s, L)
    end
    s.current.offset += x.args[2].fullspan
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Do}, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    lint(x.args[1], s, L, server, istop)
    s.current.offset = offset + x.args[1].fullspan + x.args[2].fullspan
    _do_scope(x, s, server, last(L.locals))
    lint(x.args[3], s, L, server, istop)
    s.current.offset = offset + sum(x.args[i].fullspan for i = 1:3)
    
    lint(x.args[4], s, L, server, istop)
end

function _lint_range(x::EXPR{CSTParser.BinaryOpCall}, s::TopLevelScope, L::LintState)
    if ((x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.ComparisonOp,Tokens.IN,false}} || x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.ComparisonOp,Tokens.ELEMENT_OF,false}}))
        if x.args[3] isa EXPR{L} where L <: LITERAL
            push!(L.diagnostics, LSDiagnostic{LoopOverSingle}(s.current.offset + (0:x.fullspan), [], "You are trying to loop over a single instance"))
        end
    else
        push!(L.diagnostics, LSDiagnostic{RangeNonAssignment}(s.current.offset + (0:x.fullspan), [], "You must assign (using =, in or ∈) in a range")) 
    end
end

function _lint_range(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::TopLevelScope, L::LintState)
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AssignmentOp,Tokens.EQ,false}}
        if x.args[3] isa EXPR{L} where L <: LITERAL
            push!(L.diagnostics, LSDiagnostic{LoopOverSingle}(s.current.offset + (0:x.fullspan), [], "You are trying to loop over a single instance"))
        end
    end
end

function _lint_range(x, s::TopLevelScope, L::LintState)
    push!(L.diagnostics, LSDiagnostic{RangeNonAssignment}(s.current.offset + (0:x.fullspan), [], "You must assign (using =, in or ∈) in a range")) 
end

function _lint_range(x::EXPR{P}, s::TopLevelScope, L::LintState) where P <: CSTParser.PUNCTUATION
end

function lint(x::EXPR{CSTParser.If}, s::TopLevelScope, L::LintState, server, istop) 
    cond = x.args[2]
    if cond isa EXPR{CSTParser.BinarySyntaxOpCall} && cond.args[2] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.AssignmentOp}
        push!(L.diagnostics, LSDiagnostic{CondAssignment}(s.current.offset + x.args[1].fullspan + (0:cond.fullspan), [], "An assignment rather than comparison operator has been used"))
    end
    if cond isa EXPR{LITERAL{Tokens.TRUE}}
        if length(x.args) == 6
            push!(L.diagnostics, LSDiagnostic{DeadCode}(s.current.offset + x.args[1].fullspan + cond.fullspan + x.args[3].fullspan + x.args[4].fullspan + (0:x.args[5].fullspan), [], "This code is never reached"))
        end
    elseif cond isa EXPR{LITERAL{Tokens.FALSE}}
        push!(L.diagnostics, LSDiagnostic{DeadCode}(s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan + x.args[3].fullspan), [], "This code is never reached"))
    end
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.While}, s::TopLevelScope, L::LintState, server, istop) 
    # Linting
    if x.args[2] isa EXPR{CSTParser.BinarySyntaxOpCall} && x.args[2].args[2] isa EXPR{OP} where OP <: CSTParser.OPERATOR{CSTParser.AssignmentOp}
        push!(L.diagnostics, LSDiagnostic{CondAssignment}(s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan), [], "An assignment rather than comparison operator has been used"))
    elseif x.args[2] isa EXPR{LITERAL{Tokens.FALSE}}
        push!(L.diagnostics, LSDiagnostic{DeadCode}(s.current.offset + (0:x.fullspan), [], "This code is never reached"))
    end
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end



function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Local,CSTParser.Global}
    if length(x.args) > 2
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end

function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    #  NEEDS FIX: 
end

function lint(x::EXPR{CSTParser.Export}, s::TopLevelScope, L::LintState, server, istop)
    
    exported_names = Set{String}()
    for a in x.args
        if a isa EXPR{IDENTIFIER}
            loc = s.current.offset + (0:sizeof(x.val))
            if a.val in exported_names
                push!(L.diagnostics, LSDiagnostic{DuplicateArgument}(loc, [], "Variable $(x.val) is already exported"))
            else
                push!(exported_names, a.val)
            end

            lint(a, s, L, server, istop)
        end
        s.current.offset += a.fullspan
    end
end

function lint(x::EXPR{CSTParser.BinarySyntaxOpCall}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.DotOp,Tokens.DOT,false}}
        # NEEDS FIX: check whether module or field of type
        lint(x.args[1], s, L, server, istop)
    elseif x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.WhereOp,Tokens.WHERE,false}} 
        offset = s.current.offset
        params = CSTParser._get_fparams(x)
        for p in params
            name = make_name(isempty(s.namespace) ? "toplevel" : s.namespace, p)
            v = Variable(p, :DataType, x.args[3])
            if haskey(s.symbols, name)
                push!(s.symbols[name], (v, s.current.offset + (1:x.fullspan), s.current.uri))
            else
                s.symbols[name] = [(v, s.current.offset + (1:x.fullspan), s.current.uri)]
            end
            push!(last(L.locals), name)
        end

        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    elseif CSTParser.declares_function(x)
        fname = CSTParser._get_fname(x.args[1])
        _lint_sig(x.args[1], s, L, fname, s.current.offset)
        _fsig_scope(x.args[1], s, server, last(L.locals))
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    elseif x.args[2] isa EXPR{CSTParser.OPERATOR{CSTParser.AnonFuncOp,Tokens.ANON_FUNC,false}}
        _anon_func_scope(x, s, server, last(L.locals))
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    else
        invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
    end
end


function get_symbols(x, s::TopLevelScope, L::LintState) end
function get_symbols(x::EXPR, s::TopLevelScope, L::LintState)
    for v in get_defs(x)
        name = make_name(s.namespace, v.id)
        var_item = (v, s.current.offset + (0:x.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = [var_item]
        end
        push!(last(L.locals), name)
    end
end


function remove_symbol(symbols, id)
    if haskey(symbols, id)
        if length(symbols[id]) == 1
            delete!(symbols, id)
        else
            pop!(symbols[id])
        end
    else
        warn("Tried to remove nonexistant symbol: $(id)")
    end
end
