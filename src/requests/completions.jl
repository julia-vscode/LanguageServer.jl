# TODO:
# - refactor, simplify branching, unify duplications
# - fuzzy completions
# - (maybe) export latex completions into a separate package

function textDocument_completion_request(params::CompletionParams, server::LanguageServerInstance, conn)
    CIs = CompletionItem[]
    doc = getdocument(server, URI2(params.textDocument.uri))
    offset = get_offset(doc, params.position)
    rng = Range(doc, offset:offset)
    ppt, pt, t, is_at_end  = get_partial_completion(doc, offset)
    x = get_expr(getcst(doc), offset)

    if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokenize.Tokens.BACKSLASH
        # latex completion
        latex_completions(doc, offset, string("\\", CSTParser.Tokenize.untokenize(t)), CIs)
    elseif ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokenize.Tokens.BACKSLASH && pt isa CSTParser.Tokens.Token && pt.kind === CSTParser.Tokens.CIRCUMFLEX_ACCENT
        latex_completions(doc, offset, string("\\", CSTParser.Tokenize.untokenize(pt), CSTParser.Tokenize.untokenize(t)), CIs)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokenize.Tokens.COMMENT
        partial = is_latex_comp(t.val, offset - t.startbyte)
        !isempty(partial) && latex_completions(doc, offset, partial, CIs)
    elseif t isa CSTParser.Tokens.Token && (t.kind == CSTParser.Tokenize.Tokens.STRING || t.kind == CSTParser.Tokenize.Tokens.TRIPLE_STRING)
        string_completion(doc, offset, rng, t, CIs)
    elseif x isa EXPR && parentof(x) !== nothing && (typof(parentof(x)) === CSTParser.Using || typof(parentof(x)) === CSTParser.Import)
        import_completions(doc, offset, rng, ppt, pt, t, is_at_end, x, CIs, server)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.DOT && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.IDENTIFIER
        # getfield completion, no partial
        px = get_expr(getcst(doc), offset - (1 + t.endbyte - t.startbyte))
        _get_dot_completion(px, "", rng, CIs, server)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.DOT && ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokens.IDENTIFIER
        # getfield completion, partial
        px = get_expr(getcst(doc), offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte)) # get offset 2 tokens back
        _get_dot_completion(px, t.val, rng, CIs, server)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER
        # token completion
        if is_at_end && x !== nothing
            if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.AT_SIGN
                spartial = string("@", t.val)
            else
                spartial = t.val
            end
            kw_completion(doc, spartial, CIs, offset)
            rng = Range(doc, offset:offset)
            collect_completions(x, spartial, rng, CIs, server, false)
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.AT_SIGN
        # only `@` given
        x !== nothing && collect_completions(x, "@", rng, CIs, server, false)
    elseif t isa CSTParser.Tokens.Token && Tokens.iskeyword(t.kind) && is_at_end
        kw_completion(doc, CSTParser.Tokenize.untokenize(t), CIs, offset)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IN && is_at_end
        collect_completions(x, "in", rng, CIs, server, false)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.ISA && is_at_end
        collect_completions(x, "isa", rng, CIs, server, false)
    end

    return CompletionList(true, unique(CIs))
end

function get_partial_completion(doc, offset)
    ppt, pt, t = toks = get_toks(doc, offset)
    is_at_end = offset == t.endbyte + 1
    return ppt, pt, t, is_at_end
end

function latex_completions(doc, offset, partial, CIs)
    for (k, v) in REPL.REPLCompletions.latex_symbols
        if startswith(string(k), partial)
            t1 = TextEdit(Range(doc, (offset - sizeof(partial)):offset), v)
            push!(CIs, CompletionItem(k, 11, missing, v, v, missing, missing, missing, missing, missing, missing, t1, missing, missing, missing, missing))
        end
    end
end

function kw_completion(doc, spartial, CIs, offset)
    length(spartial) == 0 && return
    fc = first(spartial)
    for (kw, comp) in snippet_completions
        if startswith(kw, spartial)
            push!(CIs, CompletionItem(kw, 14, missing, missing, kw, missing, missing, missing, missing, missing, InsertTextFormats.Snippet, TextEdit(Range(doc, offset:offset), comp[length(spartial) + 1:end]), missing, missing, missing, missing))
        end
    end
end

const snippet_completions = Dict{String,String}(
    "abstract" => "abstract type \$0 end",
    "baremodule" => "baremodule \$1\n\t\$0\nend",
    "begin" => "begin\n\t\$0\nend",
    "break" => "break",
    "catch" => "catch",
    "const" => "const ",
    "continue" => "continue",
    "do" => "do \$1\n\t\$0\nend",
    "else" => "else",
    "elseif" => "elseif ",
    "end" => "end",
    "export" => "export ",
    "finally" => "finally",
    "for" => "for \$1 in \$2\n\t\$0\nend",
    "function" => "function \$1(\$2)\n\t\$0\nend",
    "global" => "global ",
    "if" => "if \$1\n\t\$0\nend",
    "import" => "import",
    "let" => "let \$1\n\t\$0\nend",
    "local" => "local ",
    "macro" => "macro \$1(\$2)\n\t\$0\nend",
    "module" => "module \$1\n\t\$0\nend",
    "mutable" => "mutable struct \$0\nend",
    "outer" => "outer ",
    "primitive" => "primitive type \$1 \$0 end",
    "quote" => "quote\n\t\$0\nend",
    "return" => "return",
    "struct" => "struct \$0 end",
    "try" => "try\n\t\$0\ncatch\nend",
    "using" => "using ",
    "while" => "while \$1\n\t\$0\nend"
    )

function collect_completions(m::SymbolServer.ModuleStore, spartial, rng, CIs, server, inclexported=false, dotcomps=false)
    for val in m.vals
        n, v = String(val[1]), val[2]
        (startswith(n, ".") || startswith(n, "#")) && continue
        !startswith(n, spartial) && continue
        if v isa SymbolServer.VarRef
            v = SymbolServer._lookup(v, getsymbolserver(server), true)
            v === nothing && return
        end
        if StaticLint.isexportedby(n, m) || inclexported
            push!(CIs, CompletionItem(n, _completion_kind(v, server), MarkupContent(sanitize_docstring(v.doc)), TextEdit(rng, n[nextind(n, sizeof(spartial)):end])))
        elseif dotcomps
            rng1 = Range(Position(rng.start.line, rng.start.character - sizeof(spartial)), rng.stop)
            push!(CIs, CompletionItem(n, _completion_kind(v, server), MarkupContent(sanitize_docstring(v.doc)), TextEdit(rng1, string(m.name, ".", n))))
        end
    end
end

function collect_completions(x::EXPR, spartial, rng, CIs, server, inclexported=false, dotcomps=false)
    if scopeof(x) !== nothing
        collect_completions(scopeof(x), spartial, rng, CIs, server, inclexported, dotcomps)
        if scopeof(x).modules isa Dict
            for m in scopeof(x).modules
                collect_completions(m[2], spartial, rng, CIs, server, inclexported, dotcomps)
            end
        end
    end
    if parentof(x) !== nothing && typof(x) !== CSTParser.ModuleH && typof(x) !== CSTParser.BareModule
        return collect_completions(parentof(x), spartial, rng, CIs, server, inclexported, dotcomps)
    else
        return
    end
end

function collect_completions(x::StaticLint.Scope, spartial, rng, CIs, server, inclexported=false, dotcomps=false)
    if x.names !== nothing
        for n in x.names
            if startswith(n[1], spartial)
                documentation = ""
                if n[2] isa StaticLint.Binding
                    documentation = get_hover(n[2], documentation, server)
                    sanitize_docstring(documentation)
                end
                push!(CIs, CompletionItem(n[1], _completion_kind(n[2], server), MarkupContent(documentation), TextEdit(rng, n[1][nextind(n[1], sizeof(spartial)):end])))
            end
        end
    end
end


function is_rebinding_of_module(x)
    x isa EXPR && refof(x).type === StaticLint.CoreTypes.Module && # binding is a Module
    refof(x).val isa EXPR && typof(refof(x).val) === CSTParser.BinaryOpCall && kindof(refof(x).val.args[2]) === CSTParser.Tokens.EQ && # binding expr is an assignment
    StaticLint.hasref(refof(x).val.args[3]) && refof(refof(x).val.args[3]).type === StaticLint.CoreTypes.Module &&
    refof(refof(x).val.args[3]).val isa EXPR && typof(refof(refof(x).val.args[3]).val) === CSTParser.ModuleH# double check the rhs points to a module
end

function _get_dot_completion(px, spartial, rng, CIs, server) end
function _get_dot_completion(px::EXPR, spartial, rng, CIs, server)
    if px !== nothing
        if refof(px) isa StaticLint.Binding
            if refof(px).val isa StaticLint.SymbolServer.ModuleStore
                collect_completions(refof(px).val, spartial, rng, CIs, server, true)
            elseif refof(px).val isa EXPR && typof(refof(px).val) === CSTParser.ModuleH && scopeof(refof(px).val) isa StaticLint.Scope
                collect_completions(scopeof(refof(px).val), spartial, rng, CIs, server, true)
            elseif is_rebinding_of_module(px)
                collect_completions(scopeof(refof(refof(px).val.args[3]).val), spartial, rng, CIs, server, true)
            elseif refof(px).type isa SymbolServer.DataTypeStore
                for a in refof(px).type.fieldnames
                    a = String(a)
                    if startswith(a, spartial)
                        push!(CIs, CompletionItem(a, 2, MarkupContent(a), TextEdit(rng, a[nextind(a, sizeof(spartial)):end])))
                    end
                end
            elseif refof(px).type isa StaticLint.Binding && refof(px).type.val isa SymbolServer.DataTypeStore
                for a in refof(px).type.val.fieldnames
                    a = String(a)
                    if startswith(a, spartial)
                        push!(CIs, CompletionItem(a, 2, MarkupContent(a), TextEdit(rng, a[nextind(a, sizeof(spartial)):end])))
                    end
                end
            elseif refof(px).type isa StaticLint.Binding && refof(px).type.val isa EXPR && CSTParser.defines_struct(refof(px).type.val) && scopeof(refof(px).type.val) isa StaticLint.Scope
                collect_completions(scopeof(refof(px).type.val), spartial, rng, CIs, server, true)
            end
        elseif refof(px) isa StaticLint.SymbolServer.ModuleStore
            collect_completions(refof(px), spartial, rng, CIs, server, true)
        end
    end
end

function _completion_kind(b, server)
    if b isa StaticLint.Binding
        if b.type == StaticLint.CoreTypes.String
            return 1
        elseif b.type == StaticLint.CoreTypes.Function
            return 2
        elseif b.type == StaticLint.CoreTypes.Module
            return 9
        elseif b.type == Int || b.type == StaticLint.CoreTypes.Float64
            return 12
        elseif b.type == StaticLint.CoreTypes.DataType
            return 22
        else
            return 13
        end
    elseif b isa SymbolServer.ModuleStore || b isa SymbolServer.VarRef
        return 9
    elseif b isa SymbolServer.MethodStore
        return 2
    elseif b isa SymbolServer.FunctionStore
        return 3
    elseif b isa SymbolServer.DataTypeStore
        return 22
    else
        return 6
    end
end

function get_import_root(x::EXPR)
    for i = 1:length(x.args)
        if typof(x.args[i]) === CSTParser.OPERATOR && kindof(x.args[i]) === CSTParser.Tokens.COLON && i > 2
            return x.args[i - 1]
        end
    end
    return nothing
end

function string_completion(doc, offset, rng, t, CIs)
    path_completion(doc, offset, rng, t, CIs)
    # Need to adjust things for quotation marks
    if t.kind == CSTParser.Tokenize.Tokens.STRING
        t.startbyte < offset <= t.endbyte || return
        relative_offset = offset - t.startbyte - 1
        content = t.val[2:prevind(t.val, lastindex(t.val))]
    else
        t.startbyte < offset <= t.endbyte - 2 || return
        relative_offset = offset - t.startbyte - 3
        content = t.val[4:prevind(t.val, lastindex(t.val), 3)]
    end
    partial = is_latex_comp(content, relative_offset)
    !isempty(partial) && latex_completions(doc, offset, partial, CIs)
end

function is_latex_comp(s, i)
    i0 = i
    while firstindex(s) <= i
        s[i] == '\\' && return s[i:i0]
        !is_latex_comp_char(s[i]) && return ""
        i = prevind(s, i)
    end
    return ""
end

is_latex_comp_char(c::Char) = UInt32(c) <= typemax(UInt8) ? is_latex_comp_char(UInt8(c)) : false
function is_latex_comp_char(u)
    # Checks whether a Char (represented as a UInt8) is in the set of those those used to trigger
    # latex completions.
    # from: UInt8.(sort!(unique(prod([k[2:end] for (k,_) in REPL.REPLCompletions.latex_symbols]))))
    u === 0x28 ||
    u === 0x29 ||
    u === 0x2b ||
    u === 0x2d ||
    u === 0x2f ||
    0x30 <= u <= 0x39 ||
    u === 0x3d ||
    0x41 <= u <= 0x5a ||
    u === 0x5e ||
    u === 0x5f ||
    0x61 <= u <= 0x7a
end

function path_completion(doc, offset, rng, t, CIs)
    if t.kind == CSTParser.Tokenize.Tokens.STRING
        path = t.val[2:prevind(t.val, lastindex(t.val))]
        if startswith(path, "~")
            path = replace(path, '~' => homedir())
            dir, partial = _splitdir(path)
        else
            dir, partial = _splitdir(path)
            if !startswith(dir, "/")
                doc_path = getpath(doc)
                isempty(doc_path) && return
                dir = joinpath(_dirname(doc_path), dir)
            end
        end
        try
            fs = readdir(dir)
            for f in fs
                if startswith(f, partial)
                    try
                        if isdir(joinpath(dir, f))
                            f = string(f, "/")
                        end
                        push!(CIs, CompletionItem(f, 17, f, TextEdit(rng, f[nextind(f, lastindex(partial)):end])))
                    catch err
                        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
                    end
                end
            end
        catch err
            isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        end
    end
end

function import_completions(doc, offset, rng, ppt, pt, t, is_at_end, x, CIs, server)
    import_statement = parentof(x)
    import_root = get_import_root(import_statement)
    if (t.kind == CSTParser.Tokens.WHITESPACE && pt.kind ∈ (CSTParser.Tokens.USING, CSTParser.Tokens.IMPORT, CSTParser.Tokens.IMPORTALL, CSTParser.Tokens.COMMA, CSTParser.Tokens.COLON)) ||
        (t.kind in (CSTParser.Tokens.COMMA, CSTParser.Tokens.COLON))
        # no partial, no dot
        if import_root !== nothing && refof(import_root) isa SymbolServer.ModuleStore
            for (n, m) in refof(import_root).vals
                n = String(n)
                if startswith(n, t.val) && !startswith(n, "#")
                    push!(CIs, CompletionItem(n, _completion_kind(m, server), MarkupContent(m isa SymbolServer.SymStore ? sanitize_docstring(m.doc) : n), TextEdit(rng, n[length(t.val) + 1:end])))
                end
            end
        else
            for (n, m) in StaticLint.getsymbolserver(server)
                n = String(n)
                (startswith(n, ".") || startswith(n, "#")) && continue
                push!(CIs, CompletionItem(n, 9, MarkupContent(sanitize_docstring(m.doc)), TextEdit(rng, n)))
            end
        end
    elseif t.kind == CSTParser.Tokens.DOT && pt.kind == CSTParser.Tokens.IDENTIFIER
        # no partial, dot
        if haskey(getsymbolserver(server), Symbol(pt.val))
            collect_completions(getsymbolserver(server)[Symbol(pt.val)], "", rng, CIs, server)
        end
    elseif t.kind == CSTParser.Tokens.IDENTIFIER && is_at_end
        # partial
        if pt.kind == CSTParser.Tokens.DOT && ppt.kind == CSTParser.Tokens.IDENTIFIER
            if haskey(StaticLint.getsymbolserver(server), Symbol(ppt.val))
                rootmod = StaticLint.getsymbolserver(server)[Symbol(ppt.val)]
                for (n, m) in rootmod.vals
                    n = String(n)
                    if startswith(n, t.val) && !startswith(n, "#")
                        push!(CIs, CompletionItem(n, _completion_kind(m, server), MarkupContent(m isa SymbolServer.SymStore ? sanitize_docstring(m.doc) : n), TextEdit(rng, n[length(t.val) + 1:end])))
                    end
                end
            end
        else
            if import_root !== nothing && refof(import_root) isa SymbolServer.ModuleStore
                for (n, m) in refof(import_root).vals
                    n = String(n)
                    if startswith(n, t.val) && !startswith(n, "#")
                        push!(CIs, CompletionItem(n, _completion_kind(m, server), MarkupContent(m isa SymbolServer.SymStore ? sanitize_docstring(m.doc) : n), TextEdit(rng, n[length(t.val) + 1:end])))
                    end
                end
            else
                for (n, m) in StaticLint.getsymbolserver(server)
                    n = String(n)
                    if startswith(n, t.val)
                        push!(CIs, CompletionItem(n, 9, MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), TextEdit(rng, n[nextind(n, sizeof(t.val)):end])))
                    end
                end
            end
        end
    end
end
