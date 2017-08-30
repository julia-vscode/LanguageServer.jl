function test_scope(str, offset)
    server = LanguageServer.LanguageServerInstance(false,false,false)
    x = CSTParser.parse(str,true)
    s = LanguageServer.TopLevelScope(LanguageServer.ScopePosition("none", offset), LanguageServer.ScopePosition("none", 0), false, Dict(), LanguageServer.EXPR[], Symbol[], false, true, Dict{String,Set{String}}("toplevel" => Set{String}()), Dict{String,Set{String}}("toplevel" => Set{String}()), [])
    LanguageServer.toplevel(x, s, server)
    s.current.offset = 0
    y = LanguageServer._scope(x, s, server)
    if !isempty(s.stack) && last(s.stack) isa CSTParser.EXPR{CSTParser.MacroName}
        y = last(s.stack)
    end
    ns = isempty(s.namespace) ? "toplevel" : join(s.namespace, ".")
    yname = string(Expr(y))
    yname in keys(s.symbols) || yname in s.imported_names[ns]
end

function test_undefvar(str, offset = 0)
    server = LanguageServer.LanguageServerInstance(false,false,false)
    x = CSTParser.parse(str,true)
    s = LanguageServer.TopLevelScope(LanguageServer.ScopePosition("none", typemax(Int)), LanguageServer.ScopePosition("none", 0), false, Dict(), LanguageServer.EXPR[], Symbol[], false, true, Dict{String,Set{String}}("toplevel" => Set{String}()), Dict{String,Set{String}}("toplevel" => Set{String}()), [])
    LanguageServer.toplevel(x, s, server)
    L = LanguageServer.LintState([], [], [])
    s.current.offset = 0
    LanguageServer.lint(x, s, L, server, true)
    isempty(L.diagnostics)
end

@testset "scoping" begin
for f in [test_scope,test_undefvar]
    @testset "$(string(f))" begin
        @testset "for" begin
            @test f("""
            for iter in 1:10
                iter
            end
            """, 24)
            @test f("""
            for iter1 in 1:10, iter2 = 1:10, iter3 ∈ 1:30
                iter1
                iter2
                iter3
            end
            """, 53)
            @test f("""
            for iter1 in 1:10, iter2 = 1:10, iter3 ∈ 1:30
                iter1
                iter2
                iter3
            end
            """, 61)
            @test f("""
            for iter1 in 1:10, iter2 = 1:10, iter3 ∈ 1:30
                iter1
                iter2
                iter3
            end
            """, 69)
        end

        @testset "generators" begin
            @test f("""iter for iter in 1""", 2)
            @test f("""iter for iter in 1""", 11)
        end

        @testset "assignment" begin
            @test f("""
            var1 = 12345
            var1
            """, 14)
            @test f("""
            var1, var2 = 1,2
            var1
            var2
            """, 19)
            @test f("""
            var1, var2 = 1,2
            var1
            var2
            """, 24)
            @test f("""
            var1 = var2 = 12345
            var2
            """, 22)
        end

        @testset "anon func" begin
            @test f("arg -> arg * arg", 10)
            @test f("(arg1, arg2) -> arg1 * arg2", 18)
        end

        @testset "let" begin
            @test f("""
            let var1 = 1
                var1
            end
            """, 19)
            @test f("""
            let var1 = 1, var2 = 1
                var2
            end
            """, 30)
        end

        @testset "do" begin
            @test f("""
            sin([1]) do var1
                var1
            end
            """, 22)
            @test f("""
            sin([1]) do var1, var2 
                var2
            end
            """, 28)
        end

        @testset "try" begin
            @test f("""
            try
                sin(1)
            catch err
                sin(err)
            end
            """, 34)
        end

        @testset "functions" begin
            @test f("""
            function func(x)
                func(x)
            end
            func(1)
            """, 24)
            @test f("""
            function func(x)
                func(x)
            end
            func(1)
            """, 35)
            @test f("""
            function func(arg = 1)
                arg
            end
            func(1)
            """, 29)
            @test f("""
            function func(arg::T) where T
                arg
            end
            func(1)
            """, 36)
        end

        @testset "macros" begin
            @test f("""
            macro mac(x)
                x
            end
            @mac 1
            """, 25)
        end

        @testset "datatypes" begin
            @test f("""
            struct name end
            name
            """, 19)
            @test f("""
            mutable struct name end
            name
            """, 26)
            @test f("""
            abstract type name end
            name
            """, 25)
            @test f("""
            primitive type name 8 end
            name
            """, 28)
        end

        @testset "modules" begin
            @test f("""
            module name end
            name
            """, 19)
            @test f("""
            baremodule name end
            name
            """, 23)
        end

        @testset "misc" begin
            @test f("""
            function(file)
                newstr = file
            end
            """, 29) # julia-vscode issue 241

            @test f("""
            using Optim: minimizer
            res = Optim.optimize(x->sum(x.^2), ones(2))
            """, 33) # julia-vscode issue 222

            @test !f("""
            module A
            using Optim: minimizer
            res = Optim.optimize(x->sum(x.^2), ones(2))
            end
            """, 41) # julia-vscode issue 222
        end
    end
end
end
