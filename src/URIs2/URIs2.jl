module URIs2

import URIs

export URI, uri2filepath, filepath2uri

struct URI
    scheme::Union{String,Nothing}
    authority::Union{String,Nothing}
    path::String
    query::Union{String,Nothing}
    fragment::Union{String,Nothing}
end

function percent_decode(str::AbstractString)
    return URIs.unescapeuri(str)
end

function URI(value::AbstractString)
    m = match(r"^(([^:/?#]+?):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?", value)

    m===nothing && error("Invalid argument.")

    return URI(
        m.captures[2],
        m.captures[4]===nothing ? nothing : percent_decode(m.captures[4]),
        m.captures[5]===nothing ? nothing : percent_decode(m.captures[5]),
        m.captures[7]===nothing ? nothing : percent_decode(m.captures[7]),
        m.captures[9]===nothing ? nothing : percent_decode(m.captures[9])
    )
end

function URI(;
    scheme::Union{AbstractString,Nothing}=nothing,
    authority::Union{AbstractString,Nothing}=nothing,
    path::Union{AbstractString,Nothing}=nothing,
    query::Union{AbstractString,Nothing}=nothing,
    fragment::Union{AbstractString,Nothing}=nothing
    )
    return URI(scheme, authority, path, query, fragment)
end

@inline function is_rfc3986_unreserved(c::Char)
    return 'A' <= c <= 'Z' ||
        'a' <= c <= 'z' ||
        '0' <= c <= '9' ||
        c == '-' ||
        c == '.' ||
        c == '_' ||
        c == '~'
end

@inline function is_rfc3986_sub_delim(c::Char)
    return c == '!' ||
        c == '$' ||
        c == '&' ||
        c == '\'' ||
        c == '(' ||
        c == ')' ||
        c == '*' ||
        c == '+' ||
        c == ',' ||
        c == ';' ||
        c == '='
end

@inline function is_rfc3986_pchar(c::Char)
    return is_rfc3986_unreserved(c) ||
        is_rfc3986_sub_delim(c) ||
        c == ':' ||
        c == '@'
end

@inline function is_rfc3986_query(c::Char)
    return is_rfc3986_pchar(c) || c=='/' || c=='?'
end

@inline function is_rfc3986_fragment(c::Char)
    return is_rfc3986_pchar(c) || c=='/' || c=='?'
end

@inline function is_rfc3986_userinfo(c::Char)
    return is_rfc3986_unreserved(c) ||
        is_rfc3986_sub_delim(c) ||
        c == ':'
end

@inline function is_rfc3986_reg_name(c::Char)
    return is_rfc3986_unreserved(c) ||
        is_rfc3986_sub_delim(c)
end

function encode(io::IO, s::AbstractString, issafe::Function)
    for c in s
        if issafe(c)
            print(io, c)
        else
            print(io, '%')
            print(io, uppercase(string(Int(c), base=16, pad=2)))
        end
    end
end

@inline function is_ipv4address(s::AbstractString)
    if length(s)==1
        return '0' <= s[1] <= '9'
    elseif length(s)==2
        return '1' <= s[1] <= '9' && '0' <= s[2] <= '9'
    elseif length(s)==3
        return (s[1]=='1' && '0' <= s[2] <= '9' && '0' <= s[3] <= '9') ||
            (s[1]=='2' && '0' <= s[2] <= '4' && '0' <= s[3] <= '9') ||
            (s[1]=='2' && s[2] == '5' && '0' <= s[3] <= '5')
    else
        return false
    end
end

@inline function is_ipliteral(s::AbstractString)
    # TODO Implement this
    return false
end

function encode_host(io::IO, s::AbstractString)
    if is_ipv4address(s) || is_ipliteral(s)
        print(io, s)
    else
        # The host must be a reg-name
        encode(io, s, is_rfc3986_reg_name)
    end
end

function encode_path(io::IO, s::AbstractString)
    # TODO Write our own version
    print(io, URIs.escapepath(s))
end

function Base.print(io::IO, uri::URI)
    scheme = uri.scheme
    authority = uri.authority
    path = uri.path
    query = uri.query
    fragment = uri.fragment

 	if scheme!==nothing
        print(io, scheme)
        print(io, ':')
 	end

 	if authority!==nothing
        print(io, "//")

		idx = findfirst('@', authority)
		if idx !== nothing
			# <user>@<auth>
			userinfo = SubString(authority, 1:idx-1)
			host_and_port = SubString(authority, idx + 1)
			encode(io, userinfo, is_rfc3986_userinfo)
            print(io, '@')
        else
            host_and_port = SubString(authority, 1)
		end

		idx3 = findfirst(':', host_and_port)
		if idx3 === nothing
            encode_host(io, host_and_port)
		else
			# <auth>:<port>
            encode_host(io, SubString(host_and_port, 1:idx3-1))
			print(io, SubString(host_and_port, idx3))
        end
     end

     # Append path
     encode_path(io, path)

    if query!==nothing
        print(io, '?')
        encode(io, query, is_rfc3986_query)
    end

 	if fragment!==nothing
        print(io, '#')
        encode(io, fragment, is_rfc3986_fragment)
    end

    return nothing
end

function Base.string(uri::URI)
    io = IOBuffer()

    print(io, uri)

    return String(take!(io))
end

include("uri_helpers.jl")

end
