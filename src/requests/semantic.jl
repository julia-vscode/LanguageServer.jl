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
    doc = getdocument(server, uri)
    ts = collect(SemanticToken, every_semantic_token(doc))
    return semantic_tokens(ts)
end

function every_expression_with_offset(expr::EXPR, offset=0)
    every_expression = Tuple{EXPR,Int64}[]
    for ex in expr
        push!(every_expression, (ex, offset))
        if !isempty(ex)
            sub_expressions = every_expression_with_offset(ex, offset)
            push!(every_expression, sub_expressions...)
        end
        offset += ex.fullspan
    end
    every_expression
end

function expr_offset_to_maybe_token(ex::EXPR, offset::Int64, doc)::Union{Nothing,SemanticToken}
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
    line, char = get_position_from_offset(doc, offset)
    return SemanticToken(
        line,
        char,
        ex.span,
        semantic_token_encoding(kind),
        0
    )
end

function every_semantic_token(doc)
    root_expr = getcst(doc)
    expressions_with_offsets = every_expression_with_offset(root_expr)
    maybe_tokens = map(_tuple -> begin
            ex::EXPR, offset::Int64 = _tuple
            expr_offset_to_maybe_token(ex, offset, doc)
        end, expressions_with_offsets)
    filter(maybe_token -> maybe_token !== nothing, maybe_tokens)
end


"""
Get the semantic token kind for `expr`, which is assumed to be an identifier

See CSTParser.jl/src/interface.jl
"""
function semantic_token_kind(expr::EXPR)::Union{String,Nothing}
    # C.isidentifier(expr) || return nothing

    return if C.isidentifier(expr)
        SemanticTokenKinds.Variable
    elseif C.isoperator(expr)
        SemanticTokenKinds.Operator
    elseif C.isstringliteral(expr) || C.isstring(expr)
        SemanticTokenKinds.String
    elseif C.iskeyword(expr)
        SemanticTokenKinds.Keyword
    elseif C.defines_function(expr) # || C.is_func_call(expr)
        SemanticTokenKinds.Function
    elseif C.defines_struct(expr)
        SemanticTokenKinds.Struct
    elseif C.defines_macro(expr)
        SemanticTokenKinds.Macro
        # elseif C.isoperator(expr)
        # SemanticTokenKinds.Operator
    end
end
const C = CSTParser

span(token::SemanticToken) = token.length
function span(tokens::Vector{SemanticToken})
    lengths = map(tokens) do token
        token.length
    end

    reduce(+, lengths)
end
