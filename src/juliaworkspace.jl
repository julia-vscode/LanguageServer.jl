struct JuliaWorkspace
    _workspace_folders::Set{URI}
    _text_documents::Dict{URI,TextDocument}
end

JuliaWorkspace() = JuliaWorkspace(Set{URI}(), Dict{URI,TextDocument}())

function JuliaWorkspace(workspace_folders::Set{URI})
    text_documents = merge(read_path_into_textdocuments(path) for path in workspace_folders)

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

function read_path_into_textdocuments(path::String)
    result = Dict{URI,TextDocument}()

    if load_rootpath(path)
        try
            for (root, _, files) in walkdir(path, onerror=x -> x)
                for file in files
                    filepath = joinpath(root, file)
                    if is_path_project_file(filepath) || is_path_manifest_file(filepath)
                        uri = filepath2uri(filepath)
                        content = try
                            s = read(filepath, String)
                            isvalid(s) || continue
                            s
                        catch err
                            is_walkdir_error(err) || rethrow()
                            continue
                        end
                        doc = TextDocument(uri, content, 0)
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

function remove_workspace_folder(jw::JuliaWorkspace, folder::URI)
    new_roots = delete!(jw._workspace_folders, folder)

    text_documents = filter(jw._text_documents) do i
        return any(startswith(i.first), )
    end

    return JuliaWorkspace(new_roots, text_documents)
end
