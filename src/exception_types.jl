struct LSSymbolServerFailure <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSSymbolServerFailure)
    print(io, ex.msg)
end

struct LSTextSyncError <: Exception
    msg::AbstractString
end

function Base.showerror(io::IO, ex::LSTextSyncError)
    print(io, ex.msg)
end