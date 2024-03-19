@dict_readable struct ParameterInformationCapabilities <: Outbound
    labelOffsetSupport::Union{Bool,Missing}
end

@dict_readable struct SignatureInformationCapabilities <: Outbound
    documentationFormat::Union{Vector{String},Missing}
    parameterInformation::Union{ParameterInformationCapabilities,Missing}
end

@dict_readable struct SignatureHelpClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    signatureInformation::Union{SignatureInformationCapabilities,Missing}
    contextSupport::Union{Bool,Missing}
end

const SignatureHelpTriggerKind = Int
const SignatureHelpTriggerKinds = (Invoked=1,
    TriggerCharacter=2,
    ContentChange=3)

struct SignatureHelpOptions <: Outbound
    triggerCharacters::Union{Vector{String},Missing}
    retriggerCharacters::Union{Vector{String},Missing}
end

struct SignatureHelpRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    triggerCharacters::Union{Vector{String},Missing}
    retriggerCharacters::Union{Vector{String},Missing}
end

struct ParameterInformation <: Outbound
    label::Union{String,Tuple{Int,Int}}
    documentation::Union{String,MarkupContent,Missing}
end

struct SignatureInformation <: Outbound
    label::String
    documentation::Union{String,MarkedString,Missing}
    parameters::Union{Vector{ParameterInformation},Missing}
end

struct SignatureHelp <: Outbound
    signatures::Vector{SignatureInformation}
    activeSignature::Union{Int,Missing}
    activeParameter::Union{Int,Missing}
end

@dict_readable struct SignatureHelpContext <: Outbound
    triggerKind::SignatureHelpTriggerKind
    triggerCharacter::Union{String,Missing}
    isRetrigger::Bool
    activeSignatureHelp::Union{SignatureHelp,Missing}
end

@dict_readable struct SignatureHelpParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    context::Union{SignatureHelpContext,Missing}
    workDoneToken::Union{Int,String,Missing} # ProgressToken
end
