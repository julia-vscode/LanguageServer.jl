# DocumentUri, Position, Range, Location, Diagnostic, Command, TextEdit

const DocumentUri = String

mutable struct Position
    line::Int
    character::Int

    Position(line::Integer, character::Integer;one_based = false) = new(line - one_based, character - one_based)
end
Position(d::Dict) = Position(d["line"], d["character"])
Position(line::Integer) = Position(line, 0)


mutable struct Range
    start::Position
    stop::Position 
end
Range(d::Dict) = Range(Position(d["start"]), Position(d["end"]))
Range(line::Integer) = Range(Position(line), Position(line))
Range(l0::Integer, c0::Integer, l1::Integer, c1::Integer) = Range(Position(l0, c0), Position(l1, c1))

# mismatch between vscode-ls protocol naming (should be 'end')
function JSON.lower(a::Range)
    Dict("start" => a.start, "end" => a.stop)
end

mutable struct Location
    uri::String
    range::Range
end
Location(d::Dict) = Location(d["uri"], Range(d["range"]))
Location(f::String, line::Integer) = Location(f, Range(line))

mutable struct Diagnostic
    range::Range
    severity::Int
    code::String
    source::String
    message::String
end

function Diagnostic(d::Dict)
    Diagnostic(Range(d["range"]),
                     haskeynotnull(d, "severity") ? d["severity"] : 0,
                     haskeynotnull(d, "code") ? d["code"] : "",
                     haskeynotnull(d, "source") ? d["source"] : "",
                     d["message"])
end
# Diagnostic(d::Dict) = Diagnostic(Range(d["range"]), d["severity"], d["code"], d["source"], d["message"])

const DiagnosticSeverity = Dict("Error" => 1, "Warning" => 2, "Information" => 3, "Hint" => 4)


mutable struct Command
    title::String
    command::String
    arguments::Vector{Any}
end

mutable struct TextEdit
    range::Range
    newText::String
end

mutable struct WorkspaceFolder
    uri::String
    name::String
end
WorkspaceFolder(d::Dict) = WorkspaceFolder(d["uri"], d["name"])
