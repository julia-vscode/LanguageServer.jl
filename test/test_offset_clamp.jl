@testitem "Range conversion clamps out-of-bounds offsets and warns" begin
    import JuliaWorkspaces, Logging
    using JuliaWorkspaces: SourceText
    using LanguageServer: Range, get_position_from_offset

    content = "abc\ndef\n"   # 8 bytes
    st = SourceText(content, "julia")
    n = sizeof(content)

    # In-bounds range converts normally, with no warning.
    r_ok = @test_logs min_level = Logging.Warn Range(st, 1:4)
    @test r_ok isa Range

    # A stale range whose exclusive end is past EOF (e.g. diagnostics lagging a
    # content edit): the start offset first(rng)-1 = 9 exceeds sizeof = 8. It
    # must clamp to the document end and warn, not throw and fail the request.
    r = @test_logs (:warn,) match_mode = :any Range(st, 10:9)
    @test r isa Range

    eof_line, eof_char = get_position_from_offset(st, n)
    @test (r.start.line, r.start.character) == (eof_line, eof_char)
end
