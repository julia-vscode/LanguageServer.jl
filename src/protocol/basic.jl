# DocumentUri, Position, Range, Location, Diagnostic, Command, TextEdit

const DocumentUri = String

mutable struct Position
    line::Int
    character::Int

    Position(line::Integer, character::Integer;one_based = false) = new(line - one_based, character - one_based)
end

mutable struct Range
    start::Position
    stop::Position 
end

mutable struct Location
    uri::DocumentUri
    range::Range
end

mutable struct DiagnosticRelatedInformation
    location::Location
    message::String
end

mutable struct Diagnostic
    range::Range
    severity::Union{Nothing,Int}
    code::Union{Nothing,String}
    source::Union{Nothing,String}
    message::String
    relatedInformation::Union{Nothing,Vector{DiagnosticRelatedInformation}}
end

mutable struct Command
    title::String
    command::String
    arguments::Union{Nothing,Vector{Any}}
end

mutable struct TextEdit
    range::Range
    newText::String
end

@json_read mutable struct WorkspaceFolder
    uri::String
    name::String
end

mutable struct WorkspaceFoldersChangeEvent
    added::Vector{WorkspaceFolder}
    removed::Vector{WorkspaceFolder}
end

mutable struct didChangeWorkspaceFoldersParams
    event::WorkspaceFoldersChangeEvent
end

Position(d::Dict) = Position(d["line"], d["character"])
Position(line::Integer) = Position(line, 0)
Range(d::Dict) = Range(Position(d["start"]), Position(d["end"]))
Range(line::Integer) = Range(Position(line), Position(line))
Range(l0::Integer, c0::Integer, l1::Integer, c1::Integer) = Range(Position(l0, c0), Position(l1, c1))

# mismatch between vscode-ls protocol naming (should be 'end')
function JSON.lower(a::Range)
    Dict("start" => a.start, "end" => a.stop)
end

Location(d::Dict) = Location(d["uri"], Range(d["range"]))
Location(f::String, line::Integer) = Location(f, Range(line))

function Diagnostic(d::Dict)
    Diagnostic(Range(d["range"]),
                     haskeynotnull(d, "severity") ? d["severity"] : 0,
                     haskeynotnull(d, "code") ? d["code"] : "",
                     haskeynotnull(d, "source") ? d["source"] : "",
                     d["message"])
end

const DiagnosticSeverity = Dict("Error" => 1, "Warning" => 2, "Information" => 3, "Hint" => 4)

WorkspaceFolder(d::Dict) = WorkspaceFolder(d["uri"], d["name"])


function didChangeWorkspaceFoldersParams(d::Dict)
    added = WorkspaceFolder[WorkspaceFolder(i) for i in d["event"]["added"]]
    removed = WorkspaceFolder[WorkspaceFolder(i) for i in d["event"]["removed"]]

    return didChangeWorkspaceFoldersParams(WorkspaceFoldersChangeEvent(added, removed))
end
