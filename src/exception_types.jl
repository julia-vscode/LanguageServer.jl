struct LSSymbolServerFailure <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSSymbolServerFailure)
    print(io, ex.msg)
end

struct LSUriConversionFailure <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSUriConversionFailure)
    print(io, ex.msg)
end

struct LSOffsetError <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSOffsetError)
    print(io, ex.msg)
end

struct LSSyncMismatch <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSSyncMismatch)
    print(io, ex.msg)
end

struct LSHoverError <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSHoverError)
    print(io, ex.msg)
end

struct LSPositionToOffsetException <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSPositionToOffsetException)
    print(io, ex.msg)
end

struct LSRelativePath <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSRelativePath)
    print(io, ex.msg)
end

struct LSInfiniteLoop <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSInfiniteLoop)
    print(io, ex.msg)
end

struct LSInvalidFile <: Exception
    msg::AbstractString
    uri::URI
end

function Base.showerror(io::IO, ex::LSInvalidFile)
    print(io, ex.msg, " File: '", uri2filepath(ex.uri), "'")
end
