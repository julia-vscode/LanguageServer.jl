function parse_all(doc, server)
    # Try blocks should be removed
    try
        ps = CSTParser.ParseState(doc._content)
        doc.code.ast, ps = CSTParser.parse(ps, true)
    catch er
        info("PARSING FAILED for $(doc._uri)")
        info(er)
    end
    
    # includes
    update_includes(doc, server)

    # diagnostics
    doc.diagnostics = ps.diagnostics

    # Parsing failed
    if ps.errored
        parse_errored(doc, ps)
    end

    publish_diagnostics(doc, server)
end

function parse_incremental(doc::Document, dirty::UnitRange, server)
    isempty(doc.code.ast.args) || sizeof(doc._content) < 800 && return parse_all(doc, server)

    # parsing
    start_loc = stop_loc = loc = start_block = 0
    for (i, x) in enumerate(doc.code.ast)
        if loc < first(dirty) <= loc + x.span || x isa CSTParser.ERROR
            start_loc = loc
            start_block = i
        end
        if loc < last(dirty) <= loc + x.span
            stop_loc = loc + x.span
        end
        loc += x.span
    end

    (start_loc == 0 || start_block == 1) && return parse_all(doc, server)

    ps = CSTParser.ParseState(doc._content)
    # Skip to start position
    if start_block > 5
        start_loc1 = sum(doc.code.ast.args[i].span for i = 1:start_block - 3)
        skip(ps.l.io, start_loc1)
        # CSTParser.Tokenize.Lexers.emit(ps.l, CSTParser.Tokenize.Tokens.ERROR)
    end

    while ps.nt.startbyte < start_loc
        next(ps)
    end
    new_expressions, _ = CSTParser.parse(ps, true)

    # Parsing failed
    if ps.errored
        return parse_all(doc, server)
    end
    # delete all ast below start point
    deleteat!(doc.code.ast.args, start_block:length(doc.code.ast.args))
    # append new parsing
    append!(doc.code.ast.args, new_expressions.args)
    doc.code.ast.span = sizeof(doc._content)

    # get includes
    update_includes(doc, server)

    # clear diagnostics for re-parsed regions
    delete_id = Int[]
    for (i, d) in enumerate(doc.diagnostics)
        if last(d.loc) > sizeof(doc._content) || first(d.loc) > start_loc
            push!(delete_id, i)
        end
    end
    deleteat!(doc.diagnostics, delete_id)

    # Add new diagnostics
    for h in unique(ps.diagnostics)
        push!(doc.diagnostics, h)
    end

    publish_diagnostics(doc, server)
end

function convert_diagnostic{T}(h::CSTParser.Diagnostics.Diagnostic{T}, doc::Document)
    rng = Range(Position(get_position_at(doc, first(h.loc) + 1)..., one_based = true), Position(get_position_at(doc, last(h.loc) + 1)..., one_based = true))
    code =  T isa CSTParser.Diagnostics.ErrorCodes ? 1 :
            T isa CSTParser.Diagnostics.LintCodes ? 2 :
            T isa CSTParser.Diagnostics.FormatCodes ? 4 : 3
    Diagnostic(rng, code, string(T), string(typeof(h).name), string(T))
end

function publish_diagnostics(doc::Document, server)
    ls_diags = convert_diagnostic.(doc.diagnostics, doc)
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, ls_diags)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), publishDiagnosticsParams)
    send(response, server)
end

function update_includes(doc::Document, server::LanguageServerInstance)
    doc.code.includes = map(_get_includes(doc.code.ast)) do incl
        (isabspath(incl[1]) ? filepath2uri(incl[1]) : joinpath(dirname(doc._uri), incl[1]), incl[2])
        
    end
end

function parse_errored(doc::Document, ps::CSTParser.ParseState)
    ast = doc.code.ast
    if last(ast.args) isa EXPR{CSTParser.ERROR}
        if length(ast.args) > 1
            loc = sum(ast.args[i].span for i = 1:length(ast.args) - 1):sizeof(doc._content)
        else
            loc = 0:sizeof(doc._content)
        end
        push!(doc.diagnostics, CSTParser.Diagnostics.Diagnostic{CSTParser.Diagnostics.ParseFailure}(0:sizeof(doc._content), []))
    end
end
