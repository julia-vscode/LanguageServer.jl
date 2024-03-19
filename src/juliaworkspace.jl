struct JuliaPackage
    project_file_uri::URI
    name::String
    uuid::UUID
end

struct JuliaDevedPackage
    name::String
    uuid::UUID
end

struct JuliaProject
    project_file_uri::URI
    deved_packages::Dict{URI,JuliaDevedPackage}
end

struct JuliaWorkspace
    _workspace_folders::Set{URI}

    # Text content
    _text_documents::Dict{URI,TextDocument}

    # Parsed syntax trees
    # TODO Replace this with a concrete syntax tree for TOML
    _toml_syntax_trees::Dict{URI,Dict}

    # Semantic information
    _packages::Dict{URI,JuliaPackage} # For now we just record all the packages, later we would want to extract the semantic content
    _projects::Dict{URI,JuliaProject} # For now we just record all the projects, later we would want to extract the semantic content
end

JuliaWorkspace() = JuliaWorkspace(Set{URI}(), Dict{URI,TextDocument}(), Dict{URI,Dict}(), Dict{URI,JuliaPackage}(), Dict{URI,JuliaProject}())

function JuliaWorkspace(workspace_folders::Set{URI})
    text_documents = isempty(workspace_folders) ? Dict{URI,TextDocument}() : merge((read_path_into_textdocuments(path) for path in workspace_folders)...)

    toml_syntax_trees = Dict{URI,Dict}()
    for (k, v) in pairs(text_documents)
        if endswith(lowercase(string(k)), ".toml")
            try
                toml_syntax_trees[k] = parse_toml_file(get_text(v))
            catch err
                # TODO Add some diagnostics
            end
        end
    end

    new_jw = JuliaWorkspace(workspace_folders, text_documents, toml_syntax_trees, semantic_pass_toml_files(toml_syntax_trees)...)
    return new_jw
end

function parse_toml_file(content)
    return Pkg.TOML.parse(content)
end

function is_path_project_file(path)
    basename_lower_case = basename(lowercase(path))

    return basename_lower_case == "project.toml" || basename_lower_case == "juliaproject.toml"
end

function is_path_manifest_file(path)
    basename_lower_case = basename(lowercase(path))

    return basename_lower_case == "manifest.toml" || basename_lower_case == "juliamanifest.toml"
end

function read_textdocument_from_uri(uri::URI)
    path = uri2filepath(uri)

    content = try
        s = read(path, String)
        our_isvalid(s) || return nothing
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
    new_roots = push!(copy(jw._workspace_folders), folder)
    new_toml_syntax_trees = copy(jw._toml_syntax_trees)

    additional_documents = read_path_into_textdocuments(folder)
    for (k, v) in pairs(additional_documents)
        if endswith(lowercase(string(k)), ".toml")
            try
                new_toml_syntax_trees[k] = parse_toml_file(get_text(v))
            catch err
                # TODO Add some diagnostics
            end
        end
    end

    new_text_documents = merge(jw._text_documents, additional_documents)

    new_jw = JuliaWorkspace(new_roots, new_text_documents, new_toml_syntax_trees, semantic_pass_toml_files(new_toml_syntax_trees)...)
    return new_jw
end

function remove_workspace_folder(jw::JuliaWorkspace, folder::URI)
    new_roots = delete!(copy(jw._workspace_folders), folder)

    new_text_documents = filter(jw._text_documents) do i
        # TODO Eventually use FilePathsBase functionality to properly test this
        return any(startswith(string(i.first), string(j)) for j in new_roots)
    end

    new_toml_syntax_trees = filter(jw._toml_syntax_trees) do i
        return haskey(new_text_documents, i.first)
    end

    new_jw = JuliaWorkspace(new_roots, new_text_documents, new_toml_syntax_trees, semantic_pass_toml_files(new_toml_syntax_trees)...)
    return new_jw
end

function add_file(jw::JuliaWorkspace, uri::URI)
    new_doc = read_textdocument_from_uri(uri)

    new_jw = jw

    if new_doc !== nothing
        new_text_documents = copy(jw._text_documents)
        new_text_documents[uri] = new_doc

        new_toml_syntax_trees = jw._toml_syntax_trees
        try
            new_toml_syntax_tree = parse_toml_file(get_text(new_doc))

            new_toml_syntax_trees = copy(jw._toml_syntax_trees)

            new_toml_syntax_trees[uri] = new_toml_syntax_tree
        catch err
            nothing
        end

        new_jw = JuliaWorkspace(jw._workspace_folders, new_text_documents, new_toml_syntax_trees, semantic_pass_toml_files(new_toml_syntax_trees)...)
    end

    return new_jw
end

function update_file(jw::JuliaWorkspace, uri::URI)
    new_doc = read_textdocument_from_uri(uri)

    new_jw = jw

    if new_doc !== nothing
        new_text_documents = copy(jw._text_documents)
        new_text_documents[uri] = new_doc

        new_toml_syntax_trees = jw._toml_syntax_trees
        try
            new_toml_syntax_tree = parse_toml_file(get_text(new_doc))

            new_toml_syntax_trees = copy(jw._toml_syntax_trees)

            new_toml_syntax_trees[uri] = new_toml_syntax_tree
        catch err
            delete!(new_toml_syntax_trees, uri)
        end

        new_jw = JuliaWorkspace(jw._workspace_folders, new_text_documents, new_toml_syntax_trees, semantic_pass_toml_files(new_toml_syntax_trees)...)
    end

    return new_jw
end

function delete_file(jw::JuliaWorkspace, uri::URI)
    new_text_documents = copy(jw._text_documents)
    delete!(new_text_documents, uri)

    new_toml_syntax_trees = jw._toml_syntax_trees
    if haskey(jw._toml_syntax_trees, uri)
        new_toml_syntax_trees = copy(jw._toml_syntax_trees)
        delete!(new_toml_syntax_trees, uri)
    end

    new_jw = JuliaWorkspace(jw._workspace_folders, new_text_documents, new_toml_syntax_trees, semantic_pass_toml_files(new_toml_syntax_trees)...)

    return new_jw
end

function semantic_pass_toml_files(toml_syntax_trees)
    # Extract all packages & paths with a manifest
    packages = Dict{URI,JuliaPackage}()
    paths_with_manifest = Dict{String,Dict}()
    for (k, v) in pairs(toml_syntax_trees)
        # TODO Maybe also check the filename here and only do the package detection for Project.toml and JuliaProject.toml
        if haskey(v, "name") && haskey(v, "uuid") && haskey(v, "version")
            parsed_uuid = tryparse(UUID, v["uuid"])
            if parsed_uuid !== nothing
                folder_uri = k |> uri2filepath |> dirname |> filepath2uri
                packages[folder_uri] = JuliaPackage(k, v["name"], parsed_uuid)
            end
        end

        path = uri2filepath(k)
        dname = dirname(path)
        filename = basename(path)
        filename_lc = lowercase(filename)
        if filename_lc == "manifest.toml" || filename_lc == "juliamanifest.toml"
            paths_with_manifest[dname] = v
        end
    end

    # Extract all projects
    projects = Dict{URI,JuliaProject}()
    for (k, _) in pairs(toml_syntax_trees)
        path = uri2filepath(k)
        dname = dirname(path)
        filename = basename(path)
        filename_lc = lowercase(filename)

        if (filename_lc == "project.toml" || filename_lc == "juliaproject.toml") && haskey(paths_with_manifest, dname)
            manifest_content = paths_with_manifest[dname]
            manifest_content isa Dict || continue
            deved_packages = Dict{URI,JuliaDevedPackage}()
            manifest_version = get(manifest_content, "manifest_format", "1.0")

            manifest_deps = if manifest_version == "1.0"
                manifest_content
            elseif manifest_version == "2.0" && haskey(manifest_content, "deps") && manifest_content["deps"] isa Dict
                manifest_content["deps"]
            else
                continue
            end

            for (k_entry, v_entry) in pairs(manifest_deps)
                v_entry isa Vector || continue
                length(v_entry) == 1 || continue
                v_entry[1] isa Dict || continue
                haskey(v_entry[1], "path") || continue
                haskey(v_entry[1], "uuid") || continue
                uuid_of_deved_package = tryparse(UUID, v_entry[1]["uuid"])
                uuid_of_deved_package !== nothing || continue

                path_of_deved_package = v_entry[1]["path"]
                if !isabspath(path_of_deved_package)
                    path_of_deved_package = normpath(joinpath(dname, path_of_deved_package))
                    if endswith(path_of_deved_package, '\\') || endswith(path_of_deved_package, '/')
                        path_of_deved_package = path_of_deved_package[1:end-1]
                    end
                end

                uri_of_deved_package = filepath2uri(path_of_deved_package)

                deved_packages[uri_of_deved_package] = JuliaDevedPackage(k_entry, uuid_of_deved_package)
            end

            folder_uri = k |> uri2filepath |> dirname |> filepath2uri
            projects[folder_uri] = JuliaProject(k, deved_packages)
        end
    end

    return packages, projects
end
