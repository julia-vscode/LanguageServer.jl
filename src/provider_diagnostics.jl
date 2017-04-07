const LintSeverity = Dict('E'=>1,'W'=>2,'I'=>3)

function process_diagnostics(uri::String, server::LanguageServerInstance)
    put!(server.diagnostic_requests, uri)
end
