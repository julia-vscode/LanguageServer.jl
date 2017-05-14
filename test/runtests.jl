using LanguageServer
using Base.Test

tests = ["document", "communication", "hover"]

for t in tests
    fp = joinpath("test_$t.jl")
    println("$fp ...")
    include(fp)
end
