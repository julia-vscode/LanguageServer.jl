# TODO:
# - refactor, simplify branching, unify duplications
# - (maybe) export latex completions into a separate package

struct CompletionState
    offset::Int
    completions::Dict{String,CompletionItem}
    range::Range
    x::Union{Nothing, EXPR}
    doc::Document
    server::LanguageServerInstance
    using_stmts::Dict{String,Any}
end

function add_completion_item(state::CompletionState, completion::CompletionItem)
    if haskey(state.completions, completion.label) && ismissing(state.completions[completion.label].data)
        # For the above statement: we've (1) already got a completion which (2) doesn't require adding an explicit import statement.
        return
    end
    state.completions[completion.label] = completion
end

StaticLint.getenv(state::CompletionState) = getenv(state.doc, state.server)

using REPL

"""
    is_completion_match(s::AbstractString, prefix::AbstractString, cutoff=3)

Returns true if `s` starts with `prefix` or has a sufficiently high fuzzy score.
"""
function is_completion_match(s::AbstractString, prefix::AbstractString, cutoff=3)
    starter = if !any(isuppercase, prefix)
        startswith(lowercase(s), prefix)
    else
        startswith(s, prefix)
    end
    starter || REPL.fuzzyscore(prefix, s) >= cutoff
end

function textDocument_completion_request(params::CompletionParams, server::LanguageServerInstance, conn)
    state = let
        doc = getdocument(server, params.textDocument.uri)
        offset = get_offset3(get_text_document(doc), params.position)
        rng = Range(doc, offset:offset)
        x = get_expr(getcst(doc), offset)
        using_stmts = server.completion_mode == :import ? get_preexisting_using_stmts(x, doc) : Dict()
        CompletionState(offset, Dict{String,CompletionItem}(), rng, x, doc, server, using_stmts)
    end

    ppt, pt, t, is_at_end  = get_partial_completion(state)

    if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokenize.Tokens.BACKSLASH
        latex_completions(string("\\", CSTParser.Tokenize.untokenize(t)), state)
    elseif ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokenize.Tokens.BACKSLASH && pt isa CSTParser.Tokens.Token && (pt.kind === CSTParser.Tokens.CIRCUMFLEX_ACCENT || pt.kind === CSTParser.Tokens.COLON)
        latex_completions(string("\\", CSTParser.Tokenize.untokenize(pt), CSTParser.Tokenize.untokenize(t)), state)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokenize.Tokens.COMMENT
        partial = is_latex_comp(t.val, state.offset - t.startbyte)
        !isempty(partial) && latex_completions(partial, state)
    elseif t isa CSTParser.Tokens.Token && (t.kind in (CSTParser.Tokenize.Tokens.STRING,
                                                       CSTParser.Tokenize.Tokens.TRIPLE_STRING,
                                                       CSTParser.Tokenize.Tokens.CMD,
                                                       CSTParser.Tokenize.Tokens.TRIPLE_CMD))
        string_completion(t, state)
    elseif state.x isa EXPR && is_in_import_statement(state.x)
        import_completions(ppt, pt, t, is_at_end, state.x, state)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.DOT && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.IDENTIFIER
        # getfield completion, no partial
        px = get_expr(getcst(state.doc), state.offset - (1 + t.endbyte - t.startbyte))
        _get_dot_completion(px, "", state)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER && pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.DOT && ppt isa CSTParser.Tokens.Token && ppt.kind == CSTParser.Tokens.IDENTIFIER
        # getfield completion, partial
        px = get_expr(getcst(state.doc), state.offset - (1 + t.endbyte - t.startbyte) - (1 + pt.endbyte - pt.startbyte)) # get offset 2 tokens back
        _get_dot_completion(px, t.val, state)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IDENTIFIER
        # token completion
        if is_at_end && state.x !== nothing
            if pt isa CSTParser.Tokens.Token && pt.kind == CSTParser.Tokens.AT_SIGN
                spartial = string("@", t.val)
            else
                spartial = t.val
            end
            kw_completion(spartial, state)
            rng = Range(state.doc, state.offset:state.offset)
            collect_completions(state.x, spartial, state, false)
        end
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.AT_SIGN
        # only `@` given
        state.x !== nothing && collect_completions(state.x, "@", state, false)
    elseif t isa CSTParser.Tokens.Token && Tokens.iskeyword(t.kind) && is_at_end
        kw_completion(CSTParser.Tokenize.untokenize(t), state)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.IN && is_at_end && state.x !== nothing
        collect_completions(state.x, "in", state, false)
    elseif t isa CSTParser.Tokens.Token && t.kind == CSTParser.Tokens.ISA && is_at_end && state.x !== nothing
        collect_completions(state.x, "isa", state, false)
    end

    return CompletionList(true, unique(values(state.completions)))
end


function get_partial_completion(state::CompletionState)
    ppt, pt, t = get_toks(state.doc, state.offset)
    is_at_end = state.offset == t.endbyte + 1
    return ppt, pt, t, is_at_end
end

function latex_completions(partial::String, state::CompletionState)
    for (k, v) in Iterators.flatten((REPL.REPLCompletions.latex_symbols, REPL.REPLCompletions.emoji_symbols))
        if is_completion_match(string(k), partial)
            # t1 = TextEdit(Range(state.doc, (state.offset - sizeof(partial)):state.offset), v)
            add_completion_item(state, CompletionItem(k, CompletionItemKinds.Unit, missing, v, v, missing, missing, missing, missing, missing, missing, texteditfor(state, partial, v, CompletionItemKinds.Unit), missing, missing, missing, missing))
        end
    end
end

function kw_completion(partial::String, state::CompletionState)
    length(partial) == 0 && return
    for (kw, comp) in snippet_completions
        if startswith(kw, partial)
            kind = occursin("\$0", comp) ? CompletionItemKinds.Snippet : CompletionItemKinds.Keyword
            add_completion_item(state, CompletionItem(kw, kind, missing, missing, kw, missing, missing, missing, missing, missing, InsertTextFormats.Snippet, texteditfor(state, partial, comp, kind), missing, missing, missing, missing))
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
    "false" => "false",
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
    "true" => "true",
    "try" => "try\n\t\$0\ncatch\nend",
    "using" => "using ",
    "while" => "while \$1\n\t\$0\nend"
    )


function texteditfor(state::CompletionState, partial, newtext, kind)
    if state.server.complete_func_parens && (kind == CompletionItemKinds.Method || kind == CompletionItemKinds.Function)
        newtext = newtext * "()"
    end
    TextEdit(Range(Position(state.range.start.line, max(state.range.start.character - length(partial), 0)), state.range.stop), newtext)
end

function string_macro_altname(s)
    if startswith(s, "@") && endswith(s, "_str")
        return chop(s; head=1, tail=4) * '"'
    else
        return nothing
    end
end

function collect_completions(m::SymbolServer.ModuleStore, spartial, state::CompletionState, inclexported=false, dotcomps=false)
    possible_names = String[]
    for val in m.vals
        n, v = String(val[1]), val[2]
        (startswith(n, ".") || startswith(n, "#")) && continue
        # Keep track of the canonical name and some possible alternatives
        # (e.g. string macros can complete as '@foo_str' and also 'foo"')
        canonical_name = n
        resize!(possible_names, 0)
        if is_completion_match(n, spartial)
            push!(possible_names, n) # Direct match
        end
        if (nn = string_macro_altname(n); nn !== nothing) && is_completion_match(nn, spartial)
            # Match for string macro without initial @ and trailing _str
            push!(possible_names, nn)
        end
        length(possible_names) == 0 && continue # No matches, continue
        if v isa SymbolServer.VarRef
            v = SymbolServer._lookup(v, getsymbols(getenv(state)), true)
            v === nothing && return
        end
        if StaticLint.isexportedby(canonical_name, m) || inclexported
            foreach(possible_names) do n
                add_completion_item(state, CompletionItem(n, _completion_kind(v), get_typed_definition(v), MarkupContent(sanitize_docstring(v.doc)), texteditfor(state, spartial, n, _completion_kind(v))))
            end
        elseif dotcomps
            foreach(possible_names) do n
                push!(state.completions, CompletionItem(n, _completion_kind(v), get_typed_definition(v), MarkupContent(sanitize_docstring(v.doc)), texteditfor(state, spartial, string(m.name, ".", n), _completion_kind(v))))
            end
        elseif length(spartial) > 3 && !variable_already_imported(m, canonical_name, state)
            if state.server.completion_mode === :import
                # These are non-exported names and require the insertion of a :using statement.
                # We need to insert this statement at the start of the current top-level scope (e.g. Main or a module) and tag it onto existing :using statements if possible.
                foreach(possible_names) do n
                    ci = CompletionItem(n, _completion_kind(v), missing, "This is an unexported symbol and will be explicitly imported.",
                        MarkupContent(sanitize_docstring(v.doc)), missing, missing, missing, missing, missing, InsertTextFormats.PlainText,
                        texteditfor(state, spartial, n, _completion_kind(v)), textedit_to_insert_using_stmt(m, canonical_name, state), missing, missing, "import")
                    add_completion_item(state, ci)
                end
            elseif state.server.completion_mode === :qualify
                foreach(possible_names) do n
                    add_completion_item(state, CompletionItem(string(m.name, ".", n), _completion_kind(v), missing,
                        missing, MarkupContent(sanitize_docstring(v.doc)), missing,
                        missing, string(n), missing, missing, InsertTextFormats.PlainText, texteditfor(state, spartial, string(m.name, ".", n), _completion_kind(v)),
                        missing, missing, missing, missing))
                end
            end
        end
    end
end

function variable_already_imported(m, n, state)
    haskey(state.using_stmts, String(m.name.name)) && import_has_x(state.using_stmts[String(m.name.name)][1], n)
end

function import_has_x(expr::EXPR, x::String)
    if length(expr.args) == 1 && length(expr.args[1]) > 1
        for i = 2:length(expr.args[1].args)
            arg = expr.args[1].args[i]
            if CSTParser.isoperator(arg.head) && length(arg.args) == 1 && CSTParser.isidentifier(arg.args[1]) && CSTParser.valof(arg.args[1]) == x
                return true
            end
        end
    end
    return false
end

function collect_completions(x::EXPR, spartial, state::CompletionState, inclexported=false, dotcomps=false)
    if scopeof(x) !== nothing
        collect_completions(scopeof(x), spartial, state, inclexported, dotcomps)
        if scopeof(x).modules isa Dict
            for m in scopeof(x).modules
                collect_completions(m[2], spartial, state, inclexported, dotcomps)
            end
        end
    end
    if parentof(x) !== nothing && !CSTParser.defines_module(x)
        return collect_completions(parentof(x), spartial, state, inclexported, dotcomps)
    end
end

function collect_completions(x::StaticLint.Scope, spartial, state::CompletionState, inclexported=false, dotcomps=false)
    if x.names !== nothing
        possible_names = String[]
        for n in x.names
            resize!(possible_names, 0)
            if is_completion_match(n[1], spartial)
                push!(possible_names, n[1])
            end
            if (nn = string_macro_altname(n[1]); nn !== nothing) && is_completion_match(nn, spartial)
                push!(possible_names, nn)
            end
            if length(possible_names) > 0
                documentation = ""
                if n[2] isa StaticLint.Binding
                    documentation = get_tooltip(n[2], documentation, state.server)
                    sanitize_docstring(documentation)
                end
                foreach(possible_names) do nn
                    add_completion_item(state, CompletionItem(nn, _completion_kind(n[2]), get_typed_definition(n[2]), MarkupContent(documentation), texteditfor(state, spartial, nn, _completion_kind(n[2]))))
                end
            end
        end
    end
end


function is_rebinding_of_module(x)
    x isa EXPR && refof(x).type === StaticLint.CoreTypes.Module && # binding is a Module
    refof(x).val isa EXPR && CSTParser.isassignment(refof(x).val) && # binding expr is an assignment
    StaticLint.hasref(refof(x).val.args[2]) && refof(refof(x).val.args[2]).type === StaticLint.CoreTypes.Module &&
    refof(refof(x).val.args[2]).val isa EXPR && CSTParser.defines_module(refof(refof(x).val.args[2]).val)# double check the rhs points to a module
end

function _get_dot_completion(px, spartial, state::CompletionState) end
function _get_dot_completion(px::EXPR, spartial, state::CompletionState)
    if px !== nothing
        if refof(px) isa StaticLint.Binding
            if refof(px).val isa StaticLint.SymbolServer.ModuleStore
                collect_completions(refof(px).val, spartial, state, true)
            elseif refof(px).val isa EXPR && CSTParser.defines_module(refof(px).val) && scopeof(refof(px).val) isa StaticLint.Scope
                collect_completions(scopeof(refof(px).val), spartial, state, true)
            elseif is_rebinding_of_module(px)
                collect_completions(scopeof(refof(refof(px).val.args[2]).val), spartial, state, true)
            elseif refof(px).type isa SymbolServer.DataTypeStore
                for a in refof(px).type.fieldnames
                    a = String(a)
                    if is_completion_match(a, spartial)
                        add_completion_item(state, CompletionItem(a, CompletionItemKinds.Method, get_typed_definition(a), MarkupContent(a), texteditfor(state, spartial, a, CompletionItemKinds.Method)))
                    end
                end
            elseif refof(px).type isa StaticLint.Binding && refof(px).type.val isa SymbolServer.DataTypeStore
                for a in refof(px).type.val.fieldnames
                    a = String(a)
                    if is_completion_match(a, spartial)
                        add_completion_item(state, CompletionItem(a, CompletionItemKinds.Method, get_typed_definition(a), MarkupContent(a), texteditfor(state, spartial, a, CompletionItemKinds.Method)))
                    end
                end
            elseif refof(px).type isa StaticLint.Binding && refof(px).type.val isa EXPR && CSTParser.defines_struct(refof(px).type.val) && scopeof(refof(px).type.val) isa StaticLint.Scope
                collect_completions(scopeof(refof(px).type.val), spartial, state, true)
            end
        elseif refof(px) isa StaticLint.SymbolServer.ModuleStore
            collect_completions(refof(px), spartial, state, true)
        end
    end
end

function _completion_kind(b)
    if b isa StaticLint.Binding
        if b.type == StaticLint.CoreTypes.String
            return CompletionItemKinds.Text
        elseif b.type == StaticLint.CoreTypes.Function
            return CompletionItemKinds.Method
        elseif b.type == StaticLint.CoreTypes.Module
            return CompletionItemKinds.Module
        elseif b.type == Int || b.type == StaticLint.CoreTypes.Float64
            return CompletionItemKinds.Value
        elseif b.type == StaticLint.CoreTypes.DataType
            return CompletionItemKinds.Struct
        else
            return CompletionItemKinds.Variable
        end
    elseif b isa SymbolServer.ModuleStore || b isa SymbolServer.VarRef
        return CompletionItemKinds.Module
    elseif b isa SymbolServer.MethodStore
        return CompletionItemKinds.Method
    elseif b isa SymbolServer.FunctionStore
        return CompletionItemKinds.Function
    elseif b isa SymbolServer.DataTypeStore
        return CompletionItemKinds.Struct
    else
        return CompletionItemKinds.Variable
    end
end



function get_import_root(x::EXPR)
    if CSTParser.isoperator(headof(x.args[1])) && valof(headof(x.args[1])) == ":"
        return last(x.args[1].args[1].args)
    end
end

function string_completion(t, state::CompletionState)
    path_completion(t, state)
    # Need to adjust things for quotation marks
    if t.kind in (CSTParser.Tokenize.Tokens.STRING,CSTParser.Tokenize.Tokens.CMD)
        t.startbyte + 1 < state.offset <= t.endbyte || return
        relative_offset = state.offset - t.startbyte - 1
        content = t.val[2:prevind(t.val, lastindex(t.val))]
    else
        t.startbyte + 3 < state.offset <= t.endbyte - 2 || return
        relative_offset = state.offset - t.startbyte - 3
        content = t.val[4:prevind(t.val, lastindex(t.val), 3)]
    end
    relative_offset = clamp(relative_offset, firstindex(content), lastindex(content))
    partial = is_latex_comp(content, relative_offset)
    !isempty(partial) && latex_completions(partial, state)
end

function is_latex_comp(s, i)
    firstindex(s) <= i <= lastindex(s) || return ""
    i0 = i = thisind(s, i)
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
    # from: UInt8.(sort!(unique(prod([k[2:end] for (k,_) in Iterators.flatten((REPL.REPLCompletions.latex_symbols, REPL.REPLCompletions.emoji_symbols))]))))
    u === 0x21 ||
    u === 0x28 ||
    u === 0x29 ||
    u === 0x2b ||
    u === 0x2d ||
    u === 0x2f ||
    0x30 <= u <= 0x39 ||
    u === 0x3a ||
    u === 0x3d ||
    0x41 <= u <= 0x5a ||
    u === 0x5e ||
    u === 0x5f ||
    0x61 <= u <= 0x7a
end

function path_completion(t, state::CompletionState)
    if t.kind == CSTParser.Tokenize.Tokens.STRING
        path = t.val[2:prevind(t.val, lastindex(t.val))]
        if startswith(path, "~")
            path = replace(path, '~' => homedir())
            dir, partial = _splitdir(path)
        else
            dir, partial = _splitdir(path)
            if !startswith(dir, "/")
                doc_path = getpath(state.doc)
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
                        rng1 = Range(state.doc, state.offset - sizeof(partial):state.offset)
                        add_completion_item(state, CompletionItem(f, CompletionItemKinds.File, f, TextEdit(rng1, f)))
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

is_in_import_statement(x::EXPR) = is_in_fexpr(x, x -> headof(x) in (:using, :import))

function import_completions(ppt, pt, t, is_at_end, x, state::CompletionState)
    import_statement = StaticLint.get_parent_fexpr(x, x -> headof(x) === :using || headof(x) === :import)

    import_root = get_import_root(import_statement)

    if (t.kind == CSTParser.Tokens.WHITESPACE && pt.kind ∈ (CSTParser.Tokens.USING, CSTParser.Tokens.IMPORT, CSTParser.Tokens.IMPORTALL, CSTParser.Tokens.COMMA, CSTParser.Tokens.COLON)) ||
        (t.kind in (CSTParser.Tokens.COMMA, CSTParser.Tokens.COLON))
        # no partial, no dot
        if import_root !== nothing && refof(import_root) isa SymbolServer.ModuleStore
            for (n, m) in refof(import_root).vals
                n = String(n)
                if is_completion_match(n, t.val) && !startswith(n, "#")
                    add_completion_item(state, CompletionItem(n, _completion_kind(m), get_typed_definition(m), MarkupContent(m isa SymbolServer.SymStore ? sanitize_docstring(m.doc) : n), texteditfor(state, t.val, n, _completion_kind(m))))
                end
            end
        else
            for (n, m) in StaticLint.getsymbols(getenv(state))
                n = String(n)
                (startswith(n, ".") || startswith(n, "#")) && continue
                add_completion_item(state, CompletionItem(n, CompletionItemKinds.Module, get_typed_definition(m), MarkupContent(sanitize_docstring(m.doc)), TextEdit(state.range, n)))
            end
        end
    elseif t.kind == CSTParser.Tokens.DOT && pt.kind == CSTParser.Tokens.IDENTIFIER
        # no partial, dot
        if haskey(getsymbols(getenv(state)), Symbol(pt.val))
            collect_completions(getsymbols(getenv(state))[Symbol(pt.val)], "", state)
        end
    elseif t.kind == CSTParser.Tokens.IDENTIFIER && is_at_end
        # partial
        if pt.kind == CSTParser.Tokens.DOT && ppt.kind == CSTParser.Tokens.IDENTIFIER
            if haskey(StaticLint.getsymbols(getenv(state)), Symbol(ppt.val))
                rootmod = StaticLint.getsymbols(getenv(state))[Symbol(ppt.val)]
                for (n, m) in rootmod.vals
                    n = String(n)
                    if is_completion_match(n, t.val) && !startswith(n, "#")
                        add_completion_item(state, CompletionItem(n, _completion_kind(m), get_typed_definition(m), MarkupContent(m isa SymbolServer.SymStore ? sanitize_docstring(m.doc) : n), texteditfor(state, t.val, n, _completion_kind(m))))
                    end
                end
            end
        else
            if import_root !== nothing && refof(import_root) isa SymbolServer.ModuleStore
                for (n, m) in refof(import_root).vals
                    n = String(n)
                    if is_completion_match(n, t.val) && !startswith(n, "#")
                        add_completion_item(state, CompletionItem(n, _completion_kind(m), get_typed_definition(m), MarkupContent(m isa SymbolServer.SymStore ? sanitize_docstring(m.doc) : n), texteditfor(state, t.val, n, _completion_kind(m))))
                    end
                end
            else
                for (n, m) in StaticLint.getsymbols(getenv(state))
                    n = String(n)
                    if is_completion_match(n, t.val)
                        add_completion_item(state, CompletionItem(n, CompletionItemKinds.Module, get_typed_definition(m), MarkupContent(m isa SymbolServer.SymStore ? m.doc : n), texteditfor(state, t.val, n, CompletionItemKinds.Module,)))
                    end
                end
            end
        end
    end
end



function get_preexisting_using_stmts(x::EXPR, doc::Document)
    using_stmts = Dict{String,Any}()
    tls = StaticLint.retrieve_toplevel_scope(x)
    file_level_arg = get_file_level_parent(x)

    if scopeof(getcst(doc)) == tls
        # check for :using stmts in current file
        for a in getcst(doc).args
            if headof(a) === :using
                add_using_stmt(a, using_stmts)
            end
            a == file_level_arg && break
        end
    end

    if tls !== nothing
        args = get_tls_arglist(tls)
        for a in args
            if headof(a) === :using
                add_using_stmt(a, using_stmts)
            end

        end
    end
    return using_stmts
end

function add_using_stmt(x::EXPR, using_stmts)
    if length(x.args) > 0 && CSTParser.is_colon(x.args[1].head)
        if CSTParser.is_dot(x.args[1].args[1].head) && length(x.args[1].args[1].args) == 1
            using_stmts[valof(x.args[1].args[1].args[1])] = (x, get_file_loc(x))
        end
    end
end

function get_file_level_parent(x::EXPR)
    if x.parent isa EXPR && x.parent.head === :file
        x
    else
        if x.parent === nothing
            return nothing
        end
        get_file_level_parent(x.parent)
    end
end

function textedit_to_insert_using_stmt(m::SymbolServer.ModuleStore, n::String, state::CompletionState)
    tls = StaticLint.retrieve_toplevel_scope(state.x)
    if haskey(state.using_stmts, String(m.name.name))
        (using_stmt, (using_doc, using_offset)) = state.using_stmts[String(m.name.name)]

        l, c = get_position_from_offset(using_doc, using_offset + using_stmt.span)
        return [TextEdit(Range(l, c, l, c), ", $n")]
    elseif tls !== nothing
        if tls.expr.head === :file
            # Insert at the head of the file
            tlsdoc, offset1 = get_file_loc(tls.expr)
            return [TextEdit(Range(0, 0, 0, 0), "using $(m.name): $(n)\n")]
        elseif tls.expr.head === :module
            # Insert at start of module
            tlsdoc, offset1 = get_file_loc(tls.expr)
            offset2 = tls.expr.trivia[1].fullspan + tls.expr.args[2].fullspan
            l, c = get_position_from_offset(tlsdoc, offset1 + offset2)

            return [TextEdit(Range(l, c, l, c), "using $(m.name): $(n)\n")]
        else
            error()
        end
    else
        # Fallback, add it to the start of the current file.
        return [TextEdit(Range(0, 0, 0, 0), "using $(m.name): $(n)\n")]
    end
end

function get_tls_arglist(tls::StaticLint.Scope)
    if tls.expr.head === :file
        tls.expr.args
    elseif tls.expr.head === :module
        tls.expr.args[3].args
    else
        error()
    end
end
