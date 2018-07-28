

@json_read mutable struct WorkspaceEditCapabilities
    documentChanges::Bool
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
    valueSet::Vector{Int}
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
    synchronization::SynchronizationCapabilities
    completion::CompletionCapabilities
    hover::HoverCapabilities
    signatureHelp::SignatureCapabilities
    references::Capabilities
    documentHighlight::Capabilities
    documentSymbol::Union{Nothing,DocumentSymbolCapabilities}
    formatting::Union{Nothing,Capabilities}
    rangeFormatting::Union{Nothing,Capabilities}
    onTypeFormatting::Union{Nothing,Capabilities}
    definition::Union{Nothing,Capabilities}
    typeDefinition::Union{Nothing,Capabilities}
    implementation::Union{Nothing,Capabilities}
    codeAction::CodeActionCapabilities
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
    processId::Int
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
    documentLinkProvider::DocumentLinkOptions
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



# WorkspaceEditCapabilities(d::Dict) = haskeynotnull(d, "applyEdit") ? WorkspaceEditCapabilities(d["applyEdit"]) : WorkspaceEditCapabilities(false)
# WorkspaceEditCapabilities() = WorkspaceEditCapabilities(false)

# Capabilities(d::Dict) = haskeynotnull(d, "dynamicRegistration") ? Capabilities(d["dynamicRegistration"]) : Capabilities()
# Capabilities() = Capabilities(false)


# function WorkspaceClientCapabilities(d::Dict)
#     applyEdit = haskeynotnull(d, "applyEdit") ? d["applyEdit"] : nothing
#     workspaceEdit = haskeynotnull(d, "workspaceEdit") ? WorkspaceEditCapabilities(d["workspaceEdit"]) : WorkspaceEditCapabilities()
#     didChangeConfiguration = haskeynotnull(d, "didChangeConfiguration") ? Capabilities(d["didChangeConfiguration"]) : Capabilities()
#     didChangeWatchedFiles = haskeynotnull(d, "didChangeWatchedFiles") ? Capabilities(d["didChangeWatchedFiles"]) : Capabilities()
#     symbol = haskeynotnull(d, "symbol") ? Capabilities(d["symbol"]) : Capabilities()
#     executeCommand = haskeynotnull(d, "executeCommand") ? Capabilities(d["executeCommand"]) : Capabilities()
#     workspaceFolders = haskeynotnull(d, "workspaceFolders") ? d["workspaceFolders"] : nothing
#     return WorkspaceClientCapabilities(applyEdit, workspaceEdit, didChangeConfiguration, didChangeWatchedFiles, symbol, executeCommand,
#     workspaceFolders)
# end
# WorkspaceClientCapabilities() = WorkspaceClientCapabilities(Dict())

# function SynchroizationCapabilities(d::Dict)
#     dynamicRegistration = haskeynotnull(d, "dynamicRegistration") ? d["dynamicRegistration"] : false
#     willSave = haskeynotnull(d, "willSave") ? d["willSave"] : false
#     willSaveWaitUntil = haskeynotnull(d, "willSaveWaitUntil") ? d["willSaveWaitUntil"] : false
#     didSave = haskeynotnull(d, "didSave") ? d["didSave"] : false
#     return SynchroizationCapabilities(dynamicRegistration, willSave, willSaveWaitUntil, didSave)
# end
# SynchroizationCapabilities() = SynchroizationCapabilities(false, false, false, false)
# CompletionItemCapabilities(d::Dict) = haskeynotnull(d, "snippetSupport") ? CompletionItemCapabilities(d["snippetSupport"]) : CompletionItemCapabilities(false)
# CompletionItemCapabilities() = CompletionItemCapabilities(false)

# function CompletionCapabilities(d::Dict)
#     dynamicRegistration = haskeynotnull(d, "dynamicRegistration")  ? d["dynamicRegistration"] : false
#     completionItem      = haskeynotnull(d, "completionItem")       ? CompletionItemCapabilities(d["completionItem"]) : CompletionItemCapabilities()
#     return CompletionCapabilities(dynamicRegistration, completionItem)
# end
# CompletionCapabilities() = CompletionCapabilities(false, CompletionItemCapabilities())

# function TextDocumentClientCapabilities(d::Dict)
#     synchroization      = haskeynotnull(d, "synchroization")   ? SynchroizationCapabilities(d["synchroization"])   : SynchroizationCapabilities()
#     completion          = haskeynotnull(d, "completion")       ? CompletionCapabilities(d["completion"])           : CompletionCapabilities()
#     hover               = haskeynotnull(d, "hover")            ? Capabilities(d["hover"])                          : Capabilities()
#     signatureHelp       = haskeynotnull(d, "signatureHelp")    ? Capabilities(d["signatureHelp"])                  : Capabilities()
#     references          = haskeynotnull(d, "references")       ? Capabilities(d["references"])                     : Capabilities()
#     documentHighlight   = haskeynotnull(d, "documentHighlight") ? Capabilities(d["documentHighlight"])             : Capabilities()
#     documentSymbol      = haskeynotnull(d, "documentSymbol")   ? Capabilities(d["documentSymbol"])                 : Capabilities()
#     formatting          = haskeynotnull(d, "formatting")       ? Capabilities(d["formatting"])                     : Capabilities()
#     rangeFormatting     = haskeynotnull(d, "rangeFormatting")  ? Capabilities(d["rangeFormatting"])                : Capabilities()
#     onTypeFormatting    = haskeynotnull(d, "onTypeFormatting") ? Capabilities(d["onTypeFormatting"])               : Capabilities()
#     definition          = haskeynotnull(d, "definition")       ? Capabilities(d["definition"])                     : Capabilities()
#     codeAction          = haskeynotnull(d, "codeAction")       ? Capabilities(d["codeAction"])                     : Capabilities()
#     CodeLens            = haskeynotnull(d, "CodeLens")         ? Capabilities(d["CodeLens"])                       : Capabilities()
#     documentLink        = haskeynotnull(d, "documentLink")     ? Capabilities(d["documentLink"])                   : Capabilities()
#     rename              = haskeynotnull(d, "rename")           ? Capabilities(d["rename"])                         : Capabilities()
#     return TextDocumentClientCapabilities(synchroization, completion, hover, signatureHelp, references, documentHighlight, documentSymbol, formatting, rangeFormatting, onTypeFormatting, definition, codeAction, CodeLens, documentLink, rename)
# end
# TextDocumentClientCapabilities() = TextDocumentClientCapabilities(SynchroizationCapabilities(), 
#                                                                   CompletionCapabilities(), 
#                                                                   Capabilities(), 
#                                                                   Capabilities(), 
#                                                                   Capabilities(), 
#                                                                   Capabilities(), 
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities(),
#                                                                   Capabilities())


# function ClientCapabilities(d::Dict)
#     workspace = haskeynotnull(d, "workspace") ? WorkspaceClientCapabilities(d["workspace"]) : WorkspaceClientCapabilities()
#     textDocument = haskeynotnull(d, "textDocument") ? TextDocumentClientCapabilities(d["textDocument"]) : TextDocumentClientCapabilities()
#     return ClientCapabilities(workspace, textDocument, nothing)
# end


# function InitializeParams(d::Dict)
#     return InitializeParams(d["processId"],
#                             haskeynotnull(d, "rootPath") ? d["rootPath"] : nothing,
#                             haskeynotnull(d, "rootUri") ? d["rootUri"] : nothing,
#                             haskeynotnull(d, "initializationOptions") ? d["initializationOptions"] : nothing,
#                             ClientCapabilities(d["capabilities"]),
#                             haskeynotnull(d, "trace") ? d["trace"] : nothing,
#                             haskeynotnull(d, "workspaceFolders") ? WorkspaceFolder.(d["workspaceFolders"]) : WorkspaceFolder[]
#                             )
# end

# CodeLensOptions() = CodeLensOptions(false)

# DocumentOnTypeFormattingOptions() = DocumentOnTypeFormattingOptions("", [])


