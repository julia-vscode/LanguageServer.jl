# Syntax Reference

```@index
Modules = [LanguageServer]
Pages   = ["syntax.md"]
```

## Main
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("src", f) for f in readdir("../src") if endswith(f, ".jl")]
```

## Requests
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("src", "requests", f) for f in readdir("../src/requests")]
```

## Protocol
```@autodocs
Modules = [LanguageServer]
Pages   = [joinpath("src", "protocol", f) for f in readdir("../src/protocol")]
```
