const C = CSTParser

# Struct-like version of a semantic token before being flattened into 5-number-pair
struct NonFlattenedSemanticToken
    # token line number
    line::UInt32
    # token start character within line
    start::UInt32
    # the length of the token.
    length::UInt32
    # will be looked up in SemanticTokensLegend.tokenTypes
    tokenType::UInt32
    # each set bit will be looked up in SemanticTokensLegend.tokenModifiers
    tokenModifiers::UInt32
end


"""

Map collection of tokens into SemanticTokens

Note: currently uses absolute position
"""
function semantic_tokens(tokens)::SemanticTokens
    # TODO implement relative position (track last token)
    token_data_size = length(tokens) * 5
    token_data = Vector{UInt32}(undef, token_data_size)
    for (i_token, token::NonFlattenedSemanticToken) ∈ zip(1:5:token_data_size, tokens)
        token_data[i_token:i_token+4] = [
            token.line,
            token.start,
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

    repeated_tokens = collect(NonFlattenedSemanticToken, every_semantic_token(d, external_env))
    sort!(repeated_tokens, lt=(l,r)->begin
              (l.line, l.start) < (r.line, r.start)
          end)
    return semantic_tokens(unique(repeated_tokens))
end

# TODO visit expressions correctly and collect tokens into a Vector, rather than a Set (see visit_every_expression() )
TokenCollection=Set{NonFlattenedSemanticToken}
mutable struct ExpressionVisitorState
    collected_tokens::TokenCollection
    # access to positioning (used with offset, see visit_every_expression() )
    document::Document
    # read-only
    external_env::StaticLint.ExternalEnv
end
ExpressionVisitorState(args...) = ExpressionVisitorState(TokenCollection(), args...)

"""
Adds token to state.collected only if maybe_get_token_from_expr() parsed an actual token
"""
function maybe_collect_token_from_expr(ex::EXPR, state::ExpressionVisitorState, offset::Integer)
    maybe_token = maybe_get_token_from_expr(ex, state, offset)
    if maybe_token !== nothing
        push!(state.collected_tokens, maybe_token)
    end

end

function maybe_get_token_from_expr(ex::EXPR, state::ExpressionVisitorState, offset::Integer)::Union{Nothing,NonFlattenedSemanticToken}
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
    line, char = get_position_from_offset(state.document, offset)
    return NonFlattenedSemanticToken(
                                     line,
                                     char,
                                     ex.span,
                                     semantic_token_encoding(kind),
                                     0)
end


"""

Visit each expression, collecting semantic-tokens into state

Note: couldn't pack offset into ExpressionVisitorState and update, that's why it's a separate argument
TODO: not sure about how to recurse an EXPR and its sub-expressions. For now, that'll be covered by collecting them into a Set
"""
function visit_every_expression(expr_in::EXPR, state::ExpressionVisitorState, offset=0)::Nothing
    maybe_collect_token_from_expr(expr_in, state, offset)

    # recurse into this expression's expressions
    for e ∈ expr_in
        maybe_collect_token_from_expr(e, state, offset)

        visit_every_expression(e, state, offset)

        offset += e.fullspan
    end
end

function every_semantic_token(document::Document, external_env::StaticLint.ExternalEnv)
    root_expr = getcst(document)
    state = ExpressionVisitorState(document, external_env)
    visit_every_expression(root_expr, state)
    collect(state.collected_tokens)
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
