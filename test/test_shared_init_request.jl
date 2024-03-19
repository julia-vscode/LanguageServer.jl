import JSONRPC, LanguageServer

init_request = LanguageServer.InitializeParams(
    9902,
    missing,
    nothing,
    nothing,
    missing,
    LanguageServer.ClientCapabilities(
        LanguageServer.WorkspaceClientCapabilities(
            true,
            LanguageServer.WorkspaceEditClientCapabilities(true, missing, missing),
            LanguageServer.DidChangeConfigurationClientCapabilities(false),
            LanguageServer.DidChangeWatchedFilesClientCapabilities(false,),
            LanguageServer.WorkspaceSymbolClientCapabilities(true, missing),
            LanguageServer.ExecuteCommandClientCapabilities(true),
            missing,
            missing
        ),
        LanguageServer.TextDocumentClientCapabilities(
            LanguageServer.TextDocumentSyncClientCapabilities(true, true, true, true),
            LanguageServer.CompletionClientCapabilities(true, LanguageServer.CompletionItemClientCapabilities(true, missing, missing, missing, missing, missing), missing, missing),
            LanguageServer.HoverClientCapabilities(true, missing),
            LanguageServer.SignatureHelpClientCapabilities(true, missing, missing),
            LanguageServer.DeclarationClientCapabilities(false, missing),
            missing, # DefinitionClientCapabilities(),
            missing, # TypeDefinitionClientCapabilities(),
            missing, # ImplementationClientCapabilities(),
            missing, # ReferenceClientCapabilities(),
            LanguageServer.DocumentHighlightClientCapabilities(true),
            LanguageServer.DocumentSymbolClientCapabilities(true, missing, missing),
            LanguageServer.CodeActionClientCapabilities(true, missing, missing),
            LanguageServer.CodeLensClientCapabilities(true),
            missing, # DocumentLinkClientCapabilities(),
            missing, # DocumentColorClientCapabilities(),
            LanguageServer.DocumentFormattingClientCapabilities(true),
            missing, # DocumentRangeFormattingClientCapabilities(),
            missing, # DocumentOnTypeFormattingClientCapabilities(),
            LanguageServer.RenameClientCapabilities(true, true),
            missing, # PublishDiagnosticsClientCapabilities(),
            missing, # FoldingRangeClientCapabilities(),
            missing, # SelectionRangeClientCapabilities()
        ),
        missing,
        missing
    ),
    "off",
    missing,
    missing
)
