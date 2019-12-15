abstract type Outbound end
abstract type HasMissingFields end

function JSON.Writer.CompositeTypeWrapper(t::HasMissingFields)
    fns = collect(fieldnames(typeof(t)))
    dels = Int[]
    for i = 1:length(fns)
        f = fns[i]
        if getfield(t, f) isa Missing
            push!(dels, i)
        end
    end
    deleteat!(fns, dels)
    JSON.Writer.CompositeTypeWrapper(t, Tuple(fns))
end


function field_allows_missing(field::Expr)
    field.head == :(::) && field.args[2] isa Expr &&
    field.args[2].head == :curly && field.args[2].args[1] == :Union &&
    last(field.args[2].args) == :Missing
end
function field_type(field::Expr)
    if field.args[2] isa Expr && field.args[2].head == :curly && field.args[2].args[1] == :Union
        return field.args[2].args[2]
    else
        return field.args[2]
    end
end

macro dict_readable(arg)
    tname = arg.args[2] isa Expr ? arg.args[2].args[1] : arg.args[2]
    ex = quote
        $((arg))

        function $((tname))(dict::Dict)
        end
    end
    fex = :($((tname))())
    for field in arg.args[3].args
        if !(field isa LineNumberNode)
            fieldname = string(field.args[1])
            fieldtype = field_type(field)
            if fieldtype isa Expr && fieldtype.head == :curly && fieldtype.args[2] != :Any
                f = :($(fieldtype.args[2]).(dict[$fieldname]))
            elseif fieldtype != :Any
                f = :($(fieldtype)(dict[$fieldname]))
            else
                f = :(dict[$fieldname])
            end
            if field_allows_missing(field)
                f = :(haskey(dict,$fieldname) ? $f : missing)
            end
            push!(fex.args, f)
        end
    end
    push!(ex.args[end].args[2].args, fex)
    return esc(ex)
end


include("basic.jl")
include("initialize.jl")
include("document.jl")
include("features.jl")
include("configuration.jl")


mutable struct CancelParams
    id::Union{String,Int64}
end
CancelParams(d::Dict) = CancelParams(d["id"])