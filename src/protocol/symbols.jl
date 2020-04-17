const SymbolKind = Int
const SymbolKinds = (File = 1,
                    Module = 2,
                    Namespace = 3,
                    Package = 4,
                    Class = 5,
                    Method = 6,
                    Property = 7,
                    Field = 8,
                    Constructor = 9,
                    Enum = 10,
                    Interface = 11,
                    Function = 12,
                    Variable = 13,
                    Constant = 14,
                    String = 15,
                    Number = 16,
                    Boolean = 17,
                    Array = 18,
                    Object = 19,
                    Key = 20,
                    Null = 21,
                    EnumMember = 22,
                    Struct = 23,
                    Event = 24,
                    Operator = 25,
                    TypeParameter = 26)

@dict_readable struct SymbolKindCapabilities
    valueSet::Union{Vector{SymbolKind},Missing}
end

@dict_readable struct DocumentSymbolClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
    symbolKind::Union{SymbolKindCapabilities,Missing}
    hierarchicalDocumentSymbolSupport::Union{Bool,Missing}
end

@dict_readable mutable struct WorkspaceSymbolClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
    symbolKind::Union{SymbolKindCapabilities,Missing}
end

struct DocumentSymbolOptions <: Outbound
    workDoneProgress::Union{Bool, Missing}
end

struct DocumentSymbolRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector, Nothing}
    workDoneProgress::Union{Bool, Missing}
end

struct WorkspaceSymbolOptions
    workDoneProgress::Union{Bool,Missing}
end

struct WorkspaceSymbolRegistrationOptions
    workDoneProgress::Union{Bool,Missing}
end


@dict_readable struct DocumentSymbolParams 
    textDocument::TextDocumentIdentifier
    workDoneToken::Union{ProgressToken,Missing}
    partialResultToken::Union{ProgressToken,Missing}
end 

@dict_readable struct WorkspaceSymbolParams 
    query::String 
    workDoneToken::Union{ProgressToken,Missing}
    partialResultToken::Union{ProgressToken,Missing}
end 

struct SymbolInformation <: Outbound
    name::String 
    kind::SymbolKind
    deprecated::Union{Bool,Missing}
    location::Location 
    containerName::Union{String,Missing}
end

struct DocumentSymbol <: Outbound
    name::String
    detail::Union{String,Missing}
    kind::SymbolKind
    deprecated::Union{Bool,Missing}
    range::Range
    selectionRange::Range
    children::Union{Vector{DocumentSymbol},Missing}
end
