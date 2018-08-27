using LanguageServer
using CSTParser
using Test
Range = LanguageServer.Range

@testset "LanguageServer" begin

include("test_document.jl")
include("test_communication.jl")
include("test_hover.jl")
include("test_lint.jl")
include("test_scope.jl")

end
