struct TextDocument
    _uri::URI
    _content::String
    _version::Int
    _line_offsets::Union{Nothing,Vector{Int}}
    _line_offsets2::Union{Nothing,Vector{Int}}
    

    function TextDocument(uri::URI, text::AbstractString, version::Int)
        # TODO Remove this check eventually
        occursin('\0', text) && throw(LSInvalidFile("Tried to set a text with an embedded NULL as the document content."))

        line_offsets = _compute_line_offsets(text)
        line_offsets2 = _compute_line_offsets2(text)

        return new(uri, text, version, line_offsets, line_offsets2)
    end
end
Base.display(doc::TextDocument) = println("TextDocument: $(basename(doc._uri)) ")

get_text(doc::TextDocument) = doc._content

get_uri(doc::TextDocument) = doc._uri

get_version(doc::TextDocument) = doc._version

get_line_offsets(doc::TextDocument) = doc._line_offsets

get_line_offsets2(doc::TextDocument) = doc._line_offsets2

# 1-based. Basically the index at which (line, character) can be found in the document.
get_offset2(doc::TextDocument, p::Position, forgiving_mode=false) =  get_offset2(doc, p.line, p.character, forgiving_mode)

function get_offset2(doc::TextDocument, line::Integer, character::Integer, forgiving_mode=false)
    line_offsets = get_line_offsets2(doc)
    text = get_text(doc)

    if line >= length(line_offsets)
        forgiving_mode || throw(LSOffsetError("get_offset2 crashed. More diagnostics:\nline=$line\nline_offsets='$line_offsets'"))

        return nextind(text, lastindex(text))
    elseif line < 0
        throw(LSOffsetError("get_offset2 crashed. More diagnostics:\nline=$line\nline_offsets='$line_offsets'"))
    end

    line_offset = line_offsets[line + 1]

    next_line_offset = line + 1 < length(line_offsets) ? line_offsets[line + 2] : nextind(text, lastindex(text))

    pos = line_offset

    while character > 0
        if pos >= next_line_offset
            pos = next_line_offset
            break
        end

        if UInt32(text[pos]) >= 0x010000
            character -= 2
        else
            character -= 1
        end

        pos = nextind(text, pos)
    end

    return pos
end

function apply_text_edits(doc::TextDocument, edits, new_version)
    content = doc._content

    for edit in edits
        if ismissing(edit.range) && ismissing(edit.rangeLength)
            # No range given, replace all text
            content = edit.text
        else
            editrange = _convert_lsrange_to_jlrange(doc, edit.range)
            content = string(content[1:prevind(content, editrange.start)], edit.text, content[nextind(content, editrange.stop):lastindex(content)])
        end
    end

    return TextDocument(doc._uri, content, new_version)
end

function _convert_lsrange_to_jlrange(doc::TextDocument, range::Range)
    start_offset_ls = get_offset2(doc, range.start.line, range.start.character)
    stop_offset = get_offset2(doc, range.stop.line, range.stop.character)

    content = doc._content

    # we use prevind for the stop value here because Julia stop values in
    # a range are inclusive, while the stop value is exclusive in a LS
    # range
    return start_offset_ls:prevind(content, stop_offset)
end


function _compute_line_offsets(text)
    line_offsets = Int[0]

    ind = firstindex(text)
    while ind <= lastindex(text)
        c = text[ind]
        nl = c == '\n' || c == '\r'
        if c == '\r' && ind + 1 <= lastindex(text) && text[ind + 1] == '\n'
            ind += 1
        end
        nl && push!(line_offsets, ind)
        ind = nextind(text, ind)
    end

    return line_offsets
end

function _compute_line_offsets2(text)
    line_offsets = Int[1]

    ind = firstindex(text)
    while ind <= lastindex(text)
        c = text[ind]
        if c == '\n' || c == '\r'
            if c == '\r' && ind + 1 <= lastindex(text) && text[ind + 1] == '\n'
                ind += 1
            end
            push!(line_offsets, ind + 1)
        end

        ind = nextind(text, ind)
    end
    return line_offsets
end
