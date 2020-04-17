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