# https://microsoft.github.io/language-server-protocol/specifications/specification-3-17/#textDocument_semanticTokens
const SemanticTokenKind = String
const SemanticTokenKinds = (
    # Namespace = "namespace",
    # Type = "type",
    # Class = "class",
    # Enum = "enum",
    # Interface = "interface",
	Struct = "struct",
	TypeParameter = "typeParameter",
	Parameter = "parameter",
	Variable = "variable",
	Property = "property",
	# EnumMember = "enumMember",
	# Event = "event",
	Function = "function",
	# Method = "method",
	Macro = "macro",
	Keyword = "keyword",
	# Modifier = "modifier",
	Comment = "comment",
	String = "string",
	Number = "number",
	Regexp = "regexp",
	Operator = "operator"
)

const SemanticTokenModifiersKind = String
const SemanticTokenModifiersKinds = (
    Declaration = "declaration",
	Definition = "definition",
	# Readonly = "readonly",
	# Static = "static",
	# Deprecated = "deprecated",
	# Abstract = "abstract",
	# Async = "async",
	Modification = "modification",
	Documentation = "documentation",
	DefaultLibrary = "defaultLibrary"

)


struct SemanticTokensLegend <: Outbound
	# /**
	#  * The token types a server uses.
	#  */
	tokenTypes::Vector{String}

	# /**
	#  * The token modifiers a server uses.
	#  */
	tokenModifiers::Vector{String}
end

const JuliaSemanticTokensLegend = SemanticTokensLegend(
		collect(values(SemanticTokenKinds)),
		collect(values(SemanticTokenModifiersKinds))
)

function semantic_token_encoding(token :: String) :: UInt32
	for (i, type) in enumerate(JuliaSemanticTokensLegend.tokenTypes)
		if token == type
			return i - 1 # -1 to shift to 0-based indexing
		end
	end
end
# function SemanticTokensLegend() :: SemanticTokensLegend
# 	SemanticTokensLegend(
# 	)
# end
# const Tok

@dict_readable struct SemanticTokensFullDelta <: Outbound
    delta::Union{Bool,Missing}
end

@dict_readable struct SemanticTokensClientCapabilitiesRequests <: Outbound
    range::Union{Bool,Missing}
    full::Union{Bool,Missing,SemanticTokensFullDelta}

end
@dict_readable struct SemanticTokensClientCapabilities <: Outbound
    dynamicRegistration::Union{Bool,Missing}
    tokenTypes::Vector{String}
    tokenModifiers::Vector{String}
    formats::Vector{String}
    overlappingTokenSupport::Union{Bool,Missing}
    multilineTokenSupport::Union{Bool,Missing}
end

struct SemanticTokensOptions <: Outbound
	legend::SemanticTokensLegend
	range::Union{Bool,Missing}
	full::Union{Bool,SemanticTokensFullDelta,Missing}
end

struct SemanticTokensRegistrationOptions <: Outbound
    documentSelector::Union{DocumentSelector,Nothing}
    # workDoneProgress::Union{Bool,Missing}
end

@dict_readable struct SemanticTokensParams <: Outbound
    textDocument::TextDocumentIdentifier
    # position::Position
    workDoneToken::Union{Int,String,Missing} # ProgressToken
    partialResultToken::Union{Int,String,Missing} # ProgressToken
end

struct SemanticTokens <: Outbound
    resultId::Union{String,Missing}
    data::Vector{UInt32}
end

SemanticTokens(data::Vector{UInt32}) = SemanticTokens(missing, data)



struct SemanticTokensPartialResult <: Outbound
    data::Vector{UInt32}
end

struct SemanticTokensDeltaParams <: Outbound
	workDoneToken::Union{Int,String,Missing}
    partialResultToken::Union{Int,String,Missing} # ProgressToken
    textDocument::TextDocumentIdentifier
	previousResultId::String
end
struct SemanticTokensEdit <: Outbound
	start::UInt32
	deleteCount::Int
	data::Union{Vector{Int},Missing}
end
struct SemanticTokensDelta <: Outbound
	resultId::Union{String,Missing}
	edits::Vector{SemanticTokensEdit}
end

struct SemanticTokensDeltaPartialResult <: Outbound
	edits::Vector{SemanticTokensEdit}
end

struct SemanticTokensRangeParams <: Outbound
	workDoneToken::Union{Int,String,Missing}
    partialResultToken::Union{Int,String,Missing} # ProgressToken
    textDocument::TextDocumentIdentifier
	range::Range
end

struct SemanticTokensWorkspaceClientCapabilities <: Outbound
	refreshSupport::Union{Bool,Missing}
end	