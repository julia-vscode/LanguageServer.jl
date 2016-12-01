import LanguageServer: parseblocks, children, isblock, get_namespace, parsestruct, parsesignature, get_block, get_type, get_fields, shiftloc!


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

blocks = Expr(:global)
parseblocks(testtext, blocks, 0)

ex, ns = get_namespace(blocks, 119)
@test ex.head==:function
@test length(ns)==7
@test ns[:a][1]==:argument
@test parsestruct(ns[:testtype][4])==[:a=>:Any,:b=>:Int,:c=>:(Vector{Int})]
@test parsesignature(ns[:testfunction][4].args[1])==[(:a, :Any), (:b, :Int), (:c, :testtype)]

@test ns[:testtype][4] == get_block(blocks, first(ns[:testtype][3]))
@test ns[:testfunction][4] == get_block(blocks, first(ns[:testfunction][3]))

@test get_type(:testtype, ns)==:DataType
@test get_type(:c, ns)==:testtype
@test get_type([:c,:c], ns, blocks)==Symbol("Vector{Int}")
@test get_fields(:testtype, ns, blocks)[:c]==:(Vector{Int})
@test sort(collect(keys(get_fields(:Expr, ns, blocks))))==sort(fieldnames(Expr))

shiftloc!(blocks, 5)
@test blocks.args[1].typ==5:144

