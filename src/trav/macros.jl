struct MacroDef
    package::String
    contrib_top::Function
    lint::Bool
end

const MacroList = Dict{String,MacroDef}(
    # Base
    "goto" => MacroDef("Base", x -> [], false),
    "label" => MacroDef("Base", x -> [], false),

    # SimpleTraits
    "traitdef" => MacroDef("SimpleTraits", function(x) 
            [str_value(CSTParser.get_id(x.args[2]))]
        end, true)
)

