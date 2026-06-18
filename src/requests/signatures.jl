function textDocument_signatureHelp_request(params::TextDocumentPositionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    result = JuliaWorkspaces.get_signature_help(server.workspace, uri, index)

    sigs = map(result.signatures) do sig
        pars = map(sig.parameters) do p
            ParameterInformation(p.label, p.documentation === nothing ? missing : p.documentation)
        end
        SignatureInformation(sig.label, sig.documentation, pars)
    end

    return SignatureHelp(sigs, result.active_signature, result.active_parameter)
end
