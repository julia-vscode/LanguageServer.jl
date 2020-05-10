using Test, Sockets, LanguageServer, CSTParser, SymbolServer, SymbolServer.Pkg, StaticLint, JSON
using LanguageServer: Document, get_text, get_offset, get_line_offsets, get_position_at, get_open_in_editor, set_open_in_editor, is_workspace_file, applytextdocumentchanges
const LS = LanguageServer
const Range = LanguageServer.Range

@testset "LanguageServer" begin

@testset "document" begin
include("test_document.jl")
end
@testset "communication" begin
include("test_communication.jl")
end
@testset "hover" begin
include("test_hover.jl")
end
@testset "edit" begin
include("text_edit.jl")
end
@testset "actions" begin
include("test_actions.jl")
end

end
