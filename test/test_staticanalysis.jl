import LanguageServer: parseblocks, isblock, get_names, parsestruct, parsesignature, get_block, get_type, get_fields, shiftloc!
server = LanguageServerInstance(IOBuffer(), IOBuffer(), false)

testtext = """module testmodule
type testtype
    a
    b::Int
    c::Vector{Int}
end

function testfunction(a, b::Int, c::testtype)
    return c
end
end
"""

blocks = Expr(:block)
parseblocks(testtext, blocks, 0)
blocks.typ = 0:endof(testtext)

ns = get_names(blocks, 119, server)


@test length(ns.list) == 6
@test ns.list[:a].t == :Any
@test parsestruct(ns.list[:testtype].def) == [:a => :Any, :b => :Int, :c => :(Vector{Int})]
@test parsesignature(ns.list[:testfunction].def.args[1]) == [(:a, :Any), (:b, :Int), (:c, :testtype)]


@test get_type(:testtype, ns) == :DataType
@test get_type(:c, ns) == :testtype
@test get_type([:c, :c], ns) == Symbol("Vector{Int}")
@test get_fields(:testtype, ns)[:c] == :(Vector{Int})
@test sort(collect(keys(get_fields(:Expr, ns)))) == sort(fieldnames(Expr))

shiftloc!(blocks, 5)
@test blocks.args[1].typ == 5:144

