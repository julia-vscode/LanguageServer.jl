#!/bin/bash

JULIABIN="julia"
DEBUG="false"

while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -j|--julia)
            JULIABIN="$2"
            shift
        ;;
        --debug)
            DEBUG="true"
        ;;
        *)
            echo "unknown option: $key" >&2
            exit
        ;;
    esac
    shift
done

$JULIABIN --startup-file=no --history-file=no -e \
    "using LanguageServer; server = LanguageServer.LanguageServerInstance(stdin, stdout, $DEBUG); server.runlinter = true; run(server);" \
    <&0 >&1 &

PID=$!

while true; do
    # quit if server exited
    kill -0 "$PID" || break
    # if the current process is orphan, kill it and its children
    if [ $(ps -o ppid= -p "$$") -eq 1 ]; then
        kill -9 "$PID" $(pgrep -P "$PID")
        exit
    fi
    sleep 1
done
