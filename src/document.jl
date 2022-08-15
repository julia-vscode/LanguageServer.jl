mutable struct Document
    _path::String
    _text_document::TextDocument
    _open_in_editor::Bool
    _workspace_file::Bool
    cst::EXPR
    diagnostics::Vector{Diagnostic}
    server
    root::Document

    function Document(text_document::TextDocument, workspace_file::Bool, server=nothing)
        path = something(uri2filepath(get_uri(text_document)), "")
        path == "" || isabspath(path) || throw(LSRelativePath("Relative path `$path` is not valid."))
        cst = CSTParser.parse(get_text(text_document), true)
        doc = new(path, text_document, false, workspace_file, cst, [], server)
        set_doc(doc.cst, doc)
        setroot(doc, doc)
        return doc
    end
end

function Base.show(io::IO, ::MIME"text/plain", doc::Document)
    print(io, "Document: ", get_uri(doc))
end

function set_doc(x::EXPR, doc)
    if !StaticLint.hasmeta(x)
        x.meta = StaticLint.Meta()
    end
    x.meta.error = doc
end

function get_path(doc)
    return doc._path
end

function get_text(doc::Document)
    return get_text(doc._text_document)
end

function get_uri(doc::Document)
    return get_uri(doc._text_document)
end

function get_version(doc::Document)
    return get_version(doc._text_document)
end

function get_text_document(doc::Document)
    return doc._text_document
end

function set_text_document!(doc::Document, text_document)
    doc._text_document = text_document
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

function set_is_workspace_file(doc::Document, value::Bool)
    doc._workspace_file = value
end

get_language_id(doc::Document) = doc._text_document._language_id

get_offset(doc::Document, line::Integer, character::Integer) = get_offset(doc._text_document, line, character)
get_offset(doc::Document, p::Position) = get_offset(doc, p.line, p.character)
get_offset(doc::Document, r::Range) = get_offset(doc, r.start):get_offset(doc, r.stop)

# get_offset, but correct
get_offset3(args...) = index_at(args...) - 1

index_at(doc::Document, pos, args...) = index_at(doc._text_document, pos, args...)

get_position_from_offset(doc::Document, offset::Integer) = get_position_from_offset(doc._text_document, offset)

Range(doc::Document, rng::UnitRange) = Range(doc._text_document, rng)
