baremodule Scoping
mutable struct Position
    offset::Int
    uri::String
    ScopePosition(uri = "",  offset = 0) = new(uri, offset)
end

mutable struct NameSpace
    symbols::Dict
    val::EXPR
end

end
