

@json_read mutable struct WorkspaceEditCapabilities
    documentChanges::Union{Nothing,Bool}
end

@json_read mutable struct Capabilities
    dynamicRegistration::Union{Nothing,Bool}
end

@json_read mutable struct SymbolKindCapabilities
    valueSet::Union{Nothing,Vector{Int}}
end

@json_read mutable struct SymbolCapabilities
    dynamicRegistration::Union{Nothing,Bool}
    symbolKind::Union{Nothing,SymbolKindCapabilities}
end

@json_read mutable struct SynchronizationCapabilities
    dynamicRegistration::Union{Nothing,Bool}
    willSave::Union{Nothing,Bool}
    willSaveWaitUntil::Union{Nothing,Bool}
    didSave::Union{Nothing,Bool}
end

@json_read mutable struct CompletionItemCapabilities
    snippetSupport::Union{Nothing,Bool}
    commitCharactersSupport::Union{Nothing,Bool}
    documentationFormat::Union{Nothing,Vector{String}}
    deprecatedSupport::Union{Nothing,Bool}
end

@json_read mutable struct CompletionItemKindCapabilities
    valueSet::Union{Nothing,Vector{Int}}    
end

@json_read mutable struct CompletionCapabilities
    dynamicRegistration::Union{Nothing,Bool}
    completionItem::CompletionItemCapabilities
    completionItemKind::Union{Nothing,CompletionItemKindCapabilities}
    contextSupport::Union{Nothing,Bool}
end

@json_read mutable struct HoverCapabilities
    dynamicRegistration::Union{Nothing,Bool}    
    contentFormat::Union{Nothing,Vector{String}}
end

@json_read mutable struct SignatureInformationCapabilities
    documentationFormat::Union{Nothing,Vector{String}}
end

@json_read mutable struct SignatureCapabilities
    dynamicRegistration::Union{Nothing,Bool}
    signatureInformation::Union{Nothing,SignatureInformationCapabilities}
end

@json_read mutable struct DocumentSymbolCapabilities
    dynamicRegistration::Union{Nothing,Bool}
    symbolKind::Union{Nothing,SymbolKindCapabilities}
end

@json_read mutable struct CodeActionKindCapabilities
    valueSet::Vector{String}
end

@json_read mutable struct CodeActionLiteralCapabilities
    codeActionKind::CodeActionKindCapabilities
end

@json_read mutable struct CodeActionCapabilities
    dynamicRegistration::Union{Nothing,Bool}
    codeActionLiteralSupport::Union{Nothing,CodeActionLiteralCapabilities}
end

@json_read mutable struct PublishDiagnosticsCapabilities
    relatedInformation::Union{Nothing,Bool}
end

@json_read mutable struct WorkspaceClientCapabilities
    applyEdit::Union{Nothing,Bool}
    workspaceEdit::Union{Nothing,WorkspaceEditCapabilities}
    didChangeConfiguration::Union{Nothing,Capabilities}
    didChangeWatchedFiles::Union{Nothing,Capabilities}
    symbol::Union{Nothing,SymbolCapabilities}
    executeCommand::Union{Nothing,Capabilities}
    workspaceFolders::Union{Nothing,Bool}
    configuration::Union{Nothing,Bool}
end

@json_read mutable struct TextDocumentClientCapabilities
    synchronization::Union{Nothing,SynchronizationCapabilities}
    completion::Union{Nothing,CompletionCapabilities}
    hover::Union{Nothing,HoverCapabilities}
    signatureHelp::Union{Nothing,SignatureCapabilities}
    references::Union{Nothing,Capabilities}
    documentHighlight::Union{Nothing,Capabilities}
    documentSymbol::Union{Nothing,DocumentSymbolCapabilities}
    formatting::Union{Nothing,Capabilities}
    rangeFormatting::Union{Nothing,Capabilities}
    onTypeFormatting::Union{Nothing,Capabilities}
    definition::Union{Nothing,Capabilities}
    typeDefinition::Union{Nothing,Capabilities}
    implementation::Union{Nothing,Capabilities}
    codeAction::Union{Nothing,CodeActionCapabilities}
    CodeLens::Union{Nothing,Capabilities}
    documentLink::Union{Nothing,Capabilities}
    colorProvider::Union{Nothing,Capabilities}
    rename::Union{Nothing,Capabilities}
    publishDiagnostics::Union{Nothing,PublishDiagnosticsCapabilities}
end

@json_read mutable struct ClientCapabilities
    workspace::Union{Nothing,WorkspaceClientCapabilities}
    textDocument::Union{Nothing,TextDocumentClientCapabilities}
    experimental::Union{Nothing,Any}
end

@json_read mutable struct InitializeParams
    processId::Union{Nothing,Int}
    rootPath::Union{Nothing,DocumentUri}
    rootUri::Union{Nothing,DocumentUri}
    initializationOptions::Union{Nothing,Any}
    capabilities::ClientCapabilities
    trace::Union{Nothing,String}
    workspaceFolders::Union{Nothing,Vector{WorkspaceFolder}}
end


# Server Response
mutable struct CompletionOptions 
    resolveProvider::Bool
    triggerCharacters::Vector{String}
end

mutable struct SignatureHelpOptions
    triggerCharacters::Vector{String}
end

mutable struct CodeLensOptions
    resolveProvider::Bool
end

mutable struct DocumentOnTypeFormattingOptions
    firstTriggerCharacter::String
    moreTriggerCharacters::Vector{String}
end

mutable struct DocumentLinkOptions
    resolveProvider::Bool
end

mutable struct ExecuteCommandOptions
    commands::Vector{String}
end

mutable struct SaveOptions
    includeText::Bool
end

mutable struct TextDocumentSyncOptions
    openClose::Bool
    change::Int
    willSave::Bool
    willSaveWaitUntil::Bool
    save::SaveOptions
end

mutable struct StaticRegistrationOptions
    id::String
end

mutable struct WorkspaceFoldersOptions
    supported::Bool
    changeNotifications::Union{Bool,String}
end

mutable struct WorkspaceOptions
    workspaceFolders::WorkspaceFoldersOptions
end

mutable struct ServerCapabilities
    textDocumentSync::Union{TextDocumentSyncOptions,Int}
    hoverProvider::Bool
    completionProvider::CompletionOptions
    signatureHelpProvider::SignatureHelpOptions
    definitionProvider::Bool
    typeDefinitionProvider::Bool
    implementationProvider::Bool
    referencesProvider::Bool
    documentHighlightProvider::Bool
    documentSymbolProvider::Bool
    workspaceSymbolProvider::Bool
    codeActionProvider::Bool
    # codeLensProvider::CodeLensOptions
    documentFormattingProvider::Bool
    documentRangeFormattingProvider::Bool
    # documentOnTypeFormattingProvider::DocumentOnTypeFormattingOptions
    renameProvider::Bool
    # documentLinkProvider::DocumentLinkOptions
    colorProvider::Bool
    executeCommandProvider::ExecuteCommandOptions
    workspace::WorkspaceOptions
    experimental::Any
end

mutable struct InitializeResult
    capabilities::ServerCapabilities
end



mutable struct Registration
    id::String
    method::String
    registerOptions::Any
end

mutable struct RegistrationParams
    registrations::Vector{Registration}
end

mutable struct Unregistration
    id::String
    method::String
end

mutable struct UnregistrationParams
    unregistrations::Vector{Unregistration}
end

mutable struct DidChangeConfiguration
    settings::Any
end

mutable struct ConfigurationItem
    scopeUri::Union{Nothing,String}    
    section::Union{Nothing,String}
end

mutable struct ConfigurationParams
    items::Vector{ConfigurationItem}
end
