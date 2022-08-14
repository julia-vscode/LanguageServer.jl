import StaticLint: hasfile, canloadfile, loadfile, setfile, getfile, getsymbols, getsymbolextendeds, getenv
import StaticLint: getpath, getroot, setroot, getcst, setcst, semantic_pass, getserver, setserver
hasfile(server::LanguageServerInstance, path::String) = !isempty(path) && hasdocument(server, filepath2uri(path))
function canloadfile(server::LanguageServerInstance, path::String)
    try
        return !isempty(path) && safe_isfile(path)
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
    doc = Document(TextDocument(uri, source, 0), true, server)
    StaticLint.setfile(server, path, doc)
end
function setfile(server::LanguageServerInstance, path::String, x::Document)
    uri = filepath2uri(path)
    if hasdocument(server, uri)
        error("StaticLint should not try to set documents that are already tracked.")
    end

    setdocument!(server, uri, x)
end
getfile(server::LanguageServerInstance, path::String) = getdocument(server, filepath2uri(path))

function getenv(doc::Document, server::LanguageServerInstance)
    get(server.roots_env_map, doc.root, server.global_env)
end
getenv(doc::Document) = getenv(doc, doc.server)
getenv(server::LanguageServerInstance) = server.global_env

getpath(d::Document) = d._path

getroot(d::Document) = d.root
function setroot(doc::Document, root::Document)
    if isdefined(doc, :root) && doc == doc.root && root !== doc
        # doc is being unset as a root - remove ExternalEnv if there is one
        if doc.server isa LanguageServerInstance && haskey(doc.server.roots_env_map, doc)
            delete!(doc.server.roots_env_map, doc)
        end
    end
    doc.root = root
    if doc == root && doc.server isa LanguageServerInstance
        # doc is being set as it's own root, lets find
        extenv = get_env_for_root(doc, doc.server)
        if extenv !== nothing
            doc.server.roots_env_map[doc] = extenv
        end
    end
    return doc
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
    StaticLint.check_all(getcst(doc), server.lint_options, getenv(doc, server))
    empty!(doc.diagnostics)
    mark_errors(doc, doc.diagnostics)
    # TODO Ideally we would not want to acces jr_endpoint here
    publish_diagnostics(doc, server, server.jr_endpoint)

    find_testitems!(doc, server, server.jr_endpoint)
end
