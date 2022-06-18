struct JuliaWorkspace
    _workspace_folders::Set{URI}
    _text_documents::Dict{URI,TextDocument}
end

JuliaWorkspace() = JuliaWorkspace(Set{URI}(), Dict{URI,TextDocument}())

function JuliaWorkspace(workspace_folders::Set{URI})
    text_documents = merge((read_path_into_textdocuments(path) for path in workspace_folders)...)

    return JuliaWorkspace(workspace_folders, text_documents)
end

function is_path_project_file(path)
    basename_lower_case = basename(lowercase(path))

    return basename_lower_case=="project.toml" || basename_lower_case=="juliaproject.toml"
end

function is_path_manifest_file(path)
    basename_lower_case = basename(lowercase(path))

    return basename_lower_case=="manifest.toml" || basename_lower_case=="juliamanifest.toml"
end

function read_textdocument_from_uri(uri::URI)
    path = uri2filepath(uri)

    content = try
        s = read(path, String)
        isvalid(s) || return nothing
        s
    catch err
        is_walkdir_error(err) || rethrow()
        return nothing
    end
    return TextDocument(uri, content, 0)
end

function read_path_into_textdocuments(uri::URI)
    path = uri2filepath(uri)
    result = Dict{URI,TextDocument}()

    if load_rootpath(path)
        try
            for (root, _, files) in walkdir(path, onerror=x -> x)
                for file in files
                    filepath = joinpath(root, file)
                    if is_path_project_file(filepath) || is_path_manifest_file(filepath)
                        uri = filepath2uri(filepath)
                        doc = read_textdocument_from_uri(uri)
                        doc === nothing && continue
                        result[uri] = doc
                    end
                end
            end
        catch err
            is_walkdir_error(err) || rethrow()
        end
    end

    return result
end

function add_workspace_folder(jw::JuliaWorkspace, folder::URI)
    new_roots = push(copy(jw._workspace_folders), folder)

    new_text_documents = merge(jw._text_documents, read_path_into_textdocuments(folder))

    return JuliaWorkspace(new_roots, new_text_documents)
end

function remove_workspace_folder(jw::JuliaWorkspace, folder::URI)
    new_roots = delete!(copy(jw._workspace_folders), folder)

    new_text_documents = filter(jw._text_documents) do i
        # TODO Eventually use FilePathsBase functionality to properly test this
        return any(startswith(i.first, j) for j in new_roots )
    end

    return JuliaWorkspace(new_roots, new_text_documents)
end

function add_file(jw::JuliaWorkspace, uri::URI)
    new_doc = read_textdocument_from_uri(uri)

    if new_doc!==nothing
        new_text_documents = copy(jw._text_documents)
        new_text_documents[uri] = new_doc

        return JuliaWorkspace(jw._workspace_folders, new_text_documents)
    else
        return jw
    end
end

function update_file(jw::JuliaWorkspace, uri::URI)
    new_doc = read_textdocument_from_uri(uri)

    if new_doc!==nothing
        new_text_documents = copy(jw._text_documents)
        new_text_documents[uri] = new_doc

        return JuliaWorkspace(jw._workspace_folders, new_text_documents)
    else
        return jw
    end
end

function delete_file(jw::JuliaWorkspace, uri::URI)
    new_text_documents = copy(jw._text_documents)
    delete!(new_text_documents, uri)

    return JuliaWorkspace(jw._workspace_folders, new_text_documents)
end
