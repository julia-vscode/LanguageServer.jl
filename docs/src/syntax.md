# Syntax Reference

```@index
Modules = [LanguageServer]
Pages   = ["syntax.md"]
```

## Main
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("src", f) for f in filter(f -> endswith(f, ".jl"), readdir(joinpath(@__DIR__, "..", "src")))]
```

## Requests
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("requests", f) for f in readdir(joinpath(@__DIR__, "..", "src", "requests"))]
```

## Protocol
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("protocol", f) for f in readdir(joinpath(@__DIR__, "..", "src", "protocol"))]
```

## Extensions
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("extensions", f) for f in readdir(joinpath(@__DIR__, "..", "src", "extensions"))]
```
