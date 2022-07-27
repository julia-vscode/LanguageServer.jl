struct JuliaWorkspace
    _workspace_folders::Set{URI}

    # Text content
    _text_documents::Dict{URI,TextDocument}

    # Parsed syntax trees
    # TODO Replace this with a concrete syntax tree for TOML
    _toml_syntax_trees::Dict{URI,Dict}

    # Semantic information
    _packages::Set{URI} # For now we just record all the packages, later we would want to extract the semantic content
    _projects::Set{URI} # For now we just record all the projects, later we would want to extract the semantic content
end

JuliaWorkspace() = JuliaWorkspace(Set{URI}(), Dict{URI,TextDocument}(), Dict{URI,Dict}(), Set{URI}(), Set{URI}())

function JuliaWorkspace(workspace_folders::Set{URI})
    text_documents = merge((read_path_into_textdocuments(path) for path in workspace_folders)...)

    toml_syntax_trees = Dict{URI,Dict}()
    for (k,v) in pairs(text_documents)
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
    new_toml_syntax_trees = copy(jw._toml_syntax_trees)

    additional_documents = read_path_into_textdocuments(folder)
    for (k,v) in pairs(text_documents)
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
        return any(startswith(i.first, j) for j in new_roots )
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

    if new_doc!==nothing
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

        new_jw =  JuliaWorkspace(jw._workspace_folders, new_text_documents, new_toml_syntax_trees, semantic_pass_toml_files(new_toml_syntax_trees)...)
    end

    return new_jw
end

function update_file(jw::JuliaWorkspace, uri::URI)
    new_doc = read_textdocument_from_uri(uri)

    new_jw = jw

    if new_doc!==nothing
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
    packages = Set{URI}()
    paths_with_manifest = Set{String}()
    for (k,v) in pairs(toml_syntax_trees)
        if haskey(v, "name") && haskey(v, "uuid") && haskey(v, "version")
            push!(packages, k)
        end

        path = uri2filepath(k)
        dname = dirname(path)
        filename = basename(path)
        filename_lc = lowercase(filename)
        if filename_lc == "manifest.toml" || filename_lc == "juliamanifest.toml"
            push!(paths_with_manifest, dname)
        end
    end

    # Extract all projects
    projects = Set{URI}()
    for (k,_) in pairs(toml_syntax_trees)
        path = uri2filepath(k)
        dname = dirname(path)
        filename = basename(path)
        filename_lc = lowercase(filename)

        if (filename_lc=="project.toml" || filename_lc=="juliaproject.toml" ) && in(dname, paths_with_manifest)
            push!(projects, k)
        end
    end

    return packages, projects
end
