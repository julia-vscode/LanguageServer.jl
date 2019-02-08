mutable struct LSDiagnostic{C}
    loc::UnitRange{Int}
    actions::Vector{Any}
    message::String
end

mutable struct Document
    _uri::String
    _content::String
    _line_offsets::Union{Nothing,Vector{Int}}
    _open_in_editor::Bool
    _workspace_file::Bool
    code::StaticLint.File
    diagnostics::Vector{LSDiagnostic}
    _version::Int
    _runlinter::Bool
end
function Document(uri::AbstractString, text::AbstractString, workspace_file::Bool, server = nothing, index = (), nb = 0, parent = "")
    path = uri2filepath(uri)
    cst = CSTParser.parse(text, true)
    state = StaticLint.State(path, server)
    s = StaticLint.Scope(nothing, StaticLint.Scope[], cst.span,  CSTParser.TopLevel, index, nb)
    scope = StaticLint.pass(cst, state, s, index, false, false)
    file = StaticLint.File(cst, state, scope, index, nb, "", [], [])
    return Document(uri, text, nothing, false, workspace_file, file, [], 0, true)
end

StaticLint.CST(doc::Document) = doc.code


function get_text(doc::Document)
    return doc._content
end

function set_open_in_editor(doc::Document, value::Bool)
    doc._open_in_editor = value
end

function get_open_in_editor(doc::Document)
    return doc._open_in_editor
end

function is_workspace_file(doc::Document)
    return doc._workspace_file
end

"""
    get_offset(doc, line, char)

Returns the byte offset position corresponding to a line/character position. 
This takes 0 based line/char inputs. Corresponding functions are available for
Position and Range arguments, the latter returning a UnitRange{Int}.
"""
function get_offset(doc::Document, line::Integer, character::Integer)
    line_offsets = get_line_offsets(doc)
    offset = line_offsets[line + 1]
    while character > 0
        offset = nextind(doc._content, offset)
        character -= 1
    end
    return offset
end
get_offset(doc, p::Position) = get_offset(doc, p.line, p.character)
get_offset(doc, r::Range) = get_offset(doc, r.start):get_offset(doc, r.stop)


"""
    get_line_offsets(doc::Document)
    
Updates the doc._line_offsets field, an n length Array each entry of which 
gives the byte offset position of the start of each line. This always starts 
with 0 for the first line (even if empty).
"""
function get_line_offsets(doc::Document)
    doc._line_offsets = Int[0]
    text = doc._content
    ind = firstindex(text)
    while ind <= lastindex(text)
        c = text[ind]
        nl = c == '\n' || c == '\r'
        if c == '\r' && ind + 1 <= lastindex(text) && text[ind + 1] == '\n'
            ind += 1
        end
        nl && push!(doc._line_offsets, ind)
        ind = nextind(text, ind)
    end
    
    return doc._line_offsets
end

function get_line_of(line_offsets::Vector{Int}, offset::Integer)
    nlines = length(line_offsets)
    if offset > last(line_offsets)
        line = nlines
    else
        line = 1
        while line < nlines
            if line_offsets[line] <= offset < line_offsets[line + 1]
                break
            end
            line += 1
        end
    end
    return line, line_offsets[line]
end

"""
    get_position_at(doc, offset)

Returns the 0-based line and character position within a document of a given
byte offset.
"""
function get_position_at(doc::Document, offset::Integer)
    offset > sizeof(doc._content) && error("offset > sizeof(content)")
    line_offsets = get_line_offsets(doc)
    line, ind = get_line_of(doc._line_offsets, offset)
    char = 0
    while offset > ind
        ind = nextind(doc._content, ind)
        char += 1
    end
    return line - 1, char
end

"""
    Range(Doc, rng)
Converts a byte offset range to a LSP Range.
"""
function Range(doc::Document, rng::UnitRange)
    start_l, start_c = get_position_at(doc, first(rng))
    end_l, end_c = get_position_at(doc, last(rng))
    rng = Range(start_l, start_c, end_l, end_c)
end
