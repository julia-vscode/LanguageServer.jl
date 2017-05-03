
function parse_diag(doc, server)
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
    doc.diagnostics = map(unique(ps.diagnostics)) do h
        rng = Range(Position(get_position_at(doc, first(h.loc) + 1)..., one_based = true), Position(get_position_at(doc, last(h.loc) + 1)..., one_based = true))
        Diagnostic(rng, 2, string(typeof(h).parameters[1]), string(typeof(h).name), string(typeof(h).parameters[1]))
    end

    # Parsing failed
    parse_errored(doc, ps)

    publish_diagnostics(doc, server)
end

function parse_errored(doc::Document, ps::CSTParser.ParseState)
    if ps.errored
        ast = doc.code.ast
        if last(ast) isa CSTParser.ERROR
            if length(ast) > 1
                loc = sum(ast[i].span for i = 1:length(ast) - 1):sizeof(doc._content)
            else
                loc = 0:sizeof(doc._content)
            end
            rng = Range(Position(get_position_at(doc, first(loc) + 1)..., one_based = true), Position(get_position_at(doc, last(loc) + 1)..., one_based = true))
            push!(doc.diagnostics, Diagnostic(rng, 1, "Parse failure", "Unknown", "Parse failure"))
        end
    end
end

function publish_diagnostics(doc::Document, server)
    publishDiagnosticsParams = PublishDiagnosticsParams(doc._uri, doc.diagnostics)
    response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")}, PublishDiagnosticsParams}(Nullable{Union{String, Int64}}(), publishDiagnosticsParams)
    send(response, server)
end

function parse_incremental(doc::Document, dirty::UnitRange, server)
    isempty(doc.code.ast.args) || sizeof(doc._content) < 800 && return parse_diag(doc, server)

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

    (start_loc == 0 || start_block == 1) && return parse_diag(doc, server)

    ps = CSTParser.ParseState(doc._content)
    # Skip to start position
    if start_block > 5
        start_loc1 = sum(doc.code.ast[i].span for i = 1:start_block - 3)
        skip(ps.l.io, start_loc1)
        # CSTParser.Tokenize.Lexers.emit(ps.l, CSTParser.Tokenize.Tokens.ERROR)
    end

    while ps.nt.startbyte < start_loc
        next(ps)
    end
    new_expressions, _ = CSTParser.parse(ps, true)

    # delete all ast below start point
    deleteat!(doc.code.ast.args, start_block:length(doc.code.ast))
    # append new parsing
    append!(doc.code.ast.args, new_expressions.args)
    doc.code.ast.span = sizeof(doc._content)

    # get includes
    update_includes(doc, server)

    # clear diagnostics for re-parsed regions
    delete_id = []
    for (i, d) in enumerate(doc.diagnostics)
        if get_offset(doc, d.range.start.line + 1, d.range.start.character + 1) > start_loc
            push!(delete_id, i)
        end
    end
    deleteat!(doc.diagnostics, delete_id)

    # Add new diagnostics
    for h in unique(ps.diagnostics)
        rng = Range(Position(get_position_at(doc, first(h.loc) + 1)..., one_based = true), Position(get_position_at(doc, last(h.loc) + 1)..., one_based = true))
        push!(doc.diagnostics, Diagnostic(rng, 2, string(typeof(h).parameters[1]), string(typeof(h).name), string(typeof(h).parameters[1])))
    end

    # Parsing failed
    parse_errored(doc, ps)

    publish_diagnostics(doc, server)
end

function update_includes(doc::Document, server::LanguageServerInstance)
    doc.code.includes = map(CSTParser._get_includes(doc.code.ast)) do incl
        (startswith(incl[1], "/") ? filepath2uri(incl[1]) : joinpath(dirname(doc._uri), incl[1]), incl[2])
    end
end