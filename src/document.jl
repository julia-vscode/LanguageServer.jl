immutable Scope
    uri::String
    modules::Vector{Union{Symbol,Expr}}
    list::Dict
    loc::Int
end

type Document
    _uri::String
    _content::String
    _line_offsets::Nullable{Vector{Int}}
    _open_in_editor::Bool
    _workspace_file::Bool
    blocks::Parser.File
    global_namespace::Scope
    diagnostics::Vector

    function Document(uri::AbstractString, text::AbstractString, workspace_file::Bool)
        return new(uri, text, Nullable{Vector{Int}}(), false, workspace_file, Parser.File(uri), Scope(uri, [], Dict(), 1), [])
    end
end

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

function get_line(doc::Document, line::Int)
    line_offsets = get_line_offsets(doc)

    if length(line_offsets)>0
        start_offset = line_offsets[line]
        if length(line_offsets)>line
            end_offset = line_offsets[line+1]-1
        else
            end_offset = endof(doc._content)
        end
        return doc._content[start_offset:end_offset]
    else
        return ""
    end
end

function get_offset(doc::Document, line::Integer, character::Integer)
    line_offsets = get_line_offsets(doc)
    current_offset = line_offsets[line]
    for i=1:character-1
        current_offset = nextind(doc._content, current_offset)
    end
    return current_offset
end

function update(doc::Document, start_line::Integer, start_character::Integer, length::Integer, new_text::AbstractString)
    text = doc._content
    start_offset = start_line==1 && start_character==1 ? 1 : get_offset(doc, start_line, start_character)
    end_offset = start_offset
    for i=1:length
        end_offset = nextind(text,end_offset)
    end

    doc._content = string(doc._content[1:start_offset-1], new_text, doc._content[end_offset:end])
    doc._line_offsets = Nullable{Vector{Int}}()
end

function get_line_offsets(doc::Document)
    if isnull(doc._line_offsets)
        line_offsets = Array(Int,0)
        text = doc._content
        is_line_start = true
        i = 1
        while i<=endof(text)
            if is_line_start
                push!(line_offsets, i)
                is_line_start = false
            end
            ch = text[i]
            is_line_start = ch == '\r' || ch == '\n'
            if ch=='\r' && i+1<=endof(text) && text[i+1]=='\n'
                i += 1
            end
            i = nextind(text, i)
        end

        if is_line_start && length(text) > 0
            push!(line_offsets, endof(text)+1)
        end

        doc._line_offsets = Nullable(line_offsets)
    end

    return get(doc._line_offsets)
end

function get_position_at(doc::Document, offset::Integer)
    line_offsets = get_line_offsets(doc)
    for (line, line_offset) in enumerate(line_offsets)
        if offset<line_offset
            return line-1,offset-line_offsets[line-1] + 1
        end
    end
    return length(line_offsets), offset - line_offsets[end] + 1
end
