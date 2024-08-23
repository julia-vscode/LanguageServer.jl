
using Pkg
@static if isdefined(Base, :parsed_toml)
    parsed_toml(args...) = Base.parsed_toml(args...)
else
    parsed_toml(file) = Pkg.TOML.parsefile(file)
end

const project_names = ("JuliaProject.toml", "Project.toml")
const manifest_names = ("JuliaManifest.toml", "Manifest.toml")

# return nothing or the project file at env
function env_file(env::String, names=project_names)::Union{Nothing,String}
    if isdir(env)
        for proj in names
            project_file = joinpath(env, proj)
            safe_isfile(project_file) && return project_file
        end
        return nothing
    elseif basename(env) in names && safe_isfile(env)
        return env
    end
    return nothing
end

function is_project_folder_in_env(folder, env_manifest, server)
    project_file = Base.env_project_file(folder)
    project_file isa Bool && return false
    folder_proj = parsed_toml(project_file)
    manifest_pe = get(env_manifest, get(folder_proj, "uuid", ""), nothing)
    if manifest_pe === nothing
        return false
    elseif manifest_pe.path !== nothing
        return Base.Filesystem.samefile(manifest_pe.path, folder)
    elseif manifest_pe.tree_hash isa Base.SHA1
        if Base.Filesystem.samefile(abspath(server.depot_path, "packages", folder_proj.name, Base.version_slug(folder_proj.uuid, manifest_pe.tree_hash, 4)), folder)
            return true
        elseif Base.Filesystem.samefile(abspath(server.depot_path, "packages", folder_proj.name, Base.version_slug(folder_proj.uuid, manifest_pe.tree_hash)), folder)
            return true
        end
    end
    return false
end

function get_env_for_root(doc::Document, server::LanguageServerInstance)
    env_proj_file = env_file(server.env_path, project_names)
    env_manifest_file = env_file(server.env_path, manifest_names)

    (safe_isfile(env_proj_file) && safe_isfile(env_manifest_file)) || return

    # Find which workspace folder the doc is in.
    parent_workspaceFolders = sort(filter(f -> startswith(doc._path, f), collect(server.workspaceFolders)), by=length, rev=true)

    isempty(parent_workspaceFolders) && return
    # arbitrarily pick one
    parent_workspaceFolder = first(parent_workspaceFolders)

    project_env = env_file(parent_workspaceFolder, project_names)
    try
        if safe_isfile(project_env)
            folder_proj = parsed_toml(project_env)

            # We point to all caches as, though a package may not be directly available (e.g as
            # a dependency) it may still be accessible as imported by one of the direct dependencies.
            symbols = server.global_env.symbols

            # Will want to limit this to only get extended methods from the dependency tree of
            # the project (e.g. using `complete_dep_tree` below)
            extended_methods = server.global_env.extended_methods

            # This is the list of packages that are directly available
            project_deps = Symbol.(collect(keys(get(folder_proj, "deps", []))))
            if isdir(joinpath(parent_workspaceFolder, "test")) && startswith(doc._path, joinpath(parent_workspaceFolder, "test"))
                # We're in the test folder, add the project iteself to the deps
                # This should actually point to the live code (e.g. the relevant EXPR or Scope)?
                haskey(folder_proj, "name") && push!(project_deps, Symbol(folder_proj["name"]))
                for extra in keys(get(folder_proj, "extras", []))
                    if Symbol(extra) in keys(symbols)
                        push!(project_deps, Symbol(extra))
                    end
                end
            end

            StaticLint.ExternalEnv(symbols, extended_methods, project_deps)
        end
    catch err
        # The specified env is faulty (incorrect format, missing entries, ...)
        # We can't do anything about that except treating it the same as a non-existing env,
        # but showing a warning might be useful.
        msg = "The Julia environment at `$project_env` is invalid. Using the global environment instead."
        if server.jr_endpoint !== nothing
            JSONRPC.send(server.jr_endpoint, window_showMessage_notification_type, ShowMessageParams(
                MessageTypes.Warning,
                msg
            ))
        end
        @error msg exception = (err, catch_backtrace())
    end
end

function complete_dep_tree(uuid, env_manifest, alldeps=Dict{Base.UUID,Pkg.Types.PackageEntry}())
    haskey(alldeps, uuid) && return alldeps
    alldeps[uuid] = env_manifest[uuid]
    for dep_uuid in values(alldeps[uuid].deps)
        complete_dep_tree(dep_uuid, env_manifest, alldeps)
    end
    alldeps
end
