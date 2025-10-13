# LanguageServer

[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
![](https://github.com/julia-vscode/LanguageServer.jl/workflows/Run%20CI%20on%20master/badge.svg)
[![codecov](https://codecov.io/gh/julia-vscode/LanguageServer.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/julia-vscode/LanguageServer.jl)

## Overview

This package implements the Microsoft [Language Server Protocol](https://github.com/Microsoft/language-server-protocol)
for the [Julia](http://julialang.org/) programming language.

Text editors with a client for the Language Server Protocol are able to
make use of the Julia Language Server for various code editing features:

- [VS Code](https://marketplace.visualstudio.com/items?itemName=julialang.language-julia)
- [Atom](https://github.com/pfitzseb/atom-julia-lsp-client)
- [Vim and Neovim](../../wiki/Vim-and-Neovim)
- [Emacs](../../wiki/Emacs)
- [Sublime Text](https://github.com/tomv564/LSP)
- [Kakoune](../../wiki/Kakoune)
- [Helix](../../wiki/helix)
- [Kate](../../wiki/Kate)
- [Others](https://microsoft.github.io/language-server-protocol/implementors/tools/)

## Installation and Usage
**Documentation**: [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://www.julia-vscode.org/LanguageServer.jl/dev)

To install LanguageServer.jl into the current environment:

```julia
using Pkg
Pkg.add("LanguageServer")
```

To run an instance of LanguageServer.jl on `env_path`, you can run
Julia as follows:

```sh
julia --project=/path/to/LanguageServer.jl/environment \
  -e "using LanguageServer; runserver()" \
  <env_path>
```

If `env_path` is not specified, the language server will run on the
parent project of `pwd` or on the default `.julia/environments/v#.#`
if there is no parent project.

## Development of the VSCode extension

See https://github.com/julia-vscode/julia-vscode/wiki for information on how to test this package with the VSCode extension
