@testitem "MarkedString hash uses the two-arg method (#1381)" begin
    ms(s) = LanguageServer.MarkedString("julia", s)

    # The hash protocol requires the two-arg `hash(x, h::UInt)`. #1381 was a stray one-arg
    # `Base.hash(x::MarkedString)`, which made hashing identity-based and broke Dicts and
    # `unique`. Assert that method is absent rather than comparing `hash(x)` against
    # `hash(x, zero(UInt))`: Julia 1.13 stopped defining the generic one-arg `hash(x)` as
    # `hash(x, zero(UInt))`, so that comparison is now false for every type, `Int` included,
    # and says nothing about MarkedString.
    @test which(hash, Tuple{LanguageServer.MarkedString}).sig === Tuple{typeof(hash),Any}
    @test hash(ms("x")) == hash(ms("x"))
    @test hash(ms("x"), UInt(7)) == hash(ms("x"), UInt(7))

    # Equal-valued MarkedStrings deduplicate via `unique`.
    @test length(unique([ms("x"), ms("x"), ms("y")])) == 2
end
