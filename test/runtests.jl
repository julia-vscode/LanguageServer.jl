using LanguageServer, CSTParser, Test, SymbolServer
Range = LanguageServer.Range

@testset "LanguageServer" begin

include("test_document.jl")
include("test_communication.jl")
include("test_hover.jl")
include("text_edit.jl")


end
