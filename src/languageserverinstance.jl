type LanguageServerInstance
    pipe_in
    pipe_out

    rootPath::String 
    documents::Dict{String,Document}
    cache::Dict{Any,Any}
    user_modules::Channel{Symbol}

    debug_mode::Bool
    runlinter::Bool

    user_pkg_dir::String

    lint_pipe_name::String

    function LanguageServerInstance(pipe_in,pipe_out, debug_mode::Bool, user_pkg_dir::AbstractString=haskey(ENV, "JULIA_PKGDIR") ? ENV["JULIA_PKGDIR"] : joinpath(homedir(),".julia"))
        cache = Dict()

        lint_pipe_name = is_windows() ? "\\\\.\\pipe\\vscode-language-julia-lint-server-$(getpid())" : joinpath(tempname(), "vscode-language-julia-lint-server-$(getpid())")

        new(pipe_in,pipe_out,"", Dict{String,Document}(), cache, Channel{Symbol}(128), debug_mode, false, user_pkg_dir, lint_pipe_name)
    end
end

function send(message, server)
    message_json = JSON.json(message)

    write_transport_layer(server.pipe_out,message_json, server.debug_mode)
end

function Base.run(server::LanguageServerInstance)
    wontload_modules = []
    @schedule begin
        for missing_module in server.user_modules
            if !(missing_module in keys(server.cache)) && !(missing_module in wontload_modules)
                updatecache(missing_module, server)
                if !(missing_module in keys(server.cache))
                    push!(wontload_modules, missing_module)
                end
            end
        end
    end

    env_new = copy(ENV)
    env_new["JULIA_PKGDIR"] = server.user_pkg_dir

    lint_stdout,lint_stdin,lint_process = readandwrite(Cmd(`$JULIA_HOME/julia -e "Base.Sys.set_process_title(\"julia linter\"); using Lint; lintserver(\"$(replace(server.lint_pipe_name, "\\", "\\\\"))\");"`, env=env_new))

    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        request = parse(JSONRPC.Request, message)

        process(request, server)
    end
end
