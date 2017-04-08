type LanguageServerInstance
    pipe_in
    pipe_out

    rootPath::String 
    documents::Dict{String,Document}
    cache::Dict{Any,Any}
    user_modules::Channel{Symbol}

    debug_mode::Bool
    runlinter::Bool
    linter_is_installed::Bool

    user_pkg_dir::String

    lint_pipe_name::String

    out_message_buffer::Channel{String}

    diagnostic_requests::Channel{String}

    function LanguageServerInstance(pipe_in,pipe_out, debug_mode::Bool, user_pkg_dir::AbstractString=haskey(ENV, "JULIA_PKGDIR") ? ENV["JULIA_PKGDIR"] : joinpath(homedir(),".julia"))
        cache = Dict()

        lint_pipe_name = is_windows() ? "\\\\.\\pipe\\vscode-language-julia-lint-server-$(getpid())" : joinpath(tempname(), "vscode-language-julia-lint-server-$(getpid())")

        new(pipe_in,pipe_out,"", Dict{String,Document}(), cache, Channel{Symbol}(128), debug_mode, false, true, user_pkg_dir, lint_pipe_name, Channel{String}(128), Channel{String}(128))
    end
end

function send(message, server)
    message_json = JSON.json(message)

    put!(server.out_message_buffer, message_json)
end

function Base.run(server::LanguageServerInstance)
    @schedule begin
        for message in server.out_message_buffer
            write_transport_layer(server.pipe_out,message, server.debug_mode)
        end
    end

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

    lint_stdout,lint_stdin,lint_process = readandwrite(Cmd(`$JULIA_HOME/julia -e "Base.Sys.set_process_title(\"julia linter\");
        try
            eval(:(using Lint));
        catch err
            println(err)
        end

        lintserver(\"$(replace(server.lint_pipe_name, "\\", "\\\\"))\", \"lint-message\");"`, env=env_new))

    linter_is_started = Condition()

    @schedule begin
        for s in eachline(lint_stdout)
            if chomp(s)=="Server running on port/pipe $(server.lint_pipe_name) ..."
                info("Linter started")
                notify(linter_is_started)
                break
            elseif startswith(s, "ArgumentError")
                kill(lint_process)
                if server.runlinter
                    send(Message(3, "Lint.jl package not found. You need to install it with Pkg.add(\"Lint\") if you want to receive lint messages."), server)
                end
                server.linter_is_installed = false
            end
        end
    end

    @schedule begin
        wait(linter_is_started)
        for uri in server.diagnostic_requests
            document = get_text(server.documents[uri])

            input = Dict("file"=>normpath(unescape(URI(uri).path))[2:end], "code_str"=>String(document))

            conn = connect(server.lint_pipe_name)
            try
                print(conn, JSON.json(input))

                out = JSON.parse(readline(conn))

                diags = map(out) do l
                    line_number = l["line"]
                    start_col = findfirst(i->i!=' ', get_line(uri, line_number, server))
                    Diagnostic(Range(Position(line_number-1, start_col-1), Position(line_number-1, typemax(Int)) ),
                        LintSeverity[string(l["code"])[1]],
                        string(l["code"]),
                        "Lint.jl",
                        l["message"])
                end
                publishDiagnosticsParams = PublishDiagnosticsParams(uri, diags)

                response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(Nullable{Union{String,Int64}}(), publishDiagnosticsParams)
                send(response, server)
            finally
                close(conn)
            end
        end
    end

    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        request = parse(JSONRPC.Request, message)

        process(request, server)
    end
end
