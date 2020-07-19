"""
    runserver(pipe_in=stdin, pipe_out=stdout[, env_path])

Run a `LanguageServerInstance` reading from `pipe_in` and writing to `pipe_out`.

The same options can be passed to `runserver` as to
[`LanguageServerInstance`](@ref). If `env_path` is not specified,
attempt to pick an environment by considering in order of priority:

1. [`ARGS`[1]](@ref): the first command-line argument passed to the
   invocation of `julia`.
2. The Julia project containing [`pwd()`](@ref).
3. The default Julia environment withing `.julia/environments/v#.#`.

# Examples

The following invocation of Julia would set `env_path` to
`/home/example/repos/Example.jl`:

```sh
julia --project=/path/to/LanguageServer.jl \\
  -e "using LanguageServer, SymbolServer; runserver()" \\
  /home/example/repos/Example.jl
```

!!! note
    Due to [a current
    bug](https://github.com/julia-vscode/LanguageServer.jl/issues/750),
    `SymbolServer` must be imported into `Main`.

If there was a `Project.toml` or `JuliaProject.toml` in
`/home/example/repos/Example.jl/`, the following invocation would set
`env_path` to `/home/example/repos/Example.jl/`; otherwise it would be
set to `.julia/environments/v#.#` where `v#.#` is the major/minor
version of Julia being invoked.

```sh
julia --project=/path/to/LanguageServer.jl \\
  -e "using LanguageServer, SymbolServer; runserver()"
```
"""
function runserver(pipe_in = stdin, pipe_out = stdout, env_path = choose_env(),
                   depot_path = "", err_handler = nothing, symserver_store_path = nothing)
    server = LanguageServerInstance(pipe_in, pipe_out, env_path, depot_path,
                                    err_handler, symserver_store_path)
    run(server)
end

choose_env() = something(get(ARGS, 1, nothing),         # 1. path passed explicitly
                         Base.current_project(pwd()),   # 2. parent project of pwd()
                         Base.load_path_expand("@v#.#")) # 3. default "global" env
