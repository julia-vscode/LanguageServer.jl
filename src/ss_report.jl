function julia_symbolServerReport_request(params, server::LanguageServerInstance, conn)
    # params could specify which env if we allow multiple envs
    report = symbolserver_status(server.env_path, server.symbol_store)
    for t in report
        if !t.loaded
            @info "$(t.name) doesn't have a cached."
            # What info do we want to show?         
        end
    end
    [] # How would we want to display this in the client?
end

function symbolserver_status(env, symbols)
    isdefined(SymbolServer.Pkg.Types, :Manifest) || return # julia 1.0.- doesn't have this.
    manifest_file = Base.project_file_manifest_path(env)
    project_file = Base.env_project_file(env)
    !isfile(manifest_file) && return
    !isfile(project_file) && return
    manifest = SymbolServer.Pkg.Types.Manifest(Base.parsed_toml(manifest_file))
    project = SymbolServer.Pkg.Types.Project(Base.parsed_toml(project_file))
    out = Dict()
    for (uuid, pe) in manifest
        loaded = haskey(symbols, Symbol(pe.name)) && !isempty(symbols[Symbol(pe.name)].vals)
        deved = pe.path !== nothing
        project_dep = pe.name in keys(project.deps)
        parents = get_parent(pe.name, manifest)
        project_parents = get_project_dep_parent(pe.name, manifest, project)
        out[pe.name] = (name = pe.name, uuid = string(uuid), loaded = loaded, deved = deved, project_dep = project_dep, parents = parents, project_parents = project_parents)
    end
    out
end

function get_parent(name, manifest)
    parents = []
    for (u,pe) in manifest
        if haskey(pe.deps, name)
            push!(parents, u => pe.name)
        end
    end
    parents
end

function get_project_dep_parent(name, manifest, project, parents = [])
    name in parents && return parents
    name in keys(project.deps) && push!(parents, name)
    for (u,pe) in manifest
        if haskey(pe.deps, name)
            get_project_dep_parent(pe.name, manifest, project, parents)
        end
    end
    parents
end