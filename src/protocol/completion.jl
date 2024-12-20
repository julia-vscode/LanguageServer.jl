const CompletionItemKind = Int
const CompletionItemKinds = (Text=1,
    Method=2,
    Function=3,
    Constructor=4,
    Field=5,
    Variable=6,
    Class=7,
    Interface=8,
    Module=9,
    Property=10,
    Unit=11,
    Value=12,
    Enum=13,
    Keyword=14,
    Snippet=15,
    Color=16,
    File=17,
    Reference=18,
    Folder=19,
    EnumMember=20,
    Constant=21,
    Struct=22,
    Event=23,
    Operator=24,
    TypeParameter=25)

const CompletionItemTag = Int
const CompletionItemTags = (Deprecated = 1)

const CompletionTriggerKind = Int
const CompletionTriggerKinds = (Invoked=1,
    TriggerCharacter=2,
    TriggerForIncompleteCompletion=3)

const InsertTextFormat = Int
const InsertTextFormats = (PlainText=1,
    Snippet=2)

@dict_readable struct CompletionTagClientCapabilities
    valueSet::Vector{CompletionItemTag}
end

@dict_readable struct CompletionItemClientCapabilities <: Outbound
    snippetSupport::Union{Bool,Missing}
    commitCharactersSupport::Union{Bool,Missing}
    documentationFormat::Union{Vector{String},Missing}
    deprecatedSupport::Union{Bool,Missing}
    preselectSupport::Union{Bool,Missing}
    tagSupport::Union{CompletionTagClientCapabilities,Missing}
end

@dict_readable struct CompletionItemKindCapabilities <: Outbound
    valueSet::Union{Vector{CompletionItemKind},Missing}
end

@dict_readable struct CompletionClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    completionItem::Union{CompletionItemClientCapabilities,Missing}
    completionItemKind::Union{CompletionItemKindCapabilities,Missing}
    contextSupport::Union{Bool,Missing}
end

struct CompletionOptions <: Outbound
    resolveProvider::Union{Bool,Missing}
    triggerCharacters::Union{Vector{String},Missing}
    workDoneProgress::Union{Bool,Missing}
end

struct CompletionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    triggerCharacters::Union{Vector{String},Missing}
    allCommitCharacters::Union{Vector{String},Missing}
    resolveProvider::Union{Bool,Missing}
end

struct CompletionContext <: Outbound
    triggerKind::CompletionTriggerKind
    triggerCharacter::Union{String,Missing}
end

function CompletionContext(d::Dict)
    CompletionContext(d["triggerKind"], haskey(d, "triggerCharacter") && d["triggerCharacter"] isa String ? d["triggerCharacter"] : missing)
end

@dict_readable struct CompletionParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    context::Union{CompletionContext,Missing}
end

struct CompletionItem <: Outbound
    label::String
    kind::Union{Int,Missing}
    tags::Union{CompletionItemTag,Missing}
    detail::Union{String,Missing}
    documentation::Union{String,MarkupContent,Missing}
    deprecated::Union{Bool,Missing}
    preselect::Union{Bool,Missing}
    sortText::Union{String,Missing}
    filterText::Union{String,Missing}
    insertText::Union{String,Missing}
    insertTextFormat::Union{InsertTextFormat,Missing}
    textEdit::Union{TextEdit,Missing}
    additionalTextEdits::Union{Vector{TextEdit},Missing}
    commitCharacters::Union{Vector{String},Missing}
    command::Union{Command,Missing}
    data::Union{Any,Missing}
end
CompletionItem(label, kind, documentation, textEdit) = CompletionItem(label, kind, missing, missing, documentation, missing, missing, missing, missing, missing, InsertTextFormats.PlainText, textEdit, missing, missing, missing, missing)
CompletionItem(label, kind, detail, documentation, textEdit) = CompletionItem(label, kind, missing, detail, documentation, missing, missing, missing, missing, missing, InsertTextFormats.PlainText, textEdit, missing, missing, missing, missing)

struct CompletionList <: Outbound
    isIncomplete::Bool
    items::Vector{CompletionItem}
end
