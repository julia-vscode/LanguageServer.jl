function read_transport_layer(stream, debug_mode = false)
    header = String[]
    line = chomp(readline(stream))
    while length(line) > 0
        push!(header, line)
        line = chomp(readline(stream))
    end
    header_dict = Dict{String, String}()
    for h in header
        h_parts = split(h, ":")
        header_dict[chomp(h_parts[1])] = chomp(h_parts[2])
    end
    message_length = parse(Int, header_dict["Content-Length"])

    message = read(stream, message_length)
    message_str = String(message)
    debug_mode && info("RECEIVED: $message_str")
    debug_mode && info()
    return message_str    
end

function write_transport_layer(stream, response, debug_mode = false)
    response_utf8 = transcode(UInt8, response)
    n = length(response_utf8)
    write(stream, "Content-Length: $n\r\n\r\n")
    write(stream, response_utf8)
    debug_mode && info("SENT: $response")
    debug_mode && info()
end
