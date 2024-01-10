@testitem "latex completions" begin
    include("../test_shared_server.jl")

    settestdoc("""
    \\therefor
    .\\therefor
    #\\therefor
    "\\therefor"
    \"\"\"\\therefor\"\"\"
    ^\\therefor
    \\:water_buffal
    """)
    @test completion_test(0, 9).items[1].textEdit.newText == "∴"
    @test completion_test(0, 9).items[1].textEdit.range == LanguageServer.Range(0, 0, 0, 9)

    @test completion_test(1, 10).items[1].textEdit.newText == "∴"
    @test completion_test(1, 10).items[1].textEdit.range == LanguageServer.Range(1, 1, 1, 10)

    @test completion_test(2, 10).items[1].textEdit.newText == "∴"
    @test completion_test(2, 10).items[1].textEdit.range == LanguageServer.Range(2, 1, 2, 10)

    @test completion_test(3, 10).items[1].textEdit.newText == "∴"
    @test completion_test(3, 10).items[1].textEdit.range == LanguageServer.Range(3, 1, 3, 10)

    @test completion_test(4, 12).items[1].textEdit.newText == "∴"
    @test completion_test(4, 12).items[1].textEdit.range == LanguageServer.Range(4, 3, 4, 12)

    @test completion_test(5, 10).items[1].textEdit.newText == "∴"
    @test completion_test(5, 10).items[1].textEdit.range == LanguageServer.Range(5, 1, 5, 10)

    @test completion_test(6, 14).items[1].textEdit.newText == "🐃"
    @test completion_test(6, 14).items[1].textEdit.range == LanguageServer.Range(6, 0, 6, 14)
end

@testitem "path completions" begin
end

@testitem "import completions" begin
    include("../test_shared_server.jl")

    settestdoc("import Base: r")
    @test any(item.label == "rand" for item in completion_test(0, 14).items)

    settestdoc("import ")
    @test (r = all(item.label in ("Main", "Base", "Core") for item in completion_test(0, 7).items)) && !isempty(r)

    settestdoc("""module M end
    import .""")
    @test_broken completion_test(1, 8).items[1].label == "M"

    settestdoc("import Base.M")
    @test any(item.label == "Meta" for item in completion_test(0, 13).items)

    settestdoc("import Bas")
    @test any(item.label == "Base" for item in completion_test(0, 10).items)
end

@testitem "getfield completions" begin
    include("../test_shared_server.jl")

    settestdoc("Base.")
    @test length(completion_test(0, 5).items) > 10

    settestdoc("Base.B")
    @test any(item.label == "Base" for item in completion_test(0, 6).items)

    settestdoc("Base.r")
    @test any(item.label == "rand" for item in completion_test(0, 6).items)

    settestdoc("""
    using Base.Meta
    Base.Meta.
    """)
    @test any(item.label == "quot" for item in completion_test(1, 10).items)

    settestdoc("""
    module M
    inner = 1
    end
    M.
    """)
    @test any(item.label == "inner" for item in completion_test(3, 2).items)

    settestdoc("""
    x = Expr()
    x.
    """)
    @test (r = all(item.label in ("head", "args") for item in completion_test(1, 2).items)) && (!isempty(r))

    settestdoc("""
    struct T
        f1
        f2
    end
    x = T()
    x.
    """)
    @test (r = all(item.label in ("f1", "f2") for item in completion_test(5, 2).items)) && !isempty(r)
end

@testitem "token completions" begin
    include("../test_shared_server.jl")

    settestdoc("B")
    @test any(item.label == "Base" for item in completion_test(0, 1).items)

    settestdoc("r")
    @test any(item.label == "rand" for item in completion_test(0, 1).items)

    settestdoc("@t")
    @test any(item.label == "@time" for item in completion_test(0, 2).items)

    settestdoc("i")
    @test any(item.label == "if" for item in completion_test(0, 1).items)

    settestdoc("i")
    @test any(item.label == "in" for item in completion_test(0, 1).items)

    settestdoc("for")
    @test any(item.label == "for" for item in completion_test(0, 3).items)

    settestdoc("in")
    @test any(item.label == "in" for item in completion_test(0, 2).items)

    settestdoc("isa")
    @test any(item.label == "isa" for item in completion_test(0, 3).items)

    # String macros
    settestdoc("uint12")
    @test any(item.label == "uint128\"" for item in completion_test(0, 6).items)
    @test any(item.label == "@uint128_str" for item in completion_test(0, 6).items)

    settestdoc("@uint12")
    @test any(item.label == "@uint128_str" for item in completion_test(0, 7).items)

    settestdoc("""
    macro foobar_str(ex) ex end
    fooba
    """)
    @test any(item.label == "foobar\"" for item in completion_test(1, 5).items)
    @test any(item.label == "@foobar_str" for item in completion_test(1, 5).items)
end

@testitem "scope var completions" begin
    include("../test_shared_server.jl")

    settestdoc("""
    myvar = 1
    βbb = 2
    bβb = 3
    myv
    βb
    bβ
    """)
    @test any(item.label == "myvar" for item in completion_test(3, 3).items)
    @test any(item.label == "βbb" for item in completion_test(4, 2).items)
    @test any(item.label == "bβb" for item in completion_test(5, 2).items)
end

@testitem "completion kinds" begin
    include("../test_shared_server.jl")

    Kinds = LanguageServer.CompletionItemKinds
    # issue #872
    settestdoc("""
        function f(kind_variable_arg)
            kind_variable_local = 1
            kind_variable_
        end
        """)
    items = completion_test(2, 18).items
    @test any(i -> i.label == "kind_variable_local" && i.kind == Kinds.Variable, items)
    @test any(i -> i.label == "kind_variable_arg" && i.kind == Kinds.Variable, items)
end

@testitem "completion details" begin
    include("../test_shared_server.jl")

    settestdoc("""
        struct Bar end
        struct Foo
            xxx::Int
            yyy::Bar
        end
        b = Bar()
        f = Foo(1, b)
        xxx = f.yyy
        f.yy
        xx
        """)
    items1 = completion_test(8, 4).items
    items2 = completion_test(9, 2).items
    @test any(i -> i.label == "yyy" && occursin("yyy::Bar", i.detail), items1)
    @test any(i -> i.label == "xxx" && occursin("xxx::Bar = f.yyy", i.detail), items2)
end

@testitem "complete function parens" begin
    include("../test_shared_server.jl")

    server.complete_func_parens = true
    settestdoc("""
        foo_func() = 1
        foo_var = 2
        fo
        """)
    items = completion_test(2, 2).items
    @test any(i -> i.label == "foo_func" && i.textEdit.newText == "foo_func()", items)
    @test any(i -> i.label == "foo_var" && i.textEdit.newText == "foo_var", items)
    @test any(i -> i.label == "foldl" && i.textEdit.newText == "foldl()", items)
    server.complete_func_parens = false
end
