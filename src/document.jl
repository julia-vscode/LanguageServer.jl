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

function get_offset(doc::Document, line::Integer, character::Integer)
    line_offsets = get_line_offsets(doc)
    current_offset = isempty(line_offsets) ? 0 : line_offsets[line]
    for i = 1:character - 1
        current_offset = nextind(doc._content, current_offset)
    end
    return current_offset
end

function update(doc::Document, start_line::Integer, start_character::Integer, length::Integer, new_text::AbstractString)
    text = doc._content
    start_offset = start_line == 1 && start_character == 1 ? 1 : get_offset(doc, start_line, start_character)
    end_offset = start_offset
    for i = 1:length
        end_offset = nextind(text, end_offset)
    end

    doc._content = string(doc._content[1:start_offset - 1], new_text, doc._content[end_offset:end])
    doc._line_offsets = nothing
end

function get_line_offsets(doc::Document)
    if doc._line_offsets isa Nothing
        line_offsets = Array{Int}(undef, 0)
        text = doc._content
        is_line_start = true
        i = 1
        while i <= lastindex(text)
            if is_line_start
                push!(line_offsets, i)
                is_line_start = false
            end
            ch = text[i]
            is_line_start = ch == '\r' || ch == '\n'
            if ch == '\r' && i + 1 <= lastindex(text) && text[i + 1] == '\n'
                i += 1
            end
            i = nextind(text, i)
        end

        if is_line_start && length(text) > 0
            push!(line_offsets, lastindex(text) + 1)
        end

        doc._line_offsets = line_offsets
    end

    return doc._line_offsets
end

function iter_lines(doc, line_offsets, offset)
    for (line, line_offset) in enumerate(line_offsets)
        if offset < line_offset
            if offset == line_offset - 1
                return line, 0
            else
                line -= 1
                return line, 1
            end
        end
    end
    return length(line_offsets), 1
end

function get_position_at(doc::Document, offset::Integer)
    offset == 0 && return 1, 0
    line_offsets = get_line_offsets(doc)
    line, ch = iter_lines(doc, line_offsets, offset)
    if ch == 0 
        return line, ch
    end
    
    ni = nextind(doc._content, line_offsets[line])
    ch = 1
    while offset >= ni && ni < sizeof(doc._content)
        ch += 1
        ni = nextind(doc._content, ni)
    end
    return line, ch
end

function Range(doc::Document, rng::UnitRange)
    start_l, start_c = get_position_at(doc, first(rng))
    end_l, end_c = get_position_at(doc, last(rng))
    rng = Range(start_l - 1, start_c, end_l - 1, end_c)
end
