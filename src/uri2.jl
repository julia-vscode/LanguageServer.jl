"""
A type that represents a URI. The main feature provided currently is
that when the file:// scheme is used and the platform is Windows,
equality and hashing is case-insensitive.
"""
struct URI2
    _uri::String
end

import Base.==
function ==(a::URI2, b::URI2)
    @static if is_windows()
        if startswith(a._uri, "file://")
            return lowercase(a._uri) == lowercase(b._uri)
        else
            return a._uri == b._uri
        end
    else
        return a._uri == b._uri
    end
end

function Base.hash(a::URI2, h::UInt)
    @static if is_windows()
        if startswith(a._uri, "file://")
            return hash(lowercase(a._uri), h)
        else
            return hash(a_uri)
        end
    else
        return hash(a._uri)
    end
end
