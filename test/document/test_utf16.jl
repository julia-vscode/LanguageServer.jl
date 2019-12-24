using Test
import LanguageServer: Document, Range, Position,
                       get_text, get_offset, get_line_offsets, get_position_at

@testset "UTF16 handling" begin
    doc = Document("", "aaa", false)
    @test sizeof(get_text(doc)) == 3
    @test get_offset(doc, 0, 0) == 0
    @test get_position_at(doc, 0) == (0, 0)
    @test get_offset(doc, 0, 1) == 1
    @test get_position_at(doc, 1) == (0, 1)
    @test get_offset(doc, 0, 2) == 2
    @test get_position_at(doc, 2) == (0, 2)
    @test get_offset(doc, 0, 3) == 3
    @test get_position_at(doc, 3) == (0, 3)
    

    doc = Document("", "ααα", false)
    @test sizeof(get_text(doc)) == 6
    @test get_offset(doc, 0, 0) == 0
    @test get_position_at(doc, 0) == (0, 0)
    @test get_offset(doc, 0, 1) == 1
    @test get_position_at(doc, 1) == (0, 1)
    @test get_offset(doc, 0, 2) == 3
    @test get_position_at(doc, 3) == (0, 2)
    @test get_offset(doc, 0, 3) == 5
    @test get_position_at(doc, 5) == (0, 3)

    doc = Document("", "ࠀࠀࠀ", false) # 0x0800
    @test sizeof(get_text(doc)) == 9
    @test get_offset(doc, 0, 0) == 0
    @test get_position_at(doc, 0) == (0, 0)
    @test get_offset(doc, 0, 1) == 1
    @test get_position_at(doc, 1) == (0, 1)
    @test get_offset(doc, 0, 2) == 4
    @test get_position_at(doc, 4) == (0, 2)
    @test get_offset(doc, 0, 3) == 7
    @test get_position_at(doc, 7) == (0, 3)

    doc = Document("", "𐐀𐐀𐐀", false)
    @test sizeof(get_text(doc)) == 12
    @test get_offset(doc, 0, 0) == 0
    @test get_position_at(doc, 0) == (0, 0)
    @test get_offset(doc, 0, 2) == 1
    @test get_position_at(doc, 1) == (0, 2)
    @test get_offset(doc, 0, 4) == 5
    @test get_position_at(doc, 5) == (0, 4)
    @test get_offset(doc, 0, 6) == 9
    @test get_position_at(doc, 9) == (0, 6)
    
    doc = Document("", "𐀀𐀀𐀀", false) # 0x010000
    @test sizeof(get_text(doc)) == 12
    @test get_offset(doc, 0, 0) == 0
    @test get_position_at(doc, 0) == (0, 0)
    @test get_offset(doc, 0, 2) == 1
    @test get_position_at(doc, 1) == (0, 2)
    @test get_offset(doc, 0, 4) == 5
    @test get_position_at(doc, 5) == (0, 4)
    @test get_offset(doc, 0, 6) == 9
    @test get_position_at(doc, 9) == (0, 6) 
end
