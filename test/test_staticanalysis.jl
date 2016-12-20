import LanguageServer: parseblocks, isblock, get_names, parsestruct, parsesignature, get_block, get_type, get_fields, shiftloc!


testtext="""module testmodule
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
blocks.typ = 0:length(testtext.data)

ns = get_names(blocks, 119, server)


@test length(ns)==8
@test ns[:a][1]==:argument
@test parsestruct(ns[:testtype][3])==[:a=>:Any,:b=>:Int,:c=>:(Vector{Int})]
@test parsesignature(ns[:testfunction][3].args[1])==[(:a, :Any), (:b, :Int), (:c, :testtype)]


@test get_type(:testtype, ns)==:DataType
@test get_type(:c, ns)==:testtype
@test get_type([:c,:c], ns)==Symbol("Vector{Int}")
@test get_fields(:testtype, ns)[:c]==:(Vector{Int})
@test sort(collect(keys(get_fields(:Expr, ns))))==sort(fieldnames(Expr))

shiftloc!(blocks, 5)
@test blocks.args[1].typ==5:144

