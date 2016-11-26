## basic language-server protocol types ##

type Position
    line::Int
    character::Int
end
Position(d::Dict) = Position(d["line"], d["character"])
Position(line) = Position(line,0)

type Range
    start::Position
    stop::Position # mismatch between vscode-ls protocol naming (should be 'end')
end
Range(d::Dict) = Range(Position(d["start"]), Position(d["end"]))
Range(line) = Range(Position(line), Position(line))

function JSON._writejson(io::IO, state::JSON.State, a::Range)
    Base.print(io,"{\"start\":")
    JSON._writejson(io,state,a.start)
    Base.print(io,",\"end\":")
    JSON._writejson(io,state,a.stop)
    Base.print(io,"}")
end

import Base:<, in, intersect
<(a::Position, b::Position) =  a.line<b.line || (a.line≤b.line && a.character<b.character)
function in(p::Position, r::Range)
    (r.start.line < p.line < r.stop.line) ||
    (r.start.line == p.line && r.start.character ≤ p.character) ||
    (r.stop.line == p.line && p.character ≤ r.stop.character)  
end

intersect(a::Range, b::Range) = a.start in b || b.start in a

type Location
    uri::String
    range::Range
end
Location(d::Dict) = Location(d["uri"], Range(d["range"]))
Location(f::String, line) = Location(f, Range(line))

type MarkedString
    language::String
    value::AbstractString
end
MarkedString(x) = MarkedString("julia", x::AbstractString)

## text document identifier types ##

type TextDocumentIdentifier
    uri::String
end
TextDocumentIdentifier(d::Dict) = TextDocumentIdentifier(d["uri"])

type VersionedTextDocumentIdentifier
    uri::String
    version::Int
end
VersionedTextDocumentIdentifier(d::Dict) = VersionedTextDocumentIdentifier(d["uri"], d["version"])

type TextDocumentItem
    uri::String
    languageId::String
    version::Int
    text::String
end
TextDocumentItem(d::Dict) = TextDocumentItem(d["uri"], d["languageId"], d["version"], d["text"])

type TextDocumentPositionParams
    textDocument::TextDocumentIdentifier
    position::Position
end
TextDocumentPositionParams(d::Dict) = TextDocumentPositionParams(TextDocumentIdentifier(d["textDocument"]), Position(d["position"]))

## miscellaneous types ##

type CancelParams
    id::Union{String,Int64}
end
CancelParams(d::Dict) = CancelParams(d["id"])

type Diagnostic
    range::Range
    severity::Int
    code::String
    source::String
    message::String
end

# Meta info on a symbol available either in the Main namespace or 
# locally (i.e. in a function, type definition)
type VarInfo
    t::Any # indicator of variable type
    doc::String
end

# A block of sequential ASTs corresponding to ranges in the source
# file including leading whitspace. May contain informtion on local 
# variables where possible.
type Block
    uptodate::Bool
    ex::Any
    range::Range
    name::String
    var::VarInfo
    localvar::Dict{String,VarInfo}
    diags::Vector{Diagnostic}
end

type Document
    data::Vector{UInt8}
    blocks::Vector{Block}
end