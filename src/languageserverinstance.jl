T = 0.0

mutable struct LanguageServerInstance
    pipe_in
    pipe_out

    workspaceFolders::Set{String}
    documents::Dict{URI2,Document}

    debug_mode::Bool
    runlinter::Bool
    ignorelist::Set{String}
    isrunning::Bool

    packages::Dict
    env_path::String
    depot_path::String
    symbol_server::Union{Nothing,SymbolServer.SymbolServerProcess}

    function LanguageServerInstance(pipe_in, pipe_out, debug_mode::Bool, env_path, depot_path, packages)
        new(pipe_in, pipe_out, Set{String}(), Dict{URI2,Document}(),  debug_mode, false, Set{String}(), false, packages, env_path, depot_path, nothing)
    end
end

function send(message, server)
    message_json = JSON.json(message)

    write_transport_layer(server.pipe_out, message_json, server.debug_mode)
end

function Base.run(server::LanguageServerInstance)
    server. symbol_server = SymbolServer.SymbolServerProcess(depot = server.depot_path)
    @info "Started symbol server"
    server.packages = SymbolServer.getstore(server.symbol_server)
    @info "StaticLint store set"
    kill(server.symbol_server)
    global T
    while true
        message = read_transport_layer(server.pipe_in, server.debug_mode)
        message_dict = JSON.parse(message)
        # For now just ignore response messages
        if haskey(message_dict, "method")
            server.debug_mode && (T = time())
            request = parse(JSONRPC.Request, message_dict)
            # server.isrunning && serverbusy(server)
            process(request, server)
            # server.isrunning && serverready(server)
        end
    end
end

function serverbusy(server)
    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "window/setStatusBusy")), server.debug_mode)
end

function serverready(server)
    write_transport_layer(server.pipe_out, JSON.json(Dict("jsonrpc" => "2.0", "method" => "window/setStatusReady")), server.debug_mode)
end

function read_transport_layer(stream, debug_mode = false)
    header = String[]
    line = chomp(readline(stream))
    while length(line) > 0
        push!(header, line)
        line = chomp(readline(stream))
    end
    header_dict = Dict{String,String}()
    for h in header
        h_parts = split(h, ":")
        header_dict[chomp(h_parts[1])] = chomp(h_parts[2])
    end
    message_length = parse(Int, header_dict["Content-Length"])

    message = read(stream, message_length)
    message_str = String(message)
    debug_mode && @info "RECEIVED: $message_str"
    debug_mode && @info ""
    return message_str    
end

function write_transport_layer(stream, response, debug_mode = false)
    global T
    response_utf8 = transcode(UInt8, response)
    n = length(response_utf8)
    write(stream, "Content-Length: $n\r\n\r\n")
    write(stream, response_utf8)
    debug_mode && @info "SENT: $response"
    debug_mode && @info string("TIME:", round(time()-T, sigdigits = 2))
end

