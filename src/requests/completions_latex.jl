

# TODO Complete, only a subset for now
latex_inverse_mappings = Dict{Char,String}(
# Greek    
    'Α' => "Alpha",
    'Β' => "Beta",
    'Γ' => "Gamma",
    'Δ' => "Delta",
    'Ε' => "Epsilon",
    'Ζ' => "Zeta",
    'Η' => "Eta",
    'Θ' => "Theta",
    'Ι' => "Iota",
    'Κ' => "Kappa",
    'Λ' => "Lambda",
    'Ξ' => "Xi",
    'Π' => "Pi",
    'Ρ' => "Rho",
    'Σ' => "Sigma",
    'Τ' => "Tau",
    'Υ' => "Upsilon",
    'Φ' => "Phi",
    'Χ' => "Chi",
    'Ψ' => "Psi",
    'Ω' => "Omega",
    'α' => "alpha",
    'β' => "beta",
    'γ' => "gamma",
    'δ' => "delta",
    'ζ' => "zeta",
    'η' => "eta",
    'θ' => "theta",
    'ι' => "iota",
    'κ' => "kappa",
    'λ' => "lambda",
    'μ' => "mu",
    'ν' => "nu",
    'ξ' => "xi",
    'π' => "pi",
    'ρ' => "rho",
    'ς' => "varsigma",
    'σ' => "sigma",
    'τ' => "tau",
    'υ' => "upsilon",
    'φ' => "varphi",
    'χ' => "chi",
    'ψ' => "psi",
    'ω' => "omega",
    'ϑ' => "vartheta",
    'ϕ' => "phi",
    'ϖ' => "varpi",
    'Ϛ' => "Stigma",
    'Ϝ' => "Digamma",
    'ϝ' => "digamma",
    'Ϟ' => "Koppa",
    'Ϡ' => "Sampi",
    'ϰ' => "varkappa",
    'ϱ' => "varrho",
    'ϴ' => "varTheta",
    'ϵ' => "epsilon",
    '϶' => "backepsilon",

    # Indices
    '₀' => "_0",
    '₁' => "_1",
    '₂' => "_2",
    '₃' => "_3",
    '₄' => "_4",
    '₅' => "_5",
    '₆' => "_6",
    '₇' => "_7",
    '₈' => "_8",
    '₉' => "_9",
)

"""
    latex_symbol_altname(s)

If the string `s` contains latex unicode symbols, return the string with the symbols replaced by their corresponding latex commands. 
If there are no latex symbols in `s`, return `nothing`.
"""
function latex_symbol_altname(s)

    parts = map(eachindex(s)) do i
        c = s[i]
        if !isascii(c) && c ∈ keys(latex_inverse_mappings)
            return latex_inverse_mappings[c]
        else
            return string(c) # needed for typestability
        end
    end

    # If the number of codeunits is the same as the number of parts, then there are no latex symbols
    ncodeunits(s) === length(parts) && return nothing

    return join(parts)
end
