# WorkspaceClientCapabilities, TextDocumentClientCapabilities
# Initialisation

# From client

mutable struct WorkspaceEditCapabilities
    documentChanges::Bool
end
WorkspaceEditCapabilities(d::Dict) = haskeynotnull(d, "applyEdit") ? WorkspaceEditCapabilities(d["applyEdit"]) : WorkspaceEditCapabilities(false)
WorkspaceEditCapabilities() = WorkspaceEditCapabilities(false)

mutable struct Capabilities
    dynamicRegistration::Bool
end
Capabilities(d::Dict) = haskeynotnull(d, "dynamicRegistration") ? Capabilities(d["dynamicRegistration"]) : Capabilities()
Capabilities() = Capabilities(false)

mutable struct WorkspaceClientCapabilities
    applyEdit::Nullable{Bool}
    workspaceEdit::WorkspaceEditCapabilities
    didChangeConfiguration::Capabilities
    didChangeWatchedFiles::Capabilities
    symbol::Capabilities
    executeCommand::Capabilities
end

function WorkspaceClientCapabilities(d::Dict)
    applyEdit = haskeynotnull(d, "applyEdit") ? Nullable{Bool}(d["applyEdit"]) : Nullable{Bool}()
    workspaceEdit = haskeynotnull(d, "workspaceEdit") ? WorkspaceEditCapabilities(d["workspaceEdit"]) : WorkspaceEditCapabilities()
    didChangeConfiguration = haskeynotnull(d, "didChangeConfiguration") ? Capabilities(d["didChangeConfiguration"]) : Capabilities()
    didChangeWatchedFiles = haskeynotnull(d, "didChangeWatchedFiles") ? Capabilities(d["didChangeWatchedFiles"]) : Capabilities()
    symbol = haskeynotnull(d, "symbol") ? Capabilities(d["symbol"]) : Capabilities()
    executeCommand = haskeynotnull(d, "executeCommand") ? Capabilities(d["executeCommand"]) : Capabilities()
    return WorkspaceClientCapabilities(applyEdit, workspaceEdit, didChangeConfiguration, didChangeWatchedFiles, symbol, executeCommand)
end
WorkspaceClientCapabilities() = WorkspaceClientCapabilities(Dict())

mutable struct SynchroizationCapabilities
    dynamicRegistration::Bool
    willSave::Bool
    willSaveWaitUntil::Bool
    didSave::Bool
end
function SynchroizationCapabilities(d::Dict)
    dynamicRegistration = haskeynotnull(d, "dynamicRegistration") ? d["dynamicRegistration"] : false
    willSave = haskeynotnull(d, "willSave") ? d["willSave"] : false
    willSaveWaitUntil = haskeynotnull(d, "willSaveWaitUntil") ? d["willSaveWaitUntil"] : false
    didSave = haskeynotnull(d, "didSave") ? d["didSave"] : false
    return SynchroizationCapabilities(dynamicRegistration, willSave, willSaveWaitUntil, didSave)
end
SynchroizationCapabilities() = SynchroizationCapabilities(false, false, false, false)

mutable struct CompletionItemCapabilities
    snippetSupport::Bool
end
CompletionItemCapabilities(d::Dict) = haskeynotnull(d, "snippetSupport") ? CompletionItemCapabilities(d["snippetSupport"]) : CompletionItemCapabilities(false)
CompletionItemCapabilities() = CompletionItemCapabilities(false)

mutable struct CompletionCapabilities
    dynamicRegistration::Bool
    completionItem::CompletionItemCapabilities
end
function CompletionCapabilities(d::Dict)
    dynamicRegistration = haskeynotnull(d, "dynamicRegistration")  ? d["dynamicRegistration"] : false
    completionItem      = haskeynotnull(d, "completionItem")       ? CompletionItemCapabilities(d["completionItem"]) : CompletionItemCapabilities()
    return CompletionCapabilities(dynamicRegistration, completionItem)
end
CompletionCapabilities() = CompletionCapabilities(false, CompletionItemCapabilities())

mutable struct TextDocumentClientCapabilities
    synchroization::SynchroizationCapabilities
    completion::CompletionCapabilities
    hover::Capabilities
    signatureHelp::Capabilities
    references::Capabilities
    documentHighlight::Capabilities
    documentSymbol::Capabilities
    formatting::Capabilities
    rangeFormatting::Capabilities
    onTypeFormatting::Capabilities
    definition::Capabilities
    codeAction::Capabilities
    CodeLens::Capabilities
    documentLink::Capabilities
    rename::Capabilities
end
function TextDocumentClientCapabilities(d::Dict)
    synchroization      = haskeynotnull(d, "synchroization")   ? SynchroizationCapabilities(d["synchroization"])   : SynchroizationCapabilities()
    completion          = haskeynotnull(d, "completion")       ? CompletionCapabilities(d["completion"])           : CompletionCapabilities()
    hover               = haskeynotnull(d, "hover")            ? Capabilities(d["hover"])                          : Capabilities()
    signatureHelp       = haskeynotnull(d, "signatureHelp")    ? Capabilities(d["signatureHelp"])                  : Capabilities()
    references          = haskeynotnull(d, "references")       ? Capabilities(d["references"])                     : Capabilities()
    documentHighlight   = haskeynotnull(d, "documentHighlight") ? Capabilities(d["documentHighlight"])             : Capabilities()
    documentSymbol      = haskeynotnull(d, "documentSymbol")   ? Capabilities(d["documentSymbol"])                 : Capabilities()
    formatting          = haskeynotnull(d, "formatting")       ? Capabilities(d["formatting"])                     : Capabilities()
    rangeFormatting     = haskeynotnull(d, "rangeFormatting")  ? Capabilities(d["rangeFormatting"])                : Capabilities()
    onTypeFormatting    = haskeynotnull(d, "onTypeFormatting") ? Capabilities(d["onTypeFormatting"])               : Capabilities()
    definition          = haskeynotnull(d, "definition")       ? Capabilities(d["definition"])                     : Capabilities()
    codeAction          = haskeynotnull(d, "codeAction")       ? Capabilities(d["codeAction"])                     : Capabilities()
    CodeLens            = haskeynotnull(d, "CodeLens")         ? Capabilities(d["CodeLens"])                       : Capabilities()
    documentLink        = haskeynotnull(d, "documentLink")     ? Capabilities(d["documentLink"])                   : Capabilities()
    rename              = haskeynotnull(d, "rename")           ? Capabilities(d["rename"])                         : Capabilities()
    return TextDocumentClientCapabilities(synchroization, completion, hover, signatureHelp, references, documentHighlight, documentSymbol, formatting, rangeFormatting, onTypeFormatting, definition, codeAction, CodeLens, documentLink, rename)
end
TextDocumentClientCapabilities() = TextDocumentClientCapabilities(SynchroizationCapabilities(), 
                                                                  CompletionCapabilities(), 
                                                                  Capabilities(), 
                                                                  Capabilities(), 
                                                                  Capabilities(), 
                                                                  Capabilities(), 
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities(),
                                                                  Capabilities())

mutable struct ClientCapabilities
    workspace::WorkspaceClientCapabilities
    textDocument::TextDocumentClientCapabilities
    experimental::Any
end

function ClientCapabilities(d::Dict)
    workspace = haskeynotnull(d, "workspace") ? WorkspaceClientCapabilities(d["workspace"]) : WorkspaceClientCapabilities()
    textDocument = haskeynotnull(d, "textDocument") ? TextDocumentClientCapabilities(d["textDocument"]) : TextDocumentClientCapabilities()
    return ClientCapabilities(workspace, textDocument, nothing)
end

mutable struct InitializeParams
    processId::Int
    rootPath::Nullable{DocumentUri}
    rootUri::Nullable{DocumentUri}
    initializationOptions::Nullable{Any}
    capabilities::ClientCapabilities
    trace::Nullable{String}
end

function InitializeParams(d::Dict)
    return InitializeParams(d["processId"],
                            haskeynotnull(d, "rootPath") ? d["rootPath"] : Nullable{DocumentUri}(),
                            haskeynotnull(d, "rootUri") ? d["rootUri"] : Nullable{DocumentUri}(),
                            haskeynotnull(d, "initializationOptions") ? d["initializationOptions"] : Nullable{Any}(),
                            ClientCapabilities(d["capabilities"]),
                            haskeynotnull(d, "trace") ? d["trace"] : Nullable{String}())
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
CodeLensOptions() = CodeLensOptions(false)

mutable struct DocumentOnTypeFormattingOptions
    firstTriggerCharacter::String
    moreTriggerCharacters::Vector{String}
end
DocumentOnTypeFormattingOptions() = DocumentOnTypeFormattingOptions("", [])

mutable struct DocumentLinkOptions
    resolveProvider::Bool
end

mutable struct ExecuteCommandOptions
    commands::Vector{String}
end
ExecuteCommandOptions() = ExecuteCommandOptions([])

mutable struct SaveOptions
    includeText::Bool
end
const TextDocumentSyncKind = Dict("None" => 0, "Full" => 1, "Incremental" => 2)

mutable struct TextDocumentSyncOptions
    openClose::Bool
    change::Int
    willSave::Bool
    willSaveWaitUntil::Bool
    save::SaveOptions
end

mutable struct ServerCapabilities
    textDocumentSync::Int
    hoverProvider::Bool
    completionProvider::CompletionOptions
    signatureHelpProvider::SignatureHelpOptions
    definitionProvider::Bool
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
    executeCommandProvider::ExecuteCommandOptions
    experimental
end

mutable struct InitializeResult
    capabilities::ServerCapabilities
end



# Configuration

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
