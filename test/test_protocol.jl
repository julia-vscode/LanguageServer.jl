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

@testitem "ProgressToken fields accept Int64 tokens on 32-bit Julia" begin
    # The JSON parser returns Int64 for every integer. On 32-bit Julia `Int` is Int32, and
    # `convert(Union{Int32,String,Missing}, ::Int64)` has no method, so a client sending a
    # numeric `workDoneToken` killed the server there. Build the params from a Dict as
    # `JSONRPC.dispatch_msg` does; this only fails on the ~x86 CI legs.
    pos = Dict{String,Any}(
        "textDocument" => Dict{String,Any}("uri" => "file:///a.jl"),
        "position" => Dict{String,Any}("line" => 0, "character" => 0),
        "context" => Dict{String,Any}("includeDeclaration" => true),
    )
    for token in (Int64(1), "abc")
        p = LanguageServer.ReferenceParams(merge(pos, Dict{String,Any}("workDoneToken" => token, "partialResultToken" => token)))
        @test p.workDoneToken === token
        @test p.partialResultToken === token

        p = LanguageServer.WorkspaceSymbolParams(Dict{String,Any}("query" => "x", "partialResultToken" => token))
        @test p.partialResultToken === token

        p = LanguageServer.WorkDoneProgressCancelParams(Dict{String,Any}("token" => token))
        @test p.token === token

        p = LanguageServer.InitializeParams(Dict{String,Any}("processId" => nothing, "rootUri" => nothing, "capabilities" => Dict{String,Any}(), "workDoneToken" => token))
        @test p.workDoneToken === token
    end
end

@testitem "No Dict-readable protocol field puts a 32-bit Int in a union" begin
    # Guards against new `Union{Int,String...}` fields. On 64-bit `Int === Int64` and this
    # passes trivially; on the ~x86 CI legs it flags any field that a Dict-built JSON Int64
    # could not be converted into. `Union{Int,Missing}` and `Union{Int,Nothing}` are fine,
    # Julia converts those through the non-missing type.
    function bad_union(T)
        T isa Union || return false
        members = filter(t -> t !== Missing && t !== Nothing, Base.uniontypes(T))
        any(t -> t <: Signed && t !== Int64, members) && any(t -> !(t <: Integer), members)
    end
    # A constructor with an explicit Dict argument (`@dict_readable` or handwritten). The
    # default constructor of a one-field struct also accepts a Dict, so `hasmethod` is too
    # broad; outbound-only fields built from `Int` literals must stay `Int`.
    function reads_dict(T)
        any(methods(T)) do m
            sig = Base.unwrap_unionall(m.sig)
            length(sig.parameters) == 2 && sig.parameters[2] !== Any && Dict{String,Any} <: sig.parameters[2]
        end
    end
    bad = String[]
    checked = Symbol[]
    for name in names(LanguageServer; all=true)
        isdefined(LanguageServer, name) || continue
        T = getfield(LanguageServer, name)
        T isa DataType && isstructtype(T) && parentmodule(T) === LanguageServer || continue
        reads_dict(T) || continue
        push!(checked, name)
        for (fn, ft) in zip(fieldnames(T), fieldtypes(T))
            bad_union(ft) && push!(bad, "$name.$fn::$ft")
        end
    end
    @test :ReferenceParams in checked
    @test :InitializeParams in checked
    @test !(:ServerCapabilities in checked)
    @test isempty(bad)
end
