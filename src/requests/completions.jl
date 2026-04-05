# Completion request handler — thin wrapper around JuliaWorkspaces completion layer.
# All completion logic now lives in JuliaWorkspaces.layer_completions.jl.

# Re-export is_completion_match so LS code that referenced it still works.
const is_completion_match = JuliaWorkspaces.is_completion_match

function textDocument_completion_request(params::CompletionParams, server::LanguageServerInstance, conn)
    uri = params.textDocument.uri
    st = jw_source_text(server, uri)
    index = index_at(st, params.position)

    result = JuliaWorkspaces.get_completions(server.workspace, uri, index, server.completion_mode)

    # Convert JuliaWorkspaces.CompletionResult → LSP CompletionList
    items = CompletionItem[]
    for item in result.items
        text_edit = _convert_completion_edit(st, item.text_edit, uri, server)
        additional_edits = if isempty(item.additional_edits)
            missing
        else
            [_convert_completion_edit(st, e, uri, server) for e in item.additional_edits]
        end
        doc = item.documentation === nothing ? missing : MarkupContent(item.documentation)
        detail = item.detail === nothing ? missing : item.detail
        label_details = if item.detail_label !== nothing || item.detail_description !== nothing
            CompletionItemLabelDetails(
                item.detail_label === nothing ? missing : item.detail_label,
                item.detail_description === nothing ? missing : item.detail_description
            )
        else
            missing
        end
        sort_text = item.sort_text === nothing ? missing : item.sort_text
        filter_text = item.filter_text === nothing ? missing : item.filter_text
        data = item.data === nothing ? missing : item.data
        push!(items, CompletionItem(
            item.label,
            item.kind,
            missing,        # tags
            detail,
            doc,
            missing,        # deprecated
            missing,        # preselect
            sort_text,
            filter_text,
            missing,        # insertText
            item.insert_text_format,
            text_edit,
            additional_edits,
            missing,        # commitCharacters
            missing,        # command
            data,
            label_details,
        ))
    end
    return CompletionList(result.is_incomplete, items)
end

"""
Convert a JuliaWorkspaces.CompletionEdit (1-based string indices) to an LSP TextEdit (line/char).
"""
function _convert_completion_edit(st::JuliaWorkspaces.SourceText, edit::JuliaWorkspaces.CompletionEdit, current_uri::URI, server)
    # If the edit targets a different file, use that file's SourceText for position conversion
    target_st = if edit.uri !== nothing && edit.uri != current_uri
        jw_source_text(server, edit.uri)
    else
        st
    end
    start_l, start_c = get_position_from_offset(target_st, edit.start_index - 1)
    end_l, end_c = get_position_from_offset(target_st, edit.end_index - 1)
    return TextEdit(Range(start_l, start_c, end_l, end_c), edit.new_text)
end
