##############################################################################
# From client
const FailureHandlingKind = String
const FailureHandlingKinds = (Abort = "abort",
                              Transactional = "transactional",
                              TextOnlyTransactional = "textOnlyTransactional",
                              Undo = "undo")

const ResourceOperationKind = String
const ResourceOperationKinds = (Create = "create",
                                Rename = "rename",
                                Delete = "delete")

@dict_readable struct WorkspaceEditClientCapabilities <: Outbound
    documentChanges::Union{Bool,Missing}
    resourceOperations::Union{Vector{ResourceOperationKind},Missing}
    failureHandling::Union{FailureHandlingKind,Missing}
end

@dict_readable struct DidChangeConfigurationClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

@dict_readable struct DidChangeWatchedFilesClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

@dict_readable struct WorkspaceClientCapabilities <: Outbound
    applyEdit::Union{Bool,Missing}
    workspaceEdit::Union{WorkspaceEditClientCapabilities,Missing}
    didChangeConfiguration::Union{DidChangeConfigurationClientCapabilities,Missing}
    didChangeWatchedFiles::Union{DidChangeWatchedFilesClientCapabilities,Missing}
    symbol::Union{WorkspaceSymbolClientCapabilities,Missing}
    executeCommand::Union{ExecuteCommandClientCapabilities,Missing}
    workspaceFolders::Union{Bool,Missing}
    configuration::Union{Bool,Missing}
end

@dict_readable struct TextDocumentSyncClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    willSave::Union{Bool,Missing}
    willSaveWaitUntil::Union{Bool,Missing}
    didSave::Union{Bool,Missing}
end


@dict_readable struct TagClientCapabilities
    valueSet::Vector{DiagnosticTag}
end

@dict_readable struct PublishDiagnosticsClientCapabilities <: Outbound
    relatedInformation::Union{Bool,Missing}
    tagSupport::Union{TagClientCapabilities,Missing}
    versionSupport::Union{Bool,Missing}
end

@dict_readable struct TextDocumentClientCapabilities <: Outbound
    synchronization::Union{TextDocumentSyncClientCapabilities,Missing}
    completion::Union{CompletionClientCapabilities,Missing}
    hover::Union{HoverClientCapabilities,Missing}
    signatureHelp::Union{SignatureHelpClientCapabilities,Missing}
    declaration::Union{DeclarationClientCapabilities,Missing}
    definition::Union{DefinitionClientCapabilities,Missing}
    typeDefinition::Union{TypeDefinitionClientCapabilities,Missing}
    implementation::Union{ImplementationClientCapabilities,Missing}
    references::Union{ReferenceClientCapabilities,Missing}
    documentHighlight::Union{DocumentHighlightClientCapabilities,Missing}
    documentSymbol::Union{DocumentSymbolClientCapabilities,Missing}
    codeAction::Union{CodeActionClientCapabilities,Missing}
    codeLens::Union{CodeLensClientCapabilities,Missing}
    documentLink::Union{DocumentLinkClientCapabilities,Missing}
    colorProvider::Union{DocumentColorClientCapabilities,Missing}
    formatting::Union{DocumentFormattingClientCapabilities,Missing}
    rangeFormatting::Union{DocumentRangeFormattingClientCapabilities,Missing}
    onTypeFormatting::Union{DocumentOnTypeFormattingClientCapabilities,Missing}
    rename::Union{RenameClientCapabilities,Missing}
    publishDiagnostics::Union{PublishDiagnosticsClientCapabilities,Missing}
    foldingRange::Union{FoldingRangeClientCapabilities,Missing}
    selectionRange::Union{SelectionRangeClientCapabilities,Missing}
end

@dict_readable struct WindowClientCapabilities <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct ClientCapabilities <: Outbound
    workspace::Union{WorkspaceClientCapabilities,Missing}
    textDocument::Union{TextDocumentClientCapabilities,Missing}
    window::Union{WindowClientCapabilities,Missing}
    experimental::Union{Any,Missing}
end
@dict_readable struct InfoParams <: Outbound
    name::String
    version::Union{String,Missing}
end

struct InitializeParams <: Outbound
    processId::Union{Int,Nothing}
    clientInfo::Union{InfoParams,Missing}
    rootPath::Union{DocumentUri,Nothing,Missing}
    rootUri::Union{DocumentUri,Nothing}
    initializationOptions::Union{Any,Missing}
    capabilities::ClientCapabilities
    trace::Union{String,Missing}
    workspaceFolders::Union{Vector{WorkspaceFolder},Nothing,Missing}
    workDoneToken::Union{ProgressToken,Missing}
end

# Requires handwritten implementaiton to account for 3-part Unions
function InitializeParams(dict::Dict)
    InitializeParams(dict["processId"],
    haskey(dict, "clientInfo") ? InfoParams(dict["clientInfo"]) : missing,
    !haskey(dict, "rootPath") ? missing : dict["rootPath"] === nothing ? nothing : DocumentUri(dict["rootPath"]),
    dict["rootUri"] === nothing ? nothing : DocumentUri(dict["rootUri"]),
    get(dict, "initializationOptions", missing),
    ClientCapabilities(dict["capabilities"]),
    haskey(dict, "trace") ? String(dict["trace"]) : missing ,
    !haskey(dict, "workspaceFolders") ? missing : dict["workspaceFolders"] === nothing ? nothing : WorkspaceFolder.(dict["workspaceFolders"]),
    haskey(dict, "workDoneToken") ? ProgressToken(dict["workDoneToken"]) : missing)
end
##############################################################################




##############################################################################
# Server Response
struct SaveOptions <: Outbound
    includeText::Union{Bool,Missing}
end

struct ColorProviderOptions <: Outbound end

const TextDocumentSyncKind = Int
const TextDocumentSyncKinds = (None = 0,
                               Full = 1,
                               Incremental = 2)

struct TextDocumentSyncOptions <: Outbound
    openClose::Union{Bool,Missing}
    change::Union{TextDocumentSyncKind,Missing}
    willSave::Union{Bool,Missing}
    willSaveWaitUntil::Union{Bool,Missing}
    save::Union{SaveOptions,Missing}
end

struct WorkspaceFoldersOptions <: Outbound
    supported::Union{Bool,Missing}
    changeNotifications::Union{Bool,String,Missing}
end

struct WorkspaceOptions <: Outbound
    workspaceFolders::Union{WorkspaceFoldersOptions,Missing}
end

struct WorkspaceFoldersServerCapabilities <: Outbound
    supported::Union{Bool,Missing}
    changeNotifications::Union{String,Bool,Missing}
end

struct ServerCapabilities <: Outbound
    textDocumentSync::Union{TextDocumentSyncOptions,Int,Missing}
    completionProvider::Union{CompletionOptions,Missing}
    hoverProvider::Union{Bool,HoverOptions,Missing}
    signatureHelpProvider::Union{SignatureHelpOptions,Missing}
    declarationProvider::Union{Bool,DeclarationOptions,DeclarationRegistrationOptions,Missing}
    definitionProvider::Union{Bool,DefinitionOptions,Missing}
    typeDefinitionProvider::Union{Bool,TypeDefinitionOptions,TypeDefinitionRegistrationOptions,Missing}
    implementationProvider::Union{Bool,ImplementationOptions,ImplementationRegistrationOptions,Missing}
    referencesProvider::Union{Bool,ReferenceOptions,Missing}
    documentHighlightProvider::Union{Bool,DocumentHighlightOptions,Missing}
    documentSymbolProvider::Union{Bool,DocumentSymbolOptions,Missing}
    codeActionProvider::Union{Bool,CodeActionOptions,Missing}
    codeLensProvider::Union{CodeLensOptions,Missing}
    documentLinkProvider::Union{DocumentLinkOptions,Missing}
    colorProvider::Union{Bool,DocumentColorOptions,DocumentColorRegistrationOptions,Missing}
    documentFormattingProvider::Union{Bool,DocumentFormattingOptions,Missing}
    documentRangeFormattingProvider::Union{Bool,DocumentRangeFormattingOptions,Missing}
    documentOnTypeFormattingProvider::Union{DocumentOnTypeFormattingOptions,Missing}
    renameProvider::Union{Bool,RenameOptions,Missing}
    foldingRangeProvider::Union{Bool,FoldingRangeOptions,FoldingRangeRegistrationOptions,Missing}
    executeCommandProvider::Union{ExecuteCommandOptions,Missing}
    selectionRangeProvider::Union{Bool,SelectionRangeOptions,SelectionRangeRegistrationOptions,Missing}
    workspaceSymbolProvider::Union{Bool,Missing}
    workspace::Union{WorkspaceOptions,Missing}
    experimental::Union{Any,Missing}
end

struct InitializeResult <: Outbound
    capabilities::ServerCapabilities
    serverInfo::Union{InfoParams,Missing}
end

##############################################################################
@dict_readable struct InitializedParams
end
