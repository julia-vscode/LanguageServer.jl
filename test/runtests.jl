using LanguageServer
using Base.Test
Range =  LanguageServer.Range

include("test_document.jl")
include("test_communication.jl")
include("test_hover.jl")
include("test_lint.jl")
