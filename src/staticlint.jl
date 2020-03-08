import StaticLint: hasfile, canloadfile, loadfile, setfile, getfile, getsymbolserver
import StaticLint: getpath, setpath, getroot, setroot, getcst, setcst, scopepass, getserver, setserver
hasfile(server::LanguageServerInstance, path::String) = hasdocument(server, URI2(filepath2uri(path)))
function canloadfile(server::LanguageServerInstance, path::String)
    try
        return isfile(path)
    catch err
        isa(err, Base.IOError) || rethrow()
        return false
    end
end
function loadfile(server::LanguageServerInstance, path::String)
    source = try
        s = read(path, String)
        # We throw an error in the case of an invalid
        # UTF-8 sequence so that the same code path
        # is used that handles file IO problems
        isvalid(s) || error()
        s
    catch err
        isa(err, Base.IOError) || rethrow()
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