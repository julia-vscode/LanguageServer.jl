const DocumentUri = String

@dict_readable struct Position
    line::Int
    character::Int
end
Position(line::Integer) = Position(line, 0)

struct Range
    start::Position
    stop::Position 
end
# Special case to account for use of 'end' as a fieldname in LSP
Range(d::Dict) = Range(Position(d["start"]), Position(d["end"]))
Range(line::Integer) = Range(Position(line), Position(line))
Range(l0::Integer, c0::Integer, l1::Integer, c1::Integer) = Range(Position(l0, c0), Position(l1, c1))
function JSON.lower(a::Range)
    Dict("start" => a.start, "end" => a.stop)
end

@dict_readable struct Location
    uri::DocumentUri
    range::Range
end
Location(f::String, line::Integer) = Location(f, Range(line))


@dict_readable struct LocationLink <: Outbound
    originalSelectionRange::Union{Range,Missing}
    targetUri::DocumentUri
    targetRange::Range
    targetSelectionRange::Range
end

@dict_readable struct WorkspaceFolder
    uri::String
    name::String
end

##############################################################################
# Diagnostics 
struct DiagnosticRelatedInformation
    location::Location
    message::String
end

struct Diagnostic <: Outbound
    range::Range
    severity::Union{Int,Missing}
    code::Union{String,Missing}
    source::Union{String,Missing}
    message::String
    relatedInformation::Union{Vector{DiagnosticRelatedInformation},Missing}
end

const DiagnosticSeverity = Dict("Error" => 1, "Warning" => 2, "Information" => 3, "Hint" => 4)

##############################################################################

struct Command <: HasMissingFields
    title::String
    command::String
    arguments::Union{Vector{Any},Missing}
end

struct TextEdit
    range::Range
    newText::String
end

##############################################################################
# Markup
const MarkupKind = ("plaintext", "markdown")

mutable struct MarkupContent
   kind::String
   value::String
end
MarkupContent(value::String) = MarkupContent("markdown", value)

mutable struct MarkedString
    language::String
    value::AbstractString
end

Base.convert(::Type{MarkedString}, x::String) = MarkedString("julia", string(x))
MarkedString(x) = MarkedString("julia", string(x))
Base.hash(x::MarkedString) = hash(x.value) # for unique


##############################################################################
# Window

const MessageType = Int
const MessageTypes = Dict("Error" => 1, "Warning" => 2, "Info" => 3, "Log" => 4)

struct ShowMessageParams <: Outbound
    type::MessageType
    message::String
end

struct MessageActionItem <: Outbound
    title::String
end

mutable struct ShowMessageRequestParams <: Outbound
    type::MessageType
    message::String
    actions::Union{Vector{MessageActionItem},Missing}
end

mutable struct LogMessageParams <: Outbound
    type::Integer
    message::String
end
