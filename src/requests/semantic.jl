# import Iterators.flatten
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
    # TODO look up int encodings for tokenType and tokenModifiers
    SemanticToken(
        deltaLine,
        deltaStart,
        length,
        semantic_token_encoding(tokenType),
        0 # TODO
    )
end

# function SemanticToken(ex::EXPR)

# end


function SemanticTokens(tokens::Vector{SemanticToken}) :: SemanticTokens
    token_vectors = map(tokens) do token
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
                                                  server::LanguageServerInstance, conn) :: Union{SemanticTokens,Nothing}
    uri = params.textDocument.uri
    doc = getdocument(server, URI2(uri))
    # return nothing
    ts = collect_semantic_tokens(getcst(doc), doc)
    return SemanticTokens(ts)
    # return collect_document_symbols(getcst(doc), server, doc)

    # doc = getdocument(server, URI2(params.textDocument.uri))
    # offset = get_offset(doc, params.position)
    # identifier = get_identifier(getcst(doc), offset)
    # identifier !== nothing || return nothing
    # highlights = DocumentHighlight[]
    # for_each_ref(identifier) do ref, doc1, o
    #     if doc1._uri == doc._uri
    #         kind = StaticLint.hasbinding(ref) ? DocumentHighlightKinds.Write : DocumentHighlightKinds.Read
    #         push!(highlights, DocumentHighlight(Range(doc, o .+ (0:ref.span)), kind))
    #     end
    # end
    # return isempty(highlights) ? nothing : highlights
end
# import CSTParser: 
"""

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
function collect_semantic_tokens(expr::EXPR, doc :: Document, pos=0):: Vector{SemanticToken}
    tokens = SemanticToken[]

    offset = pos
    for ex in expr
        # if isempty(ex)
            # leaf of parse tree
            
		# C.isidentifier(ex)
		kind = semantic_token_kind(ex)
		if kind !== nothing
            @info "Expression" ex kind
            # identifier, identifier_pos = get_identifier_pos(ex, 0, 0)
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
            @info "name" name name_offset
			line, char = get_position_at(doc, offset)
			# add this token 
			token = SemanticToken(
				line,
				char,
				ex.span,
				semantic_token_encoding(kind),
				0
			)
			push!(tokens, token)
		end
        if !isempty(ex)
            # there are more nodes on this tree
            sub_tokens = collect_semantic_tokens(ex, doc, offset)
            push!(tokens, sub_tokens...)
        end
        offset += ex.fullspan
    end
    return tokens
    # return collect_semantic_tokens(ex)
    # @info get_toks(doc, 0) 
end

"""
Get the semantic token kind for `expr`, which is assumed to be an identifier
"""
function semantic_token_kind(expr::EXPR) :: Union{String, Nothing}
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
# function collect_semantic_tokens(ex::EXPR, pos=0) :: Vector{SemanticToken}
#     tokens = SemanticToken[]

#     @info "expr.head = $(ex.head)"
#     token_kind = if C.defines_function(ex) || C.is_func_call(ex)
#         SemanticTokenKinds.Function
#     elseif C.defines_struct(ex)
#         SemanticTokenKinds.Struct
#     elseif C.defines_macro(ex)
#         SemanticTokenKinds.Macro
#     elseif C.isoperator(ex)
#         SemanticTokenKinds.Operator
#     end
#     @info token_kind
    
#     if token_kind !== nothing
#         token = SemanticToken(
#             0,
#             pos,
#             ex.span,
#             semantic_token_encoding(token_kind),
#             0
#         )
#         push!(tokens, token)
#     end
#     pos = pos + span(tokens)

#     if ex.args !== nothing
         # sub_tokens = map(ex.args) do arg
         #     collect_semantic_tokens(arg, pos)
         # end |> Iterators.flatten |> collect
         # pos = pos + span(sub_tokens)
         # push!(tokens, sub_tokens...)
#     end
    
#     return tokens
# end


span(token :: SemanticToken) = token.length
function span(tokens :: Vector{SemanticToken})
    lengths = map(tokens) do token
        token.length
    end
    
    reduce(+, lengths)
end
