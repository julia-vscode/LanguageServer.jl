const default_format_options = (4, 100)

struct FormatOptions <: JuliaFormatter.AbstractStyle
    indent::Int
    margin::Int
    FormatOptions(indent, margin) =
        new(something(indent, default_format_options[1]), something(margin, default_format_options[2]))
end
FormatOptions() = FormatOptions(default_format_options...)


JuliaFormatter.getstyle(x::FormatOptions) = x

# All functions that don't have a dispatch defined for FormatOptions
# fallback to the definition for JuliaFormatter.DefaultStyle. This is
# how we customize the behavior of the formatter.
