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

@testset "URI comparison" begin

    if Sys.iswindows()
        @test LanguageServer.escape_uri("file:///c:/foo/bar") == "file:///c%3A/foo/bar"
        @test LanguageServer.escape_uri("file://wsl%24/foo/bar") == "file://wsl%24/foo/bar"
        @test LanguageServer.escape_uri("file:///D:/FOO/bar") == "file:///D%3A/FOO/bar"

        @test hash(LanguageServer.URI2("file:///D:/FOO/bar")) == hash(LanguageServer.URI2("file:///d%3A/FOO/bar"))
        @test hash(LanguageServer.URI2("file:///C:/foo/space bar")) == hash(LanguageServer.URI2("file:///c%3A/foo/space%20bar"))
        @test hash(LanguageServer.URI2("file://wsl\$/foo/bar")) == hash(LanguageServer.URI2("file://wsl%24/foo/bar"))

        @test LanguageServer.URI2("file:///D:/FOO/bar") == LanguageServer.URI2("file:///d%3A/FOO/bar")
        @test LanguageServer.URI2("file:///C:/foo/space bar") == LanguageServer.URI2("file:///c%3A/foo/space%20bar")
        @test LanguageServer.URI2("file://wsl\$/foo/bar") == LanguageServer.URI2("file://wsl%24/foo/bar")
    else
        @test LanguageServer.escape_uri("file:///foo/bar") == "file:///foo/bar"

        @test hash(LanguageServer.URI2("file:///foo/bar")) == hash(LanguageServer.URI2("file:///foo/bar"))
        @test hash(LanguageServer.URI2("file:///foo/space bar")) == hash(LanguageServer.URI2("file:///foo/space%20bar"))

        @test LanguageServer.URI2("file:///foo/bar") == LanguageServer.URI2("file:///foo/bar")
        @test LanguageServer.URI2("file:///foo/space bar") == LanguageServer.URI2("file:///foo/space%20bar")
    end

end

@testset "is_in_test_dir_of_package" begin
    @test LanguageServer.is_in_test_dir_of_package(@__DIR__)
    @test !LanguageServer.is_in_test_dir_of_package(pathof(LanguageServer))
end
