@dict_readable struct HoverClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    contentFormat::Union{Vector{String},Missing}
end

@dict_readable struct HoverParams <: Outbound
    textDocument::TextDocumentIdentifier
    position::Position
    workDoneToken::Union{ProgressToken, Missing}
end

struct HoverOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

struct HoverRegistrationOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
    documentSelector::Union{DocumentSelector,Nothing}
end

struct Hover <: Outbound
    contents::Union{MarkedString,Vector{MarkedString},MarkupContent}
    range::Union{Range,Missing}
end
