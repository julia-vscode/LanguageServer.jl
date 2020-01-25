module JSONRPCEndpoints

import JSON, UUIDs

export JSONRPCEndpoint, send_notification, send_request, send_success_response, send_error_response

mutable struct JSONRPCEndpoint
    pipe_in
    pipe_out

    out_msg_queue::Channel{Any}
    in_msg_queue::Channel{Any}

    outstanding_requests::Dict{String, Channel{Any}}

    function JSONRPCEndpoint(pipe_in, pipe_out)
        return new(pipe_in, pipe_out, Channel{Any}(Inf), Channel{Any}(Inf), Dict{String, Channel{Any}}())
    end
end

function write_transport_layer(stream, response)
    response_utf8 = transcode(UInt8, response)
    n = length(response_utf8)
    write(stream, "Content-Length: $n\r\n\r\n")
    write(stream, response_utf8)
end

function read_transport_layer(stream)
    header_dict = Dict{String,String}()
    line = chomp(readline(stream))
    # Check whether the socket was closed
    if line == ""        
        return nothing
    end
    while length(line) > 0
        h_parts = split(line, ":")
        header_dict[chomp(h_parts[1])] = chomp(h_parts[2])
        line = chomp(readline(stream))
    end
    message_length = parse(Int, header_dict["Content-Length"])
    message_str = String(read(stream, message_length))
    return message_str
end

function Base.run(x::JSONRPCEndpoint)
    @async try
        for msg in x.out_msg_queue
            write_transport_layer(x.pipe_out, msg)
        end
    catch err
        Base.display_error(stderr, err, catch_backtrace())
    end

    @async try
        while true
            message = read_transport_layer(x.pipe_in)

            if message===nothing
                break
            end

            message_dict = JSON.parse(message)

            if haskey(message_dict, "method")
                put!(x.in_msg_queue, message_dict)
            else
                # This must be a response
                id_of_request = message_dict["id"]

                channel_for_response = x.outstanding_requests[id_of_request]
                put!(channel_for_response, message_dict)
            end
        end
    catch err
        Base.display_error(stderr, err, catch_backtrace())
    end
end

function send_notification(x::JSONRPCEndpoint, method::AbstractString, params)
    message = Dict("jsonrpc"=>"2.0", "method"=>method, params=>params)

    message_json = JSON.json(message)

    put!(x.out_msg_queue, message_json)
end

function send_request(x::JSONRPCEndpoint, method::AbstractString, params)
    id = string(UUIDs.uuid4())
    message = Dict("jsonrpc"=>"2.0", "method"=>method, "params"=>params, "id"=>id)

    response_channel = Channel{Any}(1)
    x.outstanding_requests[id] = response_channel

    message_json = JSON.json(message)

    put!(x.out_msg_queue, message_json)

    response = take!(response_channel)

    if haskey(response, "result")
        return response["result"]
    else
        @info "We recieved an error response: $response"
        # error("Throw a better error here.")
    end
end

function get_next_message(endpoint::JSONRPCEndpoint)
    msg = take!(endpoint.in_msg_queue)

    return msg
end

function send_success_response(endpoint, original_request, result)
    response = Dict("jsonrpc"=>"2.0", "id"=>original_request["id"], "result"=>result)

    response_json = JSON.json(response)

    put!(endpoint.out_msg_queue, response_json)
end

function send_error_response(endpoint, origina_request, code, message, data)
    response = Dict("jsonrpc"=>"2.0", "id"=>original_request["id"], "error"=>Dict("code"=>code, "message"=>message, "data"=>data))

    response_json = JSON.json(response)

    put!(endpoint.out_msg_queue, response_json)
end

end
