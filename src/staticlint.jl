import StaticLint: hasfile, canloadfile, loadfile, setfile, getfile, getsymbolserver, getsymbolextendeds
import StaticLint: getpath, getroot, setroot, getcst, setcst, scopepass, getserver, setserver
hasfile(server::LanguageServerInstance, path::String) = !isempty(path) && hasdocument(server, URI2(filepath2uri(path)))
function canloadfile(server::LanguageServerInstance, path::String)
    try
        return !isempty(path) && isfile(path)
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return false
    end
end
function loadfile(server::LanguageServerInstance, path::String)
    source = try
        s = read(path, String)
        isvalid(s) || return
        s
    catch err
        isa(err, Base.IOError) || isa(err, Base.SystemError) || rethrow()
        return
    end
    uri = filepath2uri(path)
    doc = Document(uri, source, true, server)
    StaticLint.setfile(server, path, doc)
end
function setfile(server::LanguageServerInstance, path::String, x::Document)
    uri = URI2(filepath2uri(path))
    if hasdocument(server, uri)
        error("StaticLint should not try to set documents that are already tracked.")
    end

    setdocument!(server, uri, x)
end
getfile(server::LanguageServerInstance, path::String) = getdocument(server, URI2(filepath2uri(path)))
getsymbolserver(server::LanguageServerInstance) = server.symbol_store
getsymbolextendeds(server::LanguageServerInstance) = server.symbol_extends

getpath(d::Document) = d.path
function setpath(d::Document, path::String)
    d.path = path
    return d
end

getroot(d::Document) = d.root
function setroot(d::Document, root::Document)
    d.root = root
    return d
end

getcst(d::Document) = d.cst
function setcst(d::Document, cst::EXPR)
    d.cst = cst
    return d
end

getserver(file::Document) = file.server
function setserver(file::Document, server::LanguageServerInstance)
    file.server = server
    return file
end

function lint!(doc, server)
    StaticLint.check_all(getcst(doc), server.lint_options, server)
    empty!(doc.diagnostics)
    mark_errors(doc, doc.diagnostics)
    publish_diagnostics(doc, server)
end
