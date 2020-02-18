import StaticLint

StaticLint.hasfile(server::LanguageServerInstance, path::String) = hasdocument(server, URI2(filepath2uri(path)))

StaticLint.getfile(server::LanguageServerInstance, path::String) = getdocument(server, URI2(filepath2uri(path)))

StaticLint.getsymbolserver(server::LanguageServerInstance) = server.symbol_store

StaticLint.getpath(d::Document) = d.path

StaticLint.getroot(d::Document) = d.root

function StaticLint.setroot(d::Document, root::Document)
    d.root = root
    return d
end

StaticLint.getcst(d::Document) = d.cst

StaticLint.getserver(file::Document) = file.server