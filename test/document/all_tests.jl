using Test

@testset "Document" begin

    include("test_basic.jl")
    include("test_doc_changes.jl")
    include("test_utf16.jl")

end