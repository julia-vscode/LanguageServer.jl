@testitem "filepath2uri to string" begin
    using LanguageServer.URIs2

    # TODO Remove this Windows flag later, it is not in the original, but we need support for relative paths first
    if Sys.iswindows()
        @test filepath2uri("c:/win/path") |> string == "file:///c%3A/win/path"
        @test filepath2uri("C:/win/path") |> string == "file:///c%3A/win/path"
        @test filepath2uri("c:/win/path/") |> string == "file:///c%3A/win/path/"
    end
    @test filepath2uri("/c:/win/path") |> string == "file:///c%3A/win/path"
end

@testitem "filepath2uri to string - Windows special" begin
    using LanguageServer.URIs2

    if Sys.iswindows()
        @test filepath2uri("c:\\win\\path") |> string == "file:///c%3A/win/path"
        @test filepath2uri("c:\\win/path") |> string == "file:///c%3A/win/path"
        # else TODO Put this else back in once we support these paths on Unix
        # @test filepath2uri("c:\\win\\path") |> string == "file:///c%3A%5Cwin%5Cpath"
        # @test filepath2uri("c:\\win/path") |> string == "file:///c%3A%5Cwin/path"
    end
end

@testitem "uri2filepath to string - Windows special" begin
    using LanguageServer.URIs2

    if Sys.iswindows()
        @test uri2filepath(filepath2uri("c:\\win\\path")) == "c:\\win\\path"
        @test uri2filepath(filepath2uri("c:\\win/path")) == "c:\\win\\path"

        @test uri2filepath(filepath2uri("c:/win/path")) == "c:\\win\\path"
        @test uri2filepath(filepath2uri("c:/win/path/")) == "c:\\win\\path\\"
        @test uri2filepath(filepath2uri("C:/win/path")) == "c:\\win\\path"
        @test uri2filepath(filepath2uri("/c:/win/path")) == "c:\\win\\path"
        @test_broken uri2filepath(filepath2uri("./c/win/path")) == "\\.\\c\\win\\path"
        # else TODO Put this else back in once we support relative paths
        # @test uri2filepath(filepath2uri("c:/win/path")) == "c:/win/path"
        # @test uri2filepath(filepath2uri("c:/win/path/")) == "c:/win/path/"
        # @test uri2filepath(filepath2uri("C:/win/path")) == "c:/win/path"
        # @test uri2filepath(filepath2uri("/c:/win/path")) == "c:/win/path"
        # @test_broken uri2filepath(filepath2uri("./c/win/path")) == "/./c/win/path"
    end
end

@testitem "uri2filepath - no `uri2filepath` when no `path`" begin
    using LanguageServer.URIs2

    value = URI("file://%2Fhome%2Fticino%2Fdesktop%2Fcpluscplus%2Ftest.cpp")

    @test value.authority == "/home/ticino/desktop/cpluscplus/test.cpp"
    @test_broken value.path == "/"
    if Sys.iswindows()
        @test_broken uri2filepath(value) == "\\"
    else
        @test_broken uri2filepath(value) == "/"
    end
end

@testitem "parse" begin
    using LanguageServer.URIs2

    value = URI("http:/api/files/test.me?t=1234")
    @test value.scheme == "http"
    @test_broken value.authority == ""
    @test value.path == "/api/files/test.me"
    @test value.query == "t=1234"
    @test value.fragment === nothing

    value = URI("http://api/files/test.me?t=1234")
    @test value.scheme == "http"
    @test value.authority == "api"
    @test value.path == "/files/test.me"
    @test value.query == "t=1234"
    @test value.fragment === nothing

    value = URI("file:///c:/test/me")
    @test value.scheme == "file"
    @test value.authority == ""
    @test value.path == "/c:/test/me"
    @test value.fragment === nothing
    @test value.query === nothing
    @test uri2filepath(value) == (Sys.iswindows() ? "c:\\test\\me" : "c:/test/me")

    value = URI("file://shares/files/c%23/p.cs")
    @test value.scheme == "file"
    @test value.authority == "shares"
    @test value.path == "/files/c#/p.cs"
    @test value.fragment === nothing
    @test value.query === nothing
    @test uri2filepath(value) == (Sys.iswindows() ? "\\\\shares\\files\\c#\\p.cs" : "//shares/files/c#/p.cs")

    value = URI("file:///c:/Source/Z%C3%BCrich%20or%20Zurich%20(%CB%88zj%CA%8A%C9%99r%C9%AAk,/Code/resources/app/plugins/c%23/plugin.json")
    @test value.scheme == "file"
    @test value.authority == ""
    @test value.path == "/c:/Source/Zürich or Zurich (ˈzjʊərɪk,/Code/resources/app/plugins/c#/plugin.json"
    @test value.fragment === nothing
    @test value.query === nothing

    value = URI("file:///c:/test %25/path")
    @test value.scheme == "file"
    @test value.authority == ""
    @test value.path == "/c:/test %/path"
    @test value.fragment === nothing
    @test value.query === nothing

    value = URI("inmemory:")
    @test value.scheme == "inmemory"
    @test value.authority === nothing
    @test value.path === ""
    @test value.query === nothing
    @test value.fragment === nothing

    value = URI("foo:api/files/test")
    @test value.scheme == "foo"
    @test value.authority === nothing
    @test value.path == "api/files/test"
    @test value.query === nothing
    @test value.fragment === nothing

    value = URI("file:?q")
    @test value.scheme == "file"
    @test_broken value.authority == ""
    @test_broken value.path == "/"
    @test value.query == "q"
    @test value.fragment === nothing

    value = URI("file:#d")
    @test value.scheme == "file"
    @test value.authority === nothing
    @test_broken value.path == "/"
    @test value.query === nothing
    @test value.fragment == "d"

    value = URI("f3ile:#d")
    @test value.scheme == "f3ile"
    @test value.authority === nothing
    @test value.path === ""
    @test value.query === nothing
    @test value.fragment == "d"

    value = URI("foo+bar:path")
    @test value.scheme == "foo+bar"
    @test value.authority === nothing
    @test value.path == "path"
    @test value.query === nothing
    @test value.fragment === nothing

    value = URI("foo-bar:path")
    @test value.scheme == "foo-bar"
    @test value.authority === nothing
    @test value.path == "path"
    @test value.query === nothing
    @test value.fragment === nothing

    value = URI("foo.bar:path")
    @test value.scheme == "foo.bar"
    @test value.authority === nothing
    @test value.path == "path"
    @test value.query === nothing
    @test value.fragment === nothing
end
