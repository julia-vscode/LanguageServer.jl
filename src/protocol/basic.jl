# DocumentUri, Position, Range, Location, Diagnostic, Command, TextEdit

const DocumentUri = String

type Position
    line::Int
    character::Int

    function Position(line::Integer, character::Integer;one_based=false)
        if one_based
            return new(line-1, character-1)
        else
            return new(line, character)
        end
    end
end
Position(d::Dict) = Position(d["line"], d["character"])
Position(line::Integer) = Position(line, 0)


type Range
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

type Location
    uri::String
    range::Range
end
Location(d::Dict) = Location(d["uri"], Range(d["range"]))
Location(f::String, line::Integer) = Location(f, Range(line))

type Diagnostic
    range::Range
    severity::Int
    code::String
    source::String
    message::String
end
Diagnostic(d::Dict) = Diagnostic(Range(d["range"]), d["severity"], d["code"], d["source"], d["message"])

const DiagnosticSeverity = Dict("Error" => 1, "Warning" => 2, "Information" => 3, "Hint" => 4)


type Command
    title::String
    command::String
    argument::Vector{Any}
end

type TextEdit
    range::Range
    newText::String
end

