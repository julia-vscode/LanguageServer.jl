using Test
using LanguageServer

@testset "URI conversion" begin

if Sys.iswindows()
    @test LanguageServer.uri2filepath("file://SERVER/foo/bar") == "\\\\SERVER\\foo\\bar"
    @test LanguageServer.uri2filepath("file://wsl%24/foo/bar") == "\\\\wsl\$\\foo\\bar"
    @test LanguageServer.uri2filepath("file:///D:/foo/bar") == "d:\\foo\\bar"
    @test LanguageServer.uri2filepath("file:///foo/bar") == "\\foo\\bar"

    @test LanguageServer.filepath2uri("\\\\SERVER\\foo\\bar") == "file://SERVER/foo/bar"
    @test LanguageServer.filepath2uri("\\\\wsl\$\\foo\\bar") == "file://wsl%24/foo/bar"
    @test LanguageServer.filepath2uri("d:\\foo\\bar") == "file:///d%3A/foo/bar"
else
    @test LanguageServer.uri2filepath("file:///foo/bar") == "/foo/bar"

    @test LanguageServer.filepath2uri("/foo/bar") == "file:///foo/bar"
end

end
