@testitem "URI conversion" begin
    using LanguageServer.URIs2

    if Sys.iswindows()
        @test LanguageServer.URIs2.uri2filepath(uri"file://SERVER/foo/bar") == "\\\\SERVER\\foo\\bar"
        @test LanguageServer.URIs2.uri2filepath(uri"file://wsl%24/foo/bar") == "\\\\wsl\$\\foo\\bar"
        @test LanguageServer.URIs2.uri2filepath(uri"file:///D:/foo/bar") == "d:\\foo\\bar"
        @test LanguageServer.URIs2.uri2filepath(uri"file:///foo/bar") == "\\foo\\bar"

        @test LanguageServer.filepath2uri("\\\\SERVER\\foo\\bar") == uri"file://SERVER/foo/bar"
        @test LanguageServer.filepath2uri("\\\\wsl\$\\foo\\bar") == uri"file://wsl%24/foo/bar"
        @test LanguageServer.filepath2uri("d:\\foo\\bar") == uri"file:///d%3A/foo/bar"
    else
        @test LanguageServer.URIs2.uri2filepath(uri"file:///foo/bar") == "/foo/bar"

        @test LanguageServer.filepath2uri("/foo/bar") == uri"file:///foo/bar"
    end

end

@testitem "URI comparison" begin
    using LanguageServer.URIs2

    if Sys.iswindows()
        @test string(filepath2uri("C:\\foo\\bar")) == "file:///c%3A/foo/bar"
        @test string(filepath2uri("\\\\wsl\$\\foo\\bar")) == "file://wsl\$/foo/bar"

        @test hash(uri"file:///d:/FOO/bar") == hash(uri"file:///d%3A/FOO/bar")
        @test hash(uri"file:///c:/foo/space bar") == hash(uri"file:///c%3A/foo/space%20bar")
        @test hash(uri"file://wsl$/foo/bar") == hash(uri"file://wsl%24/foo/bar")

        @test uri"file:///d:/FOO/bar" == uri"file:///d%3A/FOO/bar"
        @test uri"file:///c:/foo/space bar" == uri"file:///c%3A/foo/space%20bar"
        @test uri"file://wsl$/foo/bar" == uri"file://wsl%24/foo/bar"
    else
        @test string(uri"file:///foo/bar") == "file:///foo/bar"

        @test hash(uri"file:///foo/bar") == hash(uri"file:///foo/bar")
        @test hash(uri"file:///foo/space bar") == hash(uri"file:///foo/space%20bar")

        @test uri"file:///foo/bar" == uri"file:///foo/bar"
        @test uri"file:///foo/space bar" == uri"file:///foo/space%20bar"
    end

end

@testitem "is_in_target_dir_of_package" begin
    @test LanguageServer.is_in_target_dir_of_package(@__DIR__, "test")
    @test !LanguageServer.is_in_target_dir_of_package(pathof(LanguageServer), "test")
end
