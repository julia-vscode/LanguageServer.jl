struct FilePath
    _path::String
end

import Base.==
function ==(a::FilePath, b::FilePath)
    @static if is_windows()
        return lowercase(a._path) == lowercase(b._path)
    else
        return a._path == b._path
    end
end

function Base.hash(a::FilePath, h::UInt)
    @static if is_windows()
        return hash(lowercase(a._path), h)
    else
        return hash(a._path)
    end
end

function filepath_from_uri(uri::AbstractString)
    return FilePath(uri2filepath(uri))
end
