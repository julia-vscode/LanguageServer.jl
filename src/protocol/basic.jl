mutable struct CancelParams
    id::Union{String,Int64}
end
CancelParams(d::Dict) = CancelParams(d["id"])

const TraceValue = String

struct SetTraceParams
    value::TraceValue
end
SetTraceParams(d::Dict) = SetTraceParams(d["value"])

struct ProgressParams{T}
    token::Union{Int,String} # ProgressToken
    value::T
end

mutable struct DocumentFilter <: Outbound
    language::Union{String,Missing}
    scheme::Union{String,Missing}
    pattern::Union{String,Missing}
end
const DocumentSelector = Vector{DocumentFilter}
const DocumentUri = URI

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
    uri::DocumentUri
    name::String
end

##############################################################################
# Diagnostics
const DiagnosticSeverity = Int
const DiagnosticSeverities = (Error=1,
    Warning=2,
    Information=3,
    Hint=4)

const DiagnosticTag = Int
const DiagnosticTags = (Unnecessary=1,
    Deprecated=2)

@dict_readable struct DiagnosticRelatedInformation <: Outbound
    location::Location
    message::String
end

@dict_readable struct CodeDescription <: Outbound
    href::URI
end

@dict_readable struct Diagnostic <: Outbound
    range::Range
    severity::Union{DiagnosticSeverity,Missing}
    code::Union{String,Missing}
    codeDescription::Union{CodeDescription,Missing}
    source::Union{String,Missing}
    message::String
    tags::Union{Vector{DiagnosticTag},Missing}
    relatedInformation::Union{Vector{DiagnosticRelatedInformation},Missing}
end

##############################################################################

struct Command <: Outbound # Use traits for this?
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
const MarkupKind = String
const MarkupKinds = (PlainText="plaintext",
    Markdown="markdown")

mutable struct MarkupContent
    kind::MarkupKind
    value::String
end
MarkupContent(value::String) = MarkupContent(MarkupKinds.Markdown, value)

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
const MessageTypes = (Error=1,
    Warning=2,
    Info=3,
    Log=4)

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

##############################################################################
# Progress
struct WorkDoneProgressCreateParams <: Outbound
    token::Union{Int,String} # ProgressToken
end

@dict_readable struct WorkDoneProgressCancelParams
    token::Union{Int,String} # ProgressToken
end

struct WorkDoneProgressBegin <: Outbound
    kind::String
    title::String
    cancellable::Union{Bool,Missing}
    message::Union{String,Missing}
    percentage::Union{Int,Missing}
    function WorkDoneProgressBegin(title, cancellable, message, percentage)
        new("begin", title, cancellable, message, percentage)
    end
end

struct WorkDoneProgressReport <: Outbound
    kind::String
    cancellable::Union{Bool,Missing}
    message::Union{String,Missing}
    percentage::Union{Int,Missing}
    function WorkDoneProgressReport(cancellable, message, percentage)
        new("report", cancellable, message, percentage)
    end
end

struct WorkDoneProgressEnd <: Outbound
    kind::String
    message::Union{String,Missing}
    function WorkDoneProgressEnd(message)
        new("end", message)
    end
end

struct WorkDoneProgressParams <: Outbound
    workDoneToken::Union{Int,String,Missing} # ProgressToken
end

struct WorkDoneProgressOptions <: Outbound
    workDoneProgress::Union{Bool,Missing}
end

##############################################################################
# Partial

struct PartialResultParams <: Outbound
    partialResultToken::Union{Int,String,Missing} # ProgressToken
end
