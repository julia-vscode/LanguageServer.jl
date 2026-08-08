#!/usr/bin/env bash

JULIABIN="julia"
JULIAPROJ="JuliaLSP"
JULIACOMP="JuliaLSP_compiled"

REPO="https://github.com/julia-vscode/LanguageServer.jl"
BRANCH="master"

HL='\033[1;4;31m'
NC='\033[0m'

errorexit() {
    echo -e ${HL}"$@"${NC}
    exit 1
}

while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -j|--julia)
            JULIABIN="$2"
            shift
        ;;
        -b|--branch)
            BRANCH="$2"
            shift
        ;;
        -r|--repo)
            REPO="$2"
            shift
        ;;
        *)
            echo -e "Usage:\ncompile.sh [-j|--julia <julia binary>] [-b|--branch <repo branch>]" >&2
            exit
        ;;
    esac
    shift
done

echo -e ${HL}Updating packages${NC}

$JULIABIN --project=${JULIAPROJ} --startup-file=no --history-file=no -e \
          "import Pkg;
          Pkg.add(Pkg.PackageSpec(url=\"${REPO}\", rev=\"${BRANCH}\"));
          Pkg.update();" || errorexit Cannot update packages

echo -e ${HL}Compiling...${NC}

# Additional libs are needed for running tests
$JULIABIN --startup-file=no --history-file=no -e \
          "import Pkg;
          Pkg.add(\"PackageCompiler\")
          Pkg.add([\"Test\", \"Sockets\", \"CSTParser\", \"StaticLint\", \"JSON\", \"JSONRPC\"])
          using PackageCompiler;
          Pkg.activate(\"${JULIAPROJ}\");
          create_app(\"${JULIAPROJ}\", \"${JULIACOMP}\",
          force=true, precompile_execution_file=\"../test/runtests.jl\");" \
              || errorexit Cannot compile packages

echo -e ${HL}Compiled${NC}
