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
    ts = collect(SemanticToken, every_semantic_token(d))
    return semantic_tokens(ts)
end

function expr_offset_to_maybe_token(ex::EXPR, offset::Integer, document::Document)::Union{Nothing,SemanticToken}
    kind = semantic_token_kind(ex)
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
    line, char = get_position_from_offset(document, offset)
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
    document::Document
end
ExpressionVisitorState(d::Document) = ExpressionVisitorState(SemanticToken[], d)

function visit_every_expression_with_offset(expr_in::EXPR, state::ExpressionVisitorState, offset::Integer=0)::Nothing
    for e ∈ expr_in
        # ( maybe ) collect this expression
        maybe_token = expr_offset_to_maybe_token(e, offset, state.document)
        if maybe_token !== nothing
            push!(state.collected_tokens, maybe_token)
        end

        # recurse into e's subtrees
        if !isempty(e)
            visit_every_expression_with_offset(e, state, offset)
        end
        offset += e.fullspan
    end
end

function every_semantic_token(document::Document)
    root_expr = getcst(document)
    state = ExpressionVisitorState(document)
    visit_every_expression_with_offset(root_expr, state)
    state.collected_tokens
end


"""
Get the semantic token kind for `expr`, which is assumed to be an identifier

See CSTParser.jl/src/interface.jl
"""
function semantic_token_kind(expr::EXPR)::Union{String,Nothing}

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
