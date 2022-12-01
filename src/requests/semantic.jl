const C = CSTParser

struct SemanticToken
    # token line number, relative to the previous token
    deltaLine::UInt32
    # token start character, relative to the previous token
    # (relative to 0 or the previous token’s start if they are on the same line)
    deltaStart::UInt32
    # the length of the token.
    length::UInt32
    # will be looked up in SemanticTokensLegend.tokenTypes
    tokenType::UInt32
    # each set bit will be looked up in SemanticTokensLegend.tokenModifiers
    tokenModifiers::UInt32
end

function SemanticToken(deltaLine::UInt32,
    deltaStart::UInt32,
    length::UInt32,
    tokenType::String,
    tokenModifiers::String)
    # FIXME look up int encodings for tokenType and tokenModifiers
    SemanticToken(
        deltaLine,
        deltaStart,
        length,
        semantic_token_encoding(tokenType),
        0 # FIXME look up int encodings for tokenType and tokenModifiers
    )
end

function semantic_tokens(tokens)::SemanticTokens
    token_data_size = length(tokens) * 5
    token_data = Vector{UInt32}(undef, token_data_size)
    for (i_token, token::SemanticToken) ∈ zip(1:5:token_data_size, tokens)
        token_data[i_token:i_token+4] = [
            token.deltaLine,
            token.deltaStart,
            token.length,
            token.tokenType,
            token.tokenModifiers
        ]
    end
    SemanticTokens(token_data)
end

function textDocument_semanticTokens_full_request(params::SemanticTokensParams,
    server::LanguageServerInstance, _)::Union{SemanticTokens,Nothing}
    uri = params.textDocument.uri
    d = getdocument(server, uri)

    external_env = getenv(d, server)

    ts = collect(SemanticToken, every_semantic_token(d, external_env))
    return semantic_tokens(ts)
end

function maybe_get_token_from_expr_with_state(ex::EXPR, state::ExpressionVisitorState)::Union{Nothing,SemanticToken}
    kind = semantic_token_kind(ex, state.external_env)
    if kind === nothing
        return nothing
    end
    name = C.get_name(ex)
    name_offset = 0
    # get the offset of the name expr
    if name !== nothing
        found = false
        for x in ex
            if x == name
                found = true
                break
            end
            name_offset += x.fullspan
        end
        if !found
            name_offset = -1
        end
    end
    line, char = get_position_from_offset(state.document, state.offset)
    return SemanticToken(
        line,
        char,
        ex.span,
        semantic_token_encoding(kind),
        0
    )
end

mutable struct ExpressionVisitorState
    collected_tokens::Vector{SemanticToken}
    # current offset per EXPR::fullspan (starts at 0)
    offset::Integer
    # access to positioning (used with offset)
    document::Document
    # read-only
    external_env::StaticLint.ExternalEnv
end
ExpressionVisitorState(args...) = ExpressionVisitorState(SemanticToken[], 0, args...)

"""

Update state's offset with each-of expr_in's fullspan after visiting them
"""
function visit_every_expression(expr_in::EXPR, state::ExpressionVisitorState)::Nothing
    for e ∈ expr_in
        # ( maybe ) collect this expression
        maybe_token = maybe_get_token_from_expr_with_state(e, state)
        if maybe_token !== nothing
            push!(state.collected_tokens, maybe_token)
        end

        # recurse into e's subtrees
        if !isempty(e)
            visit_every_expression(e, state)
        end
        state.offset += e.fullspan
    end
end

function every_semantic_token(document::Document, external_env::StaticLint.ExternalEnv)
    root_expr = getcst(document)
    state = ExpressionVisitorState(document, external_env)
    visit_every_expression(root_expr, state)
    state.collected_tokens
end


"""
Get the semantic token kind for `expr`, which is assumed to be an identifier

See CSTParser.jl/src/interface.jl
"""
function semantic_token_kind(expr::EXPR, external_env::StaticLint.ExternalEnv)::Union{String,Nothing}
    # TODO felipe use external_env

    return if C.isidentifier(expr)
        SemanticTokenKinds.Variable
    elseif C.isoperator(expr)
        SemanticTokenKinds.Operator
    elseif C.isstringliteral(expr) || C.isstring(expr)
        SemanticTokenKinds.String
    elseif C.iskeyword(expr)
        SemanticTokenKinds.Keyword
    elseif C.defines_function(expr)
        SemanticTokenKinds.Function
    elseif C.defines_struct(expr)
        SemanticTokenKinds.Struct
    elseif C.defines_macro(expr)
        SemanticTokenKinds.Macro
    elseif C.isnumber(expr)
        SemanticTokenKinds.Number
    end
end
