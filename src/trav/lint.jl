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

    s = TopLevelScope(ScopePosition(uri, typemax(Int)), ScopePosition(last(path), 0), false, Dict(), EXPR[], Symbol[], true, true, Dict{String,Set{String}}("toplevel" => Set{String}()), Dict{String,Set{String}}("toplevel" => Set{String}()), [])
    toplevel(server.documents[last(path)].code.ast, s, server)

    s.current = ScopePosition(uri)
    s.namespace = namespace

    L = LintState(reverse(namespace), [], [])
    lint(doc.code.ast, s, L, server, true)
    server.debug_mode && info("linting $uri: done ($(toq()))")
    return L
end

# Leaf nodes

function lint(x::IDENTIFIER, s::TopLevelScope, L::LintState, server, istop)
    Ex = Symbol(str_value(x))
    nsEx = make_name(s.namespace, str_value(x))
    found = Ex in BaseCoreNames

    if str_value(x) == "FloatRange" && !(nsEx in keys(s.symbols))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.fullspan), "StepRangeLen")], "Use of deprecated `FloatRange`, use `StepRangeLen` instead."))
    end

    if !found
        if haskey(s.symbols, str_value(x))
            found = true
        end
    end
    if !found
        if haskey(s.symbols, nsEx)
            found = true
        end
    end
    
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")

    if !found && haskey(s.imported_names, ns)
        if string(Ex) in s.imported_names[ns]
            found = true
        end
    end
    
    if !found
        loc = s.current.offset + (0:sizeof(str_value(x)))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Possible use of undeclared variable $(str_value(x))"))
    end
end

function lint(x::KEYWORD, s::TopLevelScope, L::LintState, server, istop) end
function lint(x::LITERAL, s::TopLevelScope, L::LintState, server, istop) end
function lint(x::OPERATOR, s::TopLevelScope, L::LintState, server, istop) end
function lint(x::PUNCTUATION, s::TopLevelScope, L::LintState, server, istop) end


function lint(x::EXPR, s::TopLevelScope, L::LintState, server, istop) 
    for a in x
        offset = s.current.offset
        if istop
        else
            get_symbols(a, s, L)
        end

        if contributes_scope(a)
            lint(a, s, L, server, istop)
        else
            if ismodule(a)
                push!(s.namespace, str_value(a.args[2]))
            end
            # Add new local scope
            if !(a isa IDENTIFIER)
                push!(L.locals, Set{String}())
            end
            lint(a, s, L, server, ismodule(a))
            
            # Delete local scope
            if !(a isa IDENTIFIER)
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

function lint(x::UnaryOpCall, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    lint(x.op, s, L, server, istop)
    s.current.offset = offset + x.op.fullspan
    lint(x.arg, s, L, server, istop)
end

function lint(x::UnarySyntaxOpCall, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    lint(x.arg1, s, L, server, istop)
    s.current.offset = offset + x.arg1.fullspan
    lint(x.arg2, s, L, server, istop)
end

function lint(x::BinaryOpCall, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    lint(x.arg1, s, L, server, istop)
    s.current.offset = offset + x.arg1.fullspan + x.op.fullspan
    lint(x.arg2, s, L, server, istop)
end

function lint(x::BinarySyntaxOpCall, s::TopLevelScope, L::LintState, server, istop)
    if CSTParser.is_dot(x.op)
        # NEEDS FIX: check whether module or field of type
        lint(x.arg1, s, L, server, istop)
        return 
    elseif CSTParser.declares_function(x)
        fname = CSTParser._get_fname(x.arg1)
        _lint_sig(x.arg1, s, L, fname, s.current.offset)
        _fsig_scope(x.arg1, s, server, last(L.locals))
    elseif CSTParser.is_anon_func(x.op)
        _anon_func_scope(x, s, server, last(L.locals))
    end
    offset = s.current.offset
    lint(x.arg1, s, L, server, istop)
    s.current.offset = offset + x.arg1.fullspan + x.op.fullspan
    lint(x.arg2, s, L, server, istop)
end

function lint(x::WhereOpCall, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    params = CSTParser._get_fparams(x)
    for p in params
        name = make_name(isempty(s.namespace) ? "toplevel" : s.namespace, p)
        v = Variable(p, :DataType, x.args)
        if haskey(s.symbols, name)
            push!(s.symbols[name], VariableLoc(v, s.current.offset + (1:x.fullspan), s.current.uri))
        else
            s.symbols[name] = VariableLoc[VariableLoc(v, s.current.offset + (1:x.fullspan), s.current.uri)]
        end
        push!(last(L.locals), name)
    end
    offset = s.current.offset
    lint(x.arg1, s, L, server, istop)
    # s.current.offset = offset + x.arg1.fullspan + x.op.fullspan

    # lint(x.arg2, s, L, server, istop)
end

function lint(x::ConditionalOpCall, s::TopLevelScope, L::LintState, server, istop)  
    offset = s.current.offset
    lint(x.cond, s, L, server, istop)
    s.current.offset = offset + x.cond.fullspan + x.op1.fullspan
    lint(x.arg1, s, L, server, istop)
    s.current.offset = offset + x.cond.fullspan + x.op1.fullspan + x.arg1.fullspan + x.op2.fullspan
    lint(x.arg2, s, L, server, istop)
end


function lint(x::EXPR{CSTParser.MacroName}, s::TopLevelScope, L::LintState, server, istop)
    x1 = IDENTIFIER(x.fullspan, x.span, string("@", str_value(x.args[2])))
    lint(x1, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.MacroCall}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa EXPR{CSTParser.MacroName} && str_value(x.args[1].args[2]) in keys(MacroList) && !MacroList[str_value(x.args[1].args[2])].lint
        return
    end
    return invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end


function lint(x::EXPR{CSTParser.Call}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa IDENTIFIER
        nsEx = make_name(s.namespace, str_value(x.args[1]))
        # l127 : 1 arg version of `write`
        if str_value(x.args[1]) == "write" && length(x.args) == 4 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [], "Use of deprecated function form"))

            # may need fixing for triple quoted strgins
            arg = CSTParser.isstring(x.args[3]) ? string('\"', str_value(x.args[3]), '\"') : Expr(x.args[3])
            
            push!(last(L.diagnostics).actions, DocumentFormat.TextEdit(s.current.offset + (0:x.fullspan), string("write(STDOUT, ", arg, ")")))
        # l129 : 3 arg version of `delete!`
        elseif str_value(x.args[1]) == "delete!" && length(x.args) == 8 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "pop!")], "`delete!(ENV, k, def)` should be replaced with `pop!(ENV, k, def)`. Be aware that `pop!` returns `k` or `def`, while `delete!` returns `ENV` or `def`."))
        # l372 : ipermutedims
        elseif str_value(x.args[1]) == "ipermutedims" && length(x.args) == 6 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:4) + (0:x.args[5].fullspan), string("invperm(", Expr(x.args[5]), ")")),
                DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "permutedims")
            ], "Use of deprecated function"))
        # l381 : is(a, b) -> a === b
        elseif str_value(x.args[1]) == "is" && length(x.args) == 6 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:5) + (0:x.args[6].fullspan), ""),
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:3) + (0:x.args[4].fullspan), " === "),
                DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "")
            ], "Use of deprecated function"))
        # l465
        elseif str_value(x.args[1]) == "den" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "denominator")], "Use of deprecated function"))
        # l466
        elseif str_value(x.args[1]) == "num" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "numerator")], "Use of deprecated function"))
        # l471
        elseif str_value(x.args[1]) == "takebuf_array" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "take!")], "Use of deprecated function"))
        # l472
        elseif str_value(x.args[1]) == "takebuf_string" && length(x.args) == 4 && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [
                DocumentFormat.TextEdit(s.current.offset + sum(x.args[i].fullspan for i = 1:3) + (0:x.args[4].fullspan), "))"),
                DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "String(take!")
            ], "Use of deprecated function"))
        # l527/528 : sumabs(args...) -> sum(abs, args...)
        elseif str_value(x.args[1]) == "sumabs" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "sum(abs, ")], "Use of deprecated function"))
        # l529/530 : sumabs2(args...) -> sum(abs2, args...)
        elseif str_value(x.args[1]) == "sumabs2" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "sum(abs2, ")], "Use of deprecated function"))
        # l531/532 : minabs(args...) -> minimum(abs, args...)
        elseif str_value(x.args[1]) == "minabs" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "minimum(abs, ")], "Use of deprecated function"))
        # l533/534 : maxabs(args...) -> maximum(abs, args...)
        elseif str_value(x.args[1]) == "maxabs" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:sum(x.args[i].fullspan for i = 1:2)) , "maximum(abs, ")], "Use of deprecated function"))
        elseif str_value(x.args[1]) == "quadgk" && !(nsEx in keys(s.symbols))
            ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
            if !("quadgk" in s.imported_names[ns])
                push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [], "`quadgk` has been moved to the package QuadGK.jl.\nRun Pkg.add(\"QuadGK\") to install QuadGK on Julia v0.6 and later, and then run `using QuadGK`."))
            end
        elseif str_value(x.args[1]) == "bitbroadcast" && !(nsEx in keys(s.symbols))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(s.current.offset + (0:x.args[1].fullspan), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "broadcast")], "Use of deprecated function"))
        elseif str_value(x.args[1]) == "include"
            file = str_value(x.args[3])
            uri = isabspath(file) ? filepath2uri(file) : joinpath(dirname(s.current.uri), normpath(file))
            if !(isincludable(x) && uri in keys(server.documents))
                tws = CSTParser.trailing_ws_length(x)
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
    while sig isa WhereOpCall || (sig isa BinarySyntaxOpCall && CSTParser.is_decl(sig.op))
        sig = sig.arg1
    end
    if sig isa EXPR{Call} && sig.args[1] isa EXPR{CSTParser.Curly} && !(sig.args[1].args[1] isa EXPR{CSTParser.InvisBrackets} && sig.args[1].args[1].args[2] isa UnarySyntaxOpCall && CSTParser.is_decl(sig.args[1].args[1].args[2].arg1))
        push!(L.diagnostics, LSDiagnostic{parameterisedDeprecation}((offset + sig.args[1].args[1].fullspan):(offset + sig.args[1].fullspan), [], "Use of deprecated parameter syntax"))
        
        trailingws = CSTParser.is_rparen(last(sig.args)) ? last(sig.args).fullspan - 1 : 0
        loc1 = offset + sig.fullspan - trailingws

        push!(last(L.diagnostics).actions, DocumentFormat.TextEdit(loc1:loc1, string(" where {", join((Expr(t) for t in sig.args[1].args[2:end] if !(t isa PUNCTUATION) ), ","), "}")))
        push!(last(L.diagnostics).actions, DocumentFormat.TextEdit((offset + sig.args[1].args[1].fullspan):(offset + sig.args[1].fullspan), ""))
    end

    firstkw = 0
    argnames = []
    sig isa IDENTIFIER && return
    for (i, arg) = enumerate(sig)
        i == 1 && continue
        if !(arg isa PUNCTUATION)
            arg_id = str_value(CSTParser._arg_id(arg))

            if arg_id in argnames
                tws = CSTParser.trailing_ws_length(sig)
                push!(L.diagnostics, LSDiagnostic{DuplicateArgumentName}(offset + (0:sig.fullspan - tws), [], "Use of duplicate argument names"))
            end

            arg_id != "" && push!(argnames, arg_id)
            if fname != "" && fname in argnames
                tws = CSTParser.trailing_ws_length(sig)
                push!(L.diagnostics, LSDiagnostic{DuplicateArgumentName}(offset + (0:sig.fullspan - tws), [], "Use of function name as argument name"))
            end
            if firstkw > 0 && i > firstkw && !(arg isa EXPR{CSTParser.Kw})

            end
        end
    end
end

function lint(x::EXPR{CSTParser.FunctionDef}, s::TopLevelScope, L::LintState, server, istop)
    offset = s.current.offset
    fname = str_value(CSTParser._get_fname(x))
    s.current.offset += x.args[1].fullspan
    _fsig_scope(x.args[2], s, server, last(L.locals))
    _lint_sig(x.args[2], s, L, fname, s.current.offset)

    s.current.offset = offset
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Macro}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX
    offset = s.current.offset
    fname = string("@", str_value(CSTParser._get_fname(x.args[2])))
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
    s.current.offset += sum(x.args[i].fullspan for i = 1:2)
    for i = 3:length(x.args)
        r = x.args[i]
        _for_scope(r, s, server, last(L.locals))
        s.current.offset += r.fullspan
    end
    s.current.offset = offset
    lint(x.args[1], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Quotenode}, s::TopLevelScope, L::LintState, server, istop)
end

function lint(x::EXPR{CSTParser.Quote}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: traverse args only linting -> x isa EXPR{UnarySyntaxOpCall} && x.args[1] isa EXPR{OP} where OP <: OPERATOR{CSTParser.PlusOp, Tokens.EX_OR}
end

function lint(x::EXPR{CSTParser.StringH}, s::TopLevelScope, L::LintState, server, istop)
    # NEEDS FIX: StringH constructor must track whether initial token is 
    # a STRING or TRIPLE_STRING in order to calculate offsets.
end


# Types
function lint(x::EXPR{CSTParser.Mutable}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa KEYWORD && x.args[1].kind == Tokens.TYPE
        push!(L.diagnostics, LSDiagnostic{typeDeprecation}(s.current.offset + (0:4), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "mutable struct ")], "Use of deprecated `type` syntax"))

        name = CSTParser.get_id(x.args[2])
        nsEx = make_name(s.namespace, str_value(name))
        if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx]).loc) == s.current.offset)
            loc = s.current.offset + x.args[1].fullspan + (0:sizeof(str_value(name)))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
        end
        offset = s.current.offset + x.args[1].fullspan + x.args[2].fullspan
        for a in x.args[3].args
            if CSTParser.declares_function(a)
                fname = CSTParser._get_fname(CSTParser._get_fsig(a))
                if str_value(fname) != str_value(name) && !(fname isa EXPR{CSTParser.InvisBrackets} && fname.args[2] isa UnarySyntaxOpCall && CSTParser.is_decl(fname.args[2].arg1))
                    push!(L.diagnostics, LSDiagnostic{MisnamedConstructor}(offset + (0:a.fullspan), [], "Constructor name does not match type name"))
                end
            end
            offset += a.fullspan
        end
    else
        name = CSTParser.get_id(x.args[3])
        nsEx = make_name(s.namespace, str_value(name))
        if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx]).loc) == s.current.offset)
            loc = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + (0:sizeof(str_value(name)))
            push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
        end
        offset = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + x.args[3].fullspan
        for a in x.args[4].args
            if CSTParser.declares_function(a)
                fname = CSTParser._get_fname(CSTParser._get_fsig(a))
                if str_value(fname) != str_value(name)
                    push!(L.diagnostics, LSDiagnostic{MisnamedConstructor}(offset + (0:a.fullspan), [], "Constructor name does not match type name"))
                end
            end
            offset += a.fullspan
        end
    end
end

function lint(x::EXPR{CSTParser.Struct}, s::TopLevelScope, L::LintState, server, istop)
    if x.args[1] isa KEYWORD && x.args[1].kind == Tokens.IMMUTABLE
        push!(L.diagnostics, LSDiagnostic{immutableDeprecation}(s.current.offset + (0:9), [DocumentFormat.TextEdit(s.current.offset + (0:x.args[1].fullspan), "struct ")], "Use of deprecated `immutable` syntax"))
    end
    name = CSTParser.get_id(x.args[2])
    nsEx = make_name(s.namespace, str_value(name))
    if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx]).loc) == s.current.offset)
        loc = s.current.offset + x.args[1].fullspan + (0:sizeof(str_value(name)))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end
    offset = s.current.offset + x.args[1].fullspan + x.args[2].fullspan
    for a in x.args[3].args
        if CSTParser.declares_function(a)
            fname = CSTParser._get_fname(CSTParser._get_fsig(a))
            if str_value(fname) != str_value(name)
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
        l_pos = s.current.offset + x.fullspan - CSTParser.trailing_ws_length(x)
        decl = x.args[2]
        push!(L.diagnostics, LSDiagnostic{abstractDeprecation}(s.current.offset + (0:8), [DocumentFormat.TextEdit(l_pos:l_pos, " end"), DocumentFormat.TextEdit(s.current.offset + (0:offset), "abstract type ")], "This specification for abstract types is deprecated"))
    else
        offset = x.args[1].fullspan + x.args[2].fullspan
        decl = x.args[3]
    end
    name = CSTParser.get_id(decl)
    nsEx = make_name(s.namespace, str_value(name))
    if haskey(s.symbols, nsEx) && !(first(first(s.symbols[nsEx]).loc) == s.current.offset)
        loc = s.current.offset + offset + (0:sizeof(str_value(name)))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end
end

function lint(x::EXPR{CSTParser.Bitstype}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].fullspan + x.args[2].fullspan
    
    push!(L.diagnostics, LSDiagnostic{bitstypeDeprecation}(s.current.offset + (0:8), [DocumentFormat.TextEdit(s.current.offset + (0:(x.fullspan)), string("primitive type ", Expr(x.args[3]), " ", Expr(x.args[2]), " end"))], "This specification for primitive types is deprecated"))
    
    name = CSTParser.get_id(x.args[3])
    nsEx = make_name(s.namespace, str_value(name))
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx]).loc) == s.current.offset)
        loc = s.current.offset + offset + (0:sizeof(str_value(name)))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end

    if x.args[2] isa LITERAL && x.args[2].kind == Tokens.INTEGER && mod(Expr(x.args[2]), 8) != 0
        loc = s.current.offset + x.args[1].fullspan + (0:sizeof(str_value(x.args[2])))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Invalid number of bits in primitive type $(str_value(name))"))
    end
end

function lint(x::EXPR{CSTParser.Primitive}, s::TopLevelScope, L::LintState, server, istop)
    name = CSTParser.get_id(x.args[3])
    nsEx = make_name(s.namespace, str_value(name))
    if haskey(s.symbols, nsEx) && !(length(s.symbols[nsEx]) == 1 && first(first(s.symbols[nsEx]).loc) == s.current.offset)
        loc = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + (0:sizeof(str_value(name)))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Cannot declare constant, it already has a value"))
    end

    if x.args[4] isa LITERAL && x.args[4].kind == Tokens.INTEGER && mod(Expr(x.args[4]), 8) != 0
        loc = s.current.offset + x.args[1].fullspan + x.args[2].fullspan + x.args[3].fullspan + (0:sizeof(str_value(x.args[4])))
        push!(L.diagnostics, LSDiagnostic{PossibleTypo}(loc, [], "Invalid number of bits in primitive type $(str_value(name))"))
    end
end

function lint(x::EXPR{CSTParser.TypeAlias}, s::TopLevelScope, L::LintState, server, istop)
    offset = x.args[1].fullspan
    tws = CSTParser.trailing_ws_length(x)
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
    if x.args[2] isa CSTParser.BinarySyntaxOpCall && x.args[2].arg1 isa EXPR{CSTParser.Curly} && (x.args[2].arg2 isa EXPR{CSTParser.Curly} || x.args[2].arg2 isa WhereOpCall)
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
        s.current.offset += x.args[2].fullspan
    end
    lint(x.args[3], s, L, server, istop)
end

function lint(x::EXPR{CSTParser.Local}, s::TopLevelScope, L::LintState, server, istop)
    if length(x.args) == 2 && !(x.args[2] isa CSTParser.BinarySyntaxOpCall && x.args[2].op.kind == Tokens.EQ) 
        return 
    end
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
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

function _lint_range(x::BinaryOpCall, s::TopLevelScope, L::LintState)
    if ((CSTParser.is_in(x.op) || CSTParser.is_elof(x.op)))
        if x.arg2 isa LITERAL
            push!(L.diagnostics, LSDiagnostic{LoopOverSingle}(s.current.offset + (0:x.fullspan), [], "You are trying to loop over a single instance"))
        end
    else
        push!(L.diagnostics, LSDiagnostic{RangeNonAssignment}(s.current.offset + (0:x.fullspan), [], "You must assign (using =, in or ∈) in a range")) 
    end
end

function _lint_range(x::BinarySyntaxOpCall, s::TopLevelScope, L::LintState)
    if CSTParser.is_eq(x.op)
        if x.arg2 isa LITERAL
            push!(L.diagnostics, LSDiagnostic{LoopOverSingle}(s.current.offset + (0:x.fullspan), [], "You are trying to loop over a single instance"))
        end
    end
end

function _lint_range(x, s::TopLevelScope, L::LintState)
    push!(L.diagnostics, LSDiagnostic{RangeNonAssignment}(s.current.offset + (0:x.fullspan), [], "You must assign (using =, in or ∈) in a range")) 
end

function _lint_range(x::PUNCTUATION, s::TopLevelScope, L::LintState)
end

function lint(x::EXPR{CSTParser.If}, s::TopLevelScope, L::LintState, server, istop) 
    if x.args[1] isa KEYWORD && x.args[1].kind == Tokens.IF
        cond = x.args[2]
        cond_offset = x.args[1].fullspan
        deadcode_elseblock_range = s.current.offset + cond_offset + (0:x.args[2].fullspan + x.args[3].fullspan)
    else
        cond = x.args[1]
        cond_offset = 0
        s.current.offset + cond_offset + (0:x.args[2].fullspan)
    end
    
    if cond isa BinarySyntaxOpCall && CSTParser.is_eq(cond.op)
        push!(L.diagnostics, LSDiagnostic{CondAssignment}(s.current.offset + cond_offset + (0:cond.fullspan), [], "An assignment rather than comparison operator has been used"))
    end
    if cond isa LITERAL && cond.kind == Tokens.TRUE
        if length(x.args) == 6
            push!(L.diagnostics, LSDiagnostic{DeadCode}(s.current.offset + cond_offset + cond.fullspan + x.args[3].fullspan + x.args[4].fullspan + (0:x.args[5].fullspan), [], "This code is never reached"))
        end
    elseif cond isa LITERAL && cond.kind == Tokens.FALSE
        push!(L.diagnostics, LSDiagnostic{DeadCode}(deadcode_elseblock_range, [], "This code is never reached"))
    end
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{CSTParser.While}, s::TopLevelScope, L::LintState, server, istop) 
    # Linting
    if x.args[2] isa BinarySyntaxOpCall && CSTParser.is_eq(x.args[2].op)
        push!(L.diagnostics, LSDiagnostic{CondAssignment}(s.current.offset + x.args[1].fullspan + (0:x.args[2].fullspan), [], "An assignment rather than comparison operator has been used"))
    elseif x.args[2] isa LITERAL && x.args[2].kind == Tokens.FALSE
        push!(L.diagnostics, LSDiagnostic{DeadCode}(s.current.offset + (0:x.fullspan), [], "This code is never reached"))
    end
    invoke(lint, Tuple{EXPR,TopLevelScope,LintState,LanguageServerInstance,Bool}, x, s, L, server, istop)
end

function lint(x::EXPR{T}, s::TopLevelScope, L::LintState, server, istop) where T <: Union{CSTParser.Using,CSTParser.Import,CSTParser.ImportAll}
    #  NEEDS FIX: 
end

function lint(x::EXPR{CSTParser.Export}, s::TopLevelScope, L::LintState, server, istop)
    exported_names = Set{String}()
    for a in x.args
        if a isa IDENTIFIER
            loc = s.current.offset + a.span - 1
            if str_value(a) in exported_names
                push!(L.diagnostics, LSDiagnostic{DuplicateArgument}(loc, [], "Variable $(str_value(a)) is already exported"))
            else
                push!(exported_names, str_value(a))
            end

            lint(a, s, L, server, istop)
        end
        s.current.offset += a.fullspan
    end
end


function get_symbols(x, s::TopLevelScope, L::LintState)
    for v in get_defs(x)
        name = make_name(s.namespace, v.id)
        var_item = VariableLoc(v, s.current.offset + (0:x.fullspan), s.current.uri)
        if haskey(s.symbols, name)
            push!(s.symbols[name], var_item)
        else
            s.symbols[name] = VariableLoc[var_item]
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
