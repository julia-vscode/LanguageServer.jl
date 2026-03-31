@testitem "Completions" begin
    import LanguageServer

    
    # Test Unicode Altname completion
    s = ["α", "decay_β", "θ₀", "x₀", "y", "z"]
    s_exp = ["alpha", "decay_beta", "theta_0", "x_0", nothing, nothing]
    for (i, (s, s_exp)) in enumerate(zip(s, s_exp))
        @test LanguageServer.latex_symbol_altname(s) == s_exp
    end

end
