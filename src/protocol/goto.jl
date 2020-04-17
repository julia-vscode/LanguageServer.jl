# Declaration
@dict_readable struct DeclarationClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct DeclarationOptions <: Outbound
    workDoneProgress::Union{Bool, Missing}
end

struct DeclarationRegistrationOptions <: Outbound
    workDoneProgress::Union{Bool, Missing}
    documentSelector::Union{DocumentSelector,Nothing}
    id::Union{String,Missing}
end

@dict_readable struct DeclarationParams
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
    partialResultToken::Union{ProgressToken, Missing}
end

##############################################################################
# Definition
@dict_readable struct DefinitionClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct DefinitionOptions <: Outbound
    workDoneProgress::Union{Bool, Missing}
end

struct DefinitionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector, Nothing}
    workDoneProgress::Union{Bool, Missing}
end

@dict_readable struct DefinitionParams
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
    partialResultToken::Union{ProgressToken, Missing}
end

##############################################################################
# Type definition
@dict_readable struct TypeDefinitionClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct TypeDefinitionOptions
    workDoneProgress::Union{Bool, Missing}
end

struct TypeDefinitionRegistrationOptions
    documentSelector::Union{DocumentSelector, Nothing}
    workDoneProgress::Union{Bool, Missing}
    id::Union{String, Missing}
end

@dict_readable struct TypeDefinitionParams
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
    partialResultToken::Union{ProgressToken, Missing}
end

##############################################################################
# Implementation
@dict_readable struct ImplementationClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct ImplementationOptions
    workDoneProgress::Union{Bool, Missing}
end

struct ImplementationRegistrationOptions
    documentSelector::Union{DocumentSelector, Nothing}
    workDoneProgress::Union{Bool, Missing}
    id::Union{String, Missing}
end

@dict_readable struct ImplementationParams
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
    partialResultToken::Union{ProgressToken, Missing}
end

##############################################################################
# References
@dict_readable struct ReferenceClientCapabilities
    dynamicRegistration::Union{Bool,Missing}
end

struct ReferenceOptions
    workDoneProgress::Union{Bool, Missing}
end

struct ReferenceRegistrationOptions
    documentSelector::Union{DocumentSelector, Nothing}
    workDoneProgress::Union{Bool, Missing}
end

@dict_readable struct ReferenceContext
    includeDeclaration::Bool
end

@dict_readable struct ReferenceParams
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
    partialResultToken::Union{ProgressToken, Missing}
    context::ReferenceContext
end