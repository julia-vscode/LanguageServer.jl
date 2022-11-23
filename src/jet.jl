import JET, JETLS

function jet_diagnostics!(doc::Document)
    # Run JET.report_file on the "include-root" of this doc
    root_file = get_path(getroot(doc))
    jet_results = try
        JET.report_file(root_file; analyze_from_definitions=true, toplevel_logger=devnull)
    catch e
        @error "Error in JET.report_file($(repr(root_file)))" exception=e
        return nothing
    end
    # Convert to LSP diagnostics, in JETLS format (workspace diagnostica as named tuples).
    jetls_results = JETLS.jet_to_workspace_diagnostics(jet_results)
    idx = findfirst(jetls_results) do r
        # TODO: JETLS URI are all lowercase.
        doc_uri   = lowercase(URIs2.uri2filepath(get_uri(doc)))
        jetls_uri = lowercase(URIs2.uri2filepath(URIs2.URI(r.uri)))
        return doc_uri == jetls_uri
    end
    idx === nothing && return
    jetls_result = jetls_results[idx]
    # Convert from JETLS format to LanguageServer.Diagnostic
    for item in jetls_result.items
        range = Range(
            # TODO: JETLS uses first column as the start of the message, but would look
            #       nicer to take the first non-whitespace character.
            Position(item.range.start.line, item.range.start.character),
            # TODO: JETLS return typemax(Int) for the end column but that give an error in
            #       neovim ("end column not an integer") so use typemax(Int32) instead.
            Position(item.range.var"end".line, #=item.range.var"end".character=# typemax(Int32) % Int),
        )
        d = Diagnostic(
            range,
            missing, # severity
            missing, # code
            missing, # codeDescription
            missing, # source
            item.message,
            missing, # tags
            missing, # relatedInformation
        )
        push!(doc.diagnostics, d)
    end
    return
end
