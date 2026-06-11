@testitem "MarkedString hash uses the two-arg method (#1381)" begin
    ms(s) = LanguageServer.MarkedString("julia", s)

    # The hash protocol requires the two-arg `hash(x, h::UInt)`. A stray one-arg
    # `Base.hash(x)` made `hash(x)` and `hash(x, zero(UInt))` disagree, breaking
    # hashing in Dicts/unique. They must now be consistent and value-based.
    @test hash(ms("x")) == hash(ms("x"), zero(UInt))
    @test hash(ms("x")) == hash(ms("x"))
    @test hash(ms("x"), UInt(7)) == hash(ms("x"), UInt(7))

    # Equal-valued MarkedStrings deduplicate via `unique`.
    @test length(unique([ms("x"), ms("x"), ms("y")])) == 2
end
