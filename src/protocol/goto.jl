# Declaration
@dict_readable struct DeclarationClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct DeclarationOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct DeclarationRegistrationOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
    documentSelector::Union{DocumentSelector,Nothing}
    id::Union{String,Missing}
end

@dict_readable struct DeclarationParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{Int,String,Missing} # ProgressToken
    partialResultToken::Union{Int,String,Missing} # ProgressToken
end

##############################################################################
# Definition
@dict_readable struct DefinitionClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct DefinitionOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct DefinitionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct DefinitionParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{Int,String,Missing} # ProgressToken
    partialResultToken::Union{Int,String,Missing} # ProgressToken
end

##############################################################################
# Type definition
@dict_readable struct TypeDefinitionClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct TypeDefinitionOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct TypeDefinitionRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
    id::Union{String,Missing}
end

@dict_readable struct TypeDefinitionParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{Int,String,Missing} # ProgressToken
    partialResultToken::Union{Int,String,Missing} # ProgressToken
end

##############################################################################
# Implementation
@dict_readable struct ImplementationClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    linkSupport::Union{Bool,Missing}
end

struct ImplementationOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct ImplementationRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
    id::Union{String,Missing}
end

@dict_readable struct ImplementationParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{Int,String,Missing} # ProgressToken
    partialResultToken::Union{Int,String,Missing} # ProgressToken
end

##############################################################################
# References
@dict_readable struct ReferenceClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
end

struct ReferenceOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct ReferenceRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct ReferenceContext
    includeDeclaration::Bool
end

@dict_readable struct ReferenceParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{Int,String,Missing} # ProgressToken
    partialResultToken::Union{Int,String,Missing} # ProgressToken
    context::ReferenceContext
end
