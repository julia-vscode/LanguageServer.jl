struct TextDocument
    _uri::URI
    _content::String
    _version::Int
    _line_offsets::Union{Nothing,Vector{Int}} # TODO Legacy, remove eventually
    _line_indices::Union{Nothing,Vector{Int}}
    _language_id::String

    function TextDocument(uri::URI, text::AbstractString, version::Int, lid = nothing)
        # TODO Remove this check eventually
        occursin('\0', text) && throw(LSInvalidFile("Tried to set a text with an embedded NULL as the document content."))

        line_offsets = _compute_line_offsets(text)
        line_indices = _compute_line_indices(text)

        if lid === nothing
            if endswith(uri.path, ".jmd")
                lid = "juliamarkdown"
            elseif endswith(uri.path, ".md")
                lid = "markdown"
            elseif endswith(uri.path, ".jl")
                lid = "julia"
            else
                lid = ""
            end
        end

        return new(uri, text, version, line_offsets, line_indices, lid)
    end
end

function Base.show(io::IO, ::MIME"text/plain", doc::TextDocument)
    print(io, "TextDocument: ", doc._uri)
end

get_text(doc::TextDocument) = doc._content

get_uri(doc::TextDocument) = doc._uri

get_version(doc::TextDocument) = doc._version

get_line_indices(doc::TextDocument) = doc._line_indices

get_language_id(doc::TextDocument) = doc._language_id

"""
    index_at(doc::TextDocument, p::Position, forgiving_mode=false)

Converts a 0-based `Position` that is UTF-16 encoded to a 1-based UTF-8
encoded Julia string index.
"""
function index_at(doc::TextDocument, line::Integer, character::Integer, forgiving_mode=false)
    line_indices = get_line_indices(doc)
    text = get_text(doc)

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

index_at(doc::TextDocument, p::Position, args...) = index_at(doc, p.line, p.character, args...)

function apply_text_edits(doc::TextDocument, edits, new_version)
    content = doc._content

    for edit in edits
        if ismissing(edit.range) && ismissing(edit.rangeLength)
            # No range given, replace all text
            content = edit.text
        else
            # Rebind doc here so that we compute the range for the updated document in
            # _convert_lsrange_to_jlrange when applying multiple edits
            doc = TextDocument(doc._uri, content, new_version, get_language_id(doc))
            editrange = _convert_lsrange_to_jlrange(doc, edit.range)
            content = string(content[1:prevind(content, editrange.start)], edit.text, content[nextind(content, editrange.stop):lastindex(content)])
        end
    end

    return TextDocument(doc._uri, content, new_version, get_language_id(doc))
end

# =====================
# Internal functions
# =====================

function _convert_lsrange_to_jlrange(doc::TextDocument, range::Range)
    start_index_ls = index_at(doc, range.start)
    stop_index = index_at(doc, range.stop)

    content = doc._content

    # we use prevind for the stop value here because Julia stop values in
    # a range are inclusive, while the stop value is exclusive in a LS
    # range
    return start_index_ls:prevind(content, stop_index)
end

function _compute_line_indices(text)
    line_indices = Int[1]

    ind = firstindex(text)
    while ind <= lastindex(text)
        c = text[ind]
        if c == '\n' || c == '\r'
            if c == '\r' && ind + 1 <= lastindex(text) && text[ind + 1] == '\n'
                ind += 1
            end
            push!(line_indices, ind + 1)
        end

        ind = nextind(text, ind)
    end
    return line_indices
end

# Note: to be removed
function _obscure_text(s)
    i = 1
    io = IOBuffer()
    while i <= sizeof(s) # AUDIT: OK, i is generated by nextind
        di = nextind(s, i) - i
        if di == 1
            if s[i] in ('\n', '\r')
                write(io, s[i])
            else
                write(io, "a")
            end
        elseif di == 2
            write(io, "α")
        elseif di == 3
            write(io, "—")
        else
            write(io, s[i])
        end
        i += di
    end
    String(take!(io))
end

function _get_line_of(doc::TextDocument, offset::Integer)
    line_offsets = doc._line_offsets
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

# ======================
# TODO The following functions are legacy offset versions that should eventually be removed
# ======================

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

"""
    get_line_offsets(doc::Document)

Updates the doc._line_offsets field, an n length Array each entry of which
gives the byte offset position of the start of each line. This always starts
with 0 for the first line (even if empty).
"""
get_line_offsets(doc::TextDocument) = doc._line_offsets

"""
    get_offset(doc, line, char)

Returns the 0 based byte offset position corresponding to a line/character position.
This takes 0 based line/char inputs. Corresponding functions are available for
Position and Range arguments, the latter returning a UnitRange{Int}.
"""
function get_offset(doc::TextDocument, line::Integer, character::Integer)
    return index_at(doc, line, character) - 1
end
get_offset(doc::TextDocument, p::Position) = get_offset(doc, p.line, p.character)
get_offset(doc::TextDocument, r::Range) = get_offset(doc, r.start):get_offset(doc, r.stop)

"""
    get_position_from_offset(doc, offset)

Returns the 0-based line and character position within a document of a given
byte offset.
"""
function get_position_from_offset(doc::TextDocument, offset::Integer)
    offset > sizeof(get_text(doc)) && throw(LSPositionToOffsetException("offset[$offset] > sizeof(content)[$(sizeof(get_text(doc)))]")) # OK, offset comes from EXPR spans
    line_offsets = get_line_offsets(doc)
    line, _ = _get_line_of(doc, offset)
    io = IOBuffer(get_text(doc))
    seek(io, line_offsets[line])
    character = 0
    while offset > position(io)
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
    Range(Doc, rng)
Converts a byte offset range to a LSP Range.
"""
function Range(doc::TextDocument, rng::UnitRange)
    start_l, start_c = get_position_from_offset(doc, first(rng))
    end_l, end_c = get_position_from_offset(doc, last(rng))
    return Range(start_l, start_c, end_l, end_c)
end

function Range(st::JuliaWorkspaces.SourceText, rng::UnitRange)
    start_l, start_c = JuliaWorkspaces.position_at(st, first(rng))
    end_l, end_c = JuliaWorkspaces.position_at(st, last(rng))

    return Range(start_l-1, start_c-1, end_l-1, end_c-1)
end
