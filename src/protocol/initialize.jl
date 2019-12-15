##############################################################################
# From client
@dict_readable struct Capabilities
    dynamicRegistration::Union{Bool,Missing}
end

const ResourceOperationKind = String
const ResourceOperationKinds = ("create", "rename", "delete")
const FailureHandlingKind = String
const FailureHandlingKinds = ("abort", "transactional", "undo", "textOnlyTransactional")

@dict_readable struct WorkspaceEditCapabilities
    documentChanges::Union{Bool,Missing}
    resourceOperations::Union{Vector{ResourceOperationKind},Missing}
    failureHandling::Union{FailureHandlingKind,Missing}
end

@dict_readable struct SymbolKindCapabilities
    valueSet::Union{Vector{Int},Missing}
end

@dict_readable mutable struct SymbolCapabilities
    dynamicRegistration::Union{Bool,Missing}
    symbolKind::Union{SymbolKindCapabilities,Missing}
end

@dict_readable struct WorkspaceClientCapabilities
    applyEdit::Union{Bool,Missing}
    workspaceEdit::Union{WorkspaceEditCapabilities,Missing}
    didChangeConfiguration::Union{Capabilities,Missing}
    didChangeWatchedFiles::Union{Capabilities,Missing}
    symbol::Union{SymbolCapabilities,Missing}
    executeCommand::Union{Capabilities,Missing}
    workspaceFolders::Union{Bool,Missing}
    configuration::Union{Bool,Missing}
end

@dict_readable struct SynchronizationCapabilities
    dynamicRegistration::Union{Bool,Missing}
    willSave::Union{Bool,Missing}
    willSaveWaitUntil::Union{Bool,Missing}
    didSave::Union{Bool,Missing}
end

@dict_readable struct CompletionItemCapabilities
    snippetSupport::Union{Bool,Missing}
    commitCharactersSupport::Union{Bool,Missing}
    documentationFormat::Union{Vector{String},Missing}
    deprecatedSupport::Union{Bool,Missing}
    preselectSupport::Union{Bool,Missing}
end

@dict_readable struct CompletionItemKindCapabilities
    valueSet::Union{Vector{Int},Missing}
end

@dict_readable struct CompletionCapabilities
    dynamicRegistration::Union{Bool,Missing}
    completionItem::Union{CompletionItemCapabilities,Missing}
    completionItemKind::Union{CompletionItemKindCapabilities,Missing}
    contextSupport::Union{Bool,Missing}
end

@dict_readable struct HoverCapabilities
    dynamicRegistration::Union{Bool,Missing}
    contentFormat::Union{Vector{String},Missing}
end

@dict_readable struct ParameterInformationCapabilities
    labelOffsetSupport::Union{Bool,Missing}
end

@dict_readable struct SignatureInformationCapabilities
    documentationFormat::Union{Vector{String},Missing}
    parameterInformation::Union{ParameterInformationCapabilities,Missing}
end

@dict_readable struct SignatureCapabilities
    dynamicRegistration::Union{Bool,Missing}
    signatureInformation::Union{SignatureInformationCapabilities,Missing}
end

@dict_readable struct DocumentSymbolCapabilities
    dynamicRegistration::Union{Bool,Missing}
    symbolKind::Union{SymbolKindCapabilities,Missing}
    hierarchicalDocumentSymbolSupport::Union{Bool,Missing}
end

@dict_readable struct DeclarationCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

@dict_readable struct DefinitionCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

@dict_readable struct TypeDefinitionCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

@dict_readable struct ImplementationCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

@dict_readable struct CodeActionKindCapabilities
    valueSet::Vector{String}
end

@dict_readable struct CodeActionLiteralCapabilities
    codeActionKind::CodeActionKindCapabilities
end

@dict_readable struct CodeActionCapabilities
    dynamicRegistration::Union{Bool,Missing}
    codeActionLiteralSupport::Union{CodeActionLiteralCapabilities,Missing}
end

@dict_readable struct RenameCapabilities
    dynamicRegistration::Union{Bool,Missing}
    prepareSupport::Union{Bool,Missing}
end

@dict_readable struct PublishDiagnosticsCapabilities
    relatedInformation::Union{Bool,Missing}
end

@dict_readable struct FoldingRangeCapabilities
    dynamicRegistration::Union{Bool,Missing}
    rangeLimit::Union{Int,Missing}
    lineFoldingOnly::Union{Bool,Missing}
end

@dict_readable struct TextDocumentClientCapabilities
    synchronization::Union{SynchronizationCapabilities,Missing}
    completion::Union{CompletionCapabilities,Missing}
    hover::Union{HoverCapabilities,Missing}
    signatureHelp::Union{SignatureCapabilities,Missing}
    references::Union{Capabilities,Missing}
    documentHighlight::Union{Capabilities,Missing}
    documentSymbol::Union{DocumentSymbolCapabilities,Missing}
    formatting::Union{Capabilities,Missing}
    rangeFormatting::Union{Capabilities,Missing}
    onTypeFormatting::Union{Capabilities,Missing}
    declaration::Union{DeclarationCapabilities,Missing}
    definition::Union{DefinitionCapabilities,Missing}
    typeDefinition::Union{TypeDefinitionCapabilities,Missing}
    implementation::Union{ImplementationCapabilities,Missing}
    codeAction::Union{CodeActionCapabilities,Missing}
    codeLens::Union{Capabilities,Missing}
    documentLink::Union{Capabilities,Missing}
    colorProvider::Union{Capabilities,Missing}
    rename::Union{RenameCapabilities,Missing}
    publishDiagnostics::Union{PublishDiagnosticsCapabilities,Missing}
    foldingRange::Union{FoldingRangeCapabilities,Missing}
end

@dict_readable struct ClientCapabilities
    workspace::Union{WorkspaceClientCapabilities,Missing}
    textDocument::Union{TextDocumentClientCapabilities,Missing}
    experimental::Union{Any,Missing}
end

struct InitializeParams
    processId::Union{Int,Nothing}
    rootPath::Union{DocumentUri,Nothing,Missing}
    rootUri::Union{DocumentUri,Nothing}
    initializationOptions::Union{Any,Missing}
    capabilities::ClientCapabilities
    trace::Union{String,Missing}
    workspaceFolders::Union{Vector{WorkspaceFolder},Nothing,Missing}
end

# Requires handwritten implementaiton to account for 3-part Unions
function InitializeParams(dict::Dict)
    InitializeParams(Int(dict["processId"]), 
    !haskey(dict, "rootPath") ? missing : dict["rootPath"] === nothing ? nothing : DocumentUri(dict["rootPath"]),
    dict["rootUri"] === nothing ? nothing : DocumentUri(dict["rootUri"]), 
    if haskey(dict, "initializationOptions") dict["initializationOptions"] else missing end, 
    ClientCapabilities(dict["capabilities"]), 
    if haskey(dict, "trace") String(dict["trace"]) else missing end,
    !haskey(dict, "workspaceFolders") ? missing : dict["workspaceFolders"] === nothing ? nothing : WorkspaceFolder.(dict["workspaceFolders"]))
end
##############################################################################




##############################################################################
# Server Response
struct CompletionOptions <: Outbound
    resolveProvider::Union{Bool,Missing}
    triggerCharacters::Union{Vector{String},Missing}
end

struct SignatureHelpOptions <: Outbound
    triggerCharacters::Union{Vector{String},Missing}
end

const CodeActionKind = String
const CodeActionKinds = ("", "quickfix", "refactor", "refactor.extract", "refactor.inline", "source", "source.organiseImports")

struct CodeActionOptions <: Outbound
    codeActionKinds::Union{Vector{CodeActionKind},Missing}
end

struct CodeLensOptions <: Outbound
    resolveProvider::Union{Bool,Missing}
end

struct DocumentOnTypeFormattingOptions <: Outbound
    firstTriggerCharacter::String
    moreTriggerCharacters::Union{Vector{String},Missing}
end

struct RenameOptions <: Outbound
    prepareProvider::Union{Bool,Missing}
end

struct DocumentLinkOptions <: Outbound
    resolveProvider::Union{Bool,Missing}
end

struct ExecuteCommandOptions <: Outbound
    commands::Vector{String}
end

struct SaveOptions <: Outbound
    includeText::Union{Bool,Missing}
end

struct ColorProviderOptions <: Outbound end

struct FoldingRangeProviderOptions <: Outbound end

const TextDocumentSyncKind = Int
const TextDocumentSyncKinds = Dict("None" => 0, "Full" => 1, "Incremental" => 2)

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


struct ServerCapabilities <: Outbound
    textDocumentSync::Union{TextDocumentSyncOptions,TextDocumentSyncKind,Missing}
    hoverProvider::Union{Bool,Missing}
    completionProvider::Union{CompletionOptions,Missing}
    signatureHelpProvider::Union{SignatureHelpOptions,Missing}
    definitionProvider::Union{Bool,Missing}
    typeDefinitionProvider::Union{Bool,Missing}
    implementationProvider::Union{Bool,Missing}
    referencesProvider::Union{Bool,Missing}
    documentHighlightProvider::Union{Bool,Missing}
    documentSymbolProvider::Union{Bool,Missing}
    workspaceSymbolProvider::Union{Bool,Missing}
    codeActionProvider::Union{Bool,CodeActionOptions,Missing}
    codeLensProvider::Union{CodeLensOptions,Missing}
    documentFormattingProvider::Union{Bool,Missing}
    documentRangeFormattingProvider::Union{Bool,Missing}
    documentOnTypeFormattingProvider::Union{DocumentOnTypeFormattingOptions,Missing}
    renameProvider::Union{Bool,RenameOptions,Missing}
    documentLinkProvider::Union{DocumentLinkOptions,Missing}
    colorProvider::Union{Bool,ColorProviderOptions,Missing}
    foldingRangeProvider::Union{Bool,FoldingRangeProviderOptions,Missing}
    declarationProvider::Union{Bool,Missing}
    executeCommandProvider::Union{ExecuteCommandOptions,Missing}
    workspace::Union{WorkspaceOptions,Missing}
    experimental::Union{Any,Missing}
end

struct InitializeResult <: Outbound
    capabilities::ServerCapabilities
end

##############################################################################
struct InitializedParams end