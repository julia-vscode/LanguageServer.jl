using Test, Sockets, LanguageServer, CSTParser, SymbolServer, SymbolServer.Pkg, StaticLint, JSON
using LanguageServer: Document, get_text, get_offset, get_line_offsets, get_position_at, get_open_in_editor, set_open_in_editor, is_workspace_file, applytextdocumentchanges
import JSONRPC
const LS = LanguageServer
const Range = LanguageServer.Range

# TODO Replace this with a proper mock endpoint
JSONRPC.send(::Nothing, ::Any, ::Any) = nothing

@testset "LanguageServer" begin

    @testset "document" begin
        include("test_document.jl")
    end
    @testset "communication" begin
        include("test_communication.jl")
    end
    @testset "intellisense" begin
        include("test_intellisense.jl")
        @testset "completions" begin
            include("requests/completions.jl")
        end
    end
    @testset "edit" begin
        include("test_edit.jl")
    end
    @testset "actions" begin
        include("test_actions.jl")
    end
    @testset "paths" begin
        include("test_paths.jl")
    end

end
