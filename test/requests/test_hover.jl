@testitem "Hover" begin
    include("../test_shared_server.jl")

    settestdoc("""
    1234
    Base
    +
    vari = 1234
    \"\"\"
        Text
    \"\"\"
    function func(arg) end
    func() = nothing
    module M end
    struct T end
    mutable struct T end
    for i = 1:1 end
    while true end
    begin end
    sin()
    struct S
        a
        b
        c
        d
        e
        f
        g
    end
    S(a,b,c,d,e,f,g)
    """)

    @test hover_test(0, 1) === nothing
    @test hover_test(1, 1) !== nothing
    @test hover_test(2, 1) !== nothing
    @test hover_test(3, 1) !== nothing
    @test hover_test(7, 11) !== nothing
    @test hover_test(8, 2) !== nothing
    @test hover_test(7, 16) !== nothing
    @test hover_test(7, 20) !== nothing
    @test hover_test(9, 11) !== nothing
    @test hover_test(10, 11) !== nothing
    @test hover_test(11, 18) !== nothing
    @test hover_test(12, 14) !== nothing
    @test hover_test(13, 13) !== nothing
    @test hover_test(14, 7) !== nothing
    @test hover_test(15, 2) !== nothing
    @test hover_test(15, 5) === nothing
    @test hover_test(25, 15) !== nothing
end

@testitem "hover docs" begin
    include("../test_shared_server.jl")

    settestdoc("""
    "I have a docstring"
    Base.@kwdef struct SomeStruct
        a
    end
    """)
    @test startswith(hover_test(1, 20).contents.value, "I have a docstring")
end

@testitem "hover argument qualified function" begin
    include("../test_shared_server.jl")

    settestdoc("""
    module M
        f(a,b,c,d,e) = 1
    end
    M.f(1,2,3,4,5)
    """)
    @test hover_test(3, 5).contents.value == "Argument 1 of 5 in call to `M.f`\n"
end
