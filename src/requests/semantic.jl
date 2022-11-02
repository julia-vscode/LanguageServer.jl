function textDocument_semanticTokens_request(params::SemanticTokensParams, server::LanguageServerInstance, conn)
    doc = getdocument(server, URI2(params.textDocument.uri))
    offset = get_offset(doc, params.position)
    identifier = get_identifier(getcst(doc), offset)
    identifier !== nothing || return nothing
    highlights = DocumentHighlight[]
    for_each_ref(identifier) do ref, doc1, o
        if doc1._uri == doc._uri
            kind = StaticLint.hasbinding(ref) ? DocumentHighlightKinds.Write : DocumentHighlightKinds.Read
            push!(highlights, DocumentHighlight(Range(doc, o .+ (0:ref.span)), kind))
        end
    end
    return isempty(highlights) ? nothing : highlights
end

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
    token_vectors = map(tokens) do token::SemanticToken
        # token_index = i - 1
        [
            token.deltaLine,
            token.deltaStart,
            token.length,
            token.tokenType,
            token.tokenModifiers
        ]
    end
    SemanticTokens(Iterators.flatten(token_vectors) |> collect)
end

function textDocument_semanticTokens_full_request(params::SemanticTokensParams,
    server::LanguageServerInstance, conn)::Union{SemanticTokens,Nothing}
    uri = params.textDocument.uri
    doc = getdocument(server, URI2(uri))
    ts = collect(every_semantic_token(doc))
    return semantic_tokens(ts)
end

@doc """
Iterator interface for providing tokens from a Document

parse applies these types
 Parser.SyntaxNode
  Parser.EXPR
  Parser.INSTANCE
    Parser.HEAD{K}
    Parser.IDENTIFIER
    Parser.KEYWORD{K}
    Parser.LITERAL{K}
    Parser.OPERATOR{P,K,dot}
    Parser.PUNCTUATION
  Parser.QUOTENODE

┌ Info:   1:60  file(  new scope lint )
│   1:60   function(  Binding(main:: (1 refs)) new scope)
│   1:8     call( )
│   1:4      main *
│   9:48    block( )
│   9:28       1:2   OP: =( )
│   9:10      s Binding(s:: (3 refs)) *
│  11:26      STRING: hello world!
│  29:40     call( )
│  29:35      println *
│  36:36      s *
│  41:48     macrocall( )
│  41:46      @show *
│  47:46      NOTHING: nothing
└  47:48      s *
 """
function expression_to_maybe_token(ex::EXPR, offset)
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
    line, char = get_offset(doc, offset)
    return SemanticToken(
        line,
        char,
        ex.span,
        semantic_token_encoding(kind),
        0
    )
end
function every_expression_with_offset(expr::EXPR, offset=0)
    every_expression = Tuple{EXPR,Int64}[]
    for ex in expr
        push!((ex, offset), every_expression)
        if !isempty(ex)
            push!((ex, offset), every_expression_with_offset(ex, offset)...)
        end
        offset += ex.fullspan
    end
end
function expr_offset_to_maybe_token(ex::EXPR, offset::Int64, doc)
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
    line, char = get_offset(doc, offset)
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
    maybe_tokens = map(expr_offset_to_maybe_token,
        map((ex, offset) -> (ex, offset, doc),
            every_expression_with_offset(root_expr)))
    filter(maybe_token -> maybe_token !== nothing, maybe_tokens)
end


"""
Get the semantic token kind for `expr`, which is assumed to be an identifier
"""
function semantic_token_kind(expr::EXPR)::Union{String,Nothing}
    # C.isidentifier(expr) || return nothing
    return if C.defines_function(expr)# || C.is_func_call(expr)
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
