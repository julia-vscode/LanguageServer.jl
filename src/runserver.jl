"""
    runserver(pipe_in=stdin, pipe_out=stdout[, env_path])

Run a `LanguageServerInstance` reading from `pipe_in` and writing to `pipe_out`.

The same options can be passed to `runserver` as to
[`LanguageServerInstance`](@ref). If `env_path` is not specified,
attempt to pick an environment by considering in order of priority:

1. `ARGS[1]`: the first command-line argument passed to the
   invocation of `julia`.
2. The Julia project containing `pwd()`.
3. The default Julia environment withing `.julia/environments/v#.#`.

# Examples

The following invocation of Julia would set `env_path` to
`/home/example/repos/Example.jl`:

```sh
julia --project=/path/to/LanguageServer.jl \\
  -e "using LanguageServer; runserver()" \\
  /home/example/repos/Example.jl
```

If there was a `Project.toml` or `JuliaProject.toml` in
`/home/example/repos/Example.jl/`, the following invocation would set
`env_path` to `/home/example/repos/Example.jl/`; otherwise it would be
set to `.julia/environments/v#.#` where `v#.#` is the major/minor
version of Julia being invoked.

```sh
julia --project=/path/to/LanguageServer.jl \\
  -e "using LanguageServer; runserver()"
```
"""
function runserver(@nospecialize(pipe_in)=stdin, pipe_out=stdout, env_path=choose_env(),
                   err_handler=nothing, symserver_store_path=nothing)
    server = LanguageServerInstance(pipe_in, pipe_out, env_path,
                                    err_handler, symserver_store_path)
    run(server)
end

function choose_env()
    maybe_dirname = x -> x !== nothing ? dirname(x) : nothing
    return something(
        # 1. Path passed explicitly
        get(ARGS, 1, nothing),
        # 2. Path from ENV
        Base.load_path_expand((p = get(ENV, "JULIA_PROJECT", ""); isempty(p) ? nothing : p)),
        # 3. Search the directory tree up from pwd
        maybe_dirname(Base.current_project(pwd())),
        # 4. Default global env
        maybe_dirname(Base.load_path_expand("@v#.#"))
    )
end
