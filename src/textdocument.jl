# =====================
# Position conversion functions operating on JuliaWorkspaces.SourceText
# =====================

"""
    index_at(st::JuliaWorkspaces.SourceText, p::Position, forgiving_mode=false)

Converts a 0-based `Position` that is UTF-16 encoded to a 1-based UTF-8
encoded Julia string index.
"""
function index_at(st::JuliaWorkspaces.SourceText, line::Integer, character::Integer, forgiving_mode=false)
    line_indices = st.line_indices
    text = st.content

    if line >= length(line_indices)
        forgiving_mode || throw(LSOffsetError("index_at crashed. More diagnostics:\nline=$line\nline_indices='$line_indices'"))

        return nextind(text, lastindex(text))
    elseif line < 0
        throw(LSOffsetError("index_at crashed. More diagnostics:\nline=$line\nline_indices='$line_indices'"))
    end

    line_index = line_indices[line + 1]

    next_line_index = line + 1 < length(line_indices) ? line_indices[line + 2] : nextind(text, lastindex(text))

    pos = line_index

    while character > 0
        if pos >= next_line_index
            pos = next_line_index
            break
        end

        if UInt32(text[pos]) >= 0x010000
            character -= 2
        else
            character -= 1
        end

        pos = nextind(text, pos)
    end

    if character < 0
        error("Invalid UTF-16 index supplied")
    end

    return pos
end

index_at(st::JuliaWorkspaces.SourceText, p::Position, args...) = index_at(st, p.line, p.character, args...)

"""
    apply_text_edits(st::JuliaWorkspaces.SourceText, edits)

Apply LSP text edits to a SourceText and return the new content as a String.
"""
function apply_text_edits(st::JuliaWorkspaces.SourceText, edits)
    content = st.content

    for edit in edits
        if ismissing(edit.range) && ismissing(edit.rangeLength)
            # No range given, replace all text
            content = edit.text
        else
            # Create a new SourceText for each intermediate edit so that
            # position conversion is correct for subsequent edits
            st = JuliaWorkspaces.SourceText(content, st.language_id)
            editrange = _convert_lsrange_to_jlrange(st, edit.range)
            content = string(content[1:prevind(content, editrange.start)], edit.text, content[nextind(content, editrange.stop):lastindex(content)])
        end
    end

    return content
end

# =====================
# Internal functions
# =====================

function _convert_lsrange_to_jlrange(st::JuliaWorkspaces.SourceText, range::Range)
    start_index_ls = index_at(st, range.start)
    stop_index = index_at(st, range.stop)

    content = st.content

    # we use prevind for the stop value here because Julia stop values in
    # a range are inclusive, while the stop value is exclusive in a LS
    # range
    return start_index_ls:prevind(content, stop_index)
end

"""
    get_offset(st, line, char)

Returns the 0 based byte offset position corresponding to a line/character position.
This takes 0 based line/char inputs. Corresponding functions are available for
Position and Range arguments, the latter returning a UnitRange{Int}.
"""
function get_offset(st::JuliaWorkspaces.SourceText, line::Integer, character::Integer)
    return index_at(st, line, character) - 1
end
get_offset(st::JuliaWorkspaces.SourceText, p::Position) = get_offset(st, p.line, p.character)
get_offset(st::JuliaWorkspaces.SourceText, r::Range) = get_offset(st, r.start):get_offset(st, r.stop)

"""
    get_position_from_offset(st, offset)

Returns the 0-based line and character position within a document of a given
byte offset. Handles UTF-16 encoding for LSP compliance.
"""
function get_position_from_offset(st::JuliaWorkspaces.SourceText, offset::Integer)
    text = st.content
    line_indices = st.line_indices
    offset > sizeof(text) && throw(LSPositionToOffsetException("offset[$offset] > sizeof(content)[$(sizeof(text))]"))

    # Find which line contains the offset (line_indices are 1-based byte positions)
    # Convert offset (0-based) to 1-based index for comparison
    idx = offset + 1
    line = 1
    for i in 2:length(line_indices)
        if line_indices[i] > idx
            break
        end
        line = i
    end

    # Count UTF-16 characters from line start to offset
    io = IOBuffer(text)
    seek(io, line_indices[line] - 1) # seek is 0-based
    character = 0
    while position(io) < offset
        c = read(io, Char)
        character += 1
        if UInt32(c) >= 0x010000
            character += 1
        end
    end
    close(io)
    return line - 1, character
end

"""
    Range(st::JuliaWorkspaces.SourceText, rng::UnitRange)

Converts a byte offset range to a LSP Range with proper UTF-16 character encoding.
"""
function Range(st::JuliaWorkspaces.SourceText, rng::UnitRange)
    start_l, start_c = get_position_from_offset(st, first(rng))
    end_l, end_c = get_position_from_offset(st, last(rng))
    return Range(start_l, start_c, end_l, end_c)
end
