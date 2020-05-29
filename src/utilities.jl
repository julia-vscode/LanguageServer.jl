function uri2filepath(uri::AbstractString)
    parsed_uri = try
        URIParser.URI(uri)
    catch err
        throw(LSUriConversionFailure("Cannot parse `$uri`."))
    end

    if parsed_uri.scheme !== "file"
        return nothing
    end

    path_unescaped = URIParser.unescape(parsed_uri.path)
    host_unescaped = URIParser.unescape(parsed_uri.host)

    value = ""

    if host_unescaped != "" && length(path_unescaped) > 1
        # unc path: file://shares/c$/far/boo
        value = "//$host_unescaped$path_unescaped"
    elseif length(path_unescaped) >= 3 &&
            path_unescaped[1] == '/' &&
            isascii(path_unescaped[2]) && isletter(path_unescaped[2]) &&
            path_unescaped[3] == ':'
        # windows drive letter: file:///c:/far/boo
        value = lowercase(path_unescaped[2]) * path_unescaped[3:end]
    else
        # other path
        value = path_unescaped
    end

    if Sys.iswindows()
        value = replace(value, '/' => '\\')
    end

    value = normpath(value)

    return value
end

function filepath2uri(file::String)
    isabspath(file) || throw(LSRelativePath("Relative path `$file` is not valid."))
    if Sys.iswindows()
        file = normpath(file)
        file = replace(file, "\\" => "/")
        file = URIParser.escape(file)
        file = replace(file, "%2F" => "/")
        if startswith(file, "//")
            # UNC path \\foo\bar\foobar
            return string("file://", file[3:end])
        else
            # windows drive letter path
            return string("file:///", file)
        end
    else
        file = normpath(file)
        file = URIParser.escape(file)
        file = replace(file, "%2F" => "/")
        return string("file://", file)
    end
end

function escape_uri(uri::AbstractString)
    if !startswith(uri, "file://") # escaping only file URI
        return uri
    end
    escaped_uri = uri[8:end] |> URIParser.unescape |> URIParser.escape
    return string("file://", replace(escaped_uri, "%2F" => "/"))
end

function should_file_be_linted(uri, server)
    !server.runlinter && return false

    uri_path = uri2filepath(uri)

    if length(server.workspaceFolders) == 0 || uri_path === nothing
        return false
    else
        return any(i->startswith(uri_path, i), server.workspaceFolders)
    end
end

# CompletionItemKind(t) = t in [:String, :AbstractString] ? 1 :
#                                 t == :Function ? 3 :
#                                 t == :DataType ? 7 :
#                                 t == :Module ? 9 : 6

# SymbolKind(t) = t in [:String, :AbstractString] ? 15 :
#                         t == :Function ? 12 :
#                         t == :DataType ? 5 :
#                         t == :Module ? 2 :
#                         t == :Bool ? 17 : 13




# Find location of default datatype constructor
const DefaultTypeConstructorLoc = let def = first(methods(Int))
    Base.find_source_file(string(def.file)), def.line
end

# TODO I believe this will also remove files from documents that were added
# not because they are part of the workspace, but by either StaticLint or
# the include follow logic.
function remove_workspace_files(root, server)
    for (uri, doc) in getdocuments_pair(server)
        fpath = getpath(doc)
        isempty(fpath) && continue
        get_open_in_editor(doc) && continue
        for folder in server.workspaceFolders
            if startswith(fpath, folder)
                continue
            end
            deletedocument!(server, uri)
        end
    end
end


function Base.getindex(server::LanguageServerInstance, r::Regex)
    out = []
    for (uri, doc) in getdocuments_pair(server)
        occursin(r, uri._uri) && push!(out, doc)
    end
    return out
end

function _offset_unitrange(r::UnitRange{Int}, first = true)
    return r.start - 1:r.stop
end

function get_toks(doc, offset)
    ts = CSTParser.Tokenize.tokenize(get_text(doc))
    ppt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0, 0), (0, 0), 1, 0, CSTParser.Tokens.NO_ERR, false, false)
    pt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0, 0), (0, 0), 1, 0, CSTParser.Tokens.NO_ERR, false, false)
    t = CSTParser.Tokenize.Lexers.next_token(ts)

    while t.kind != CSTParser.Tokenize.Tokens.ENDMARKER
        if t.startbyte < offset <= t.endbyte + 1
            break
        end
        ppt = pt
        pt = t
        t = CSTParser.Tokenize.Lexers.next_token(ts)
    end
    return ppt, pt, t
end

function isvalidjlfile(path)
    endswith(path, ".jl")
end

function get_expr(x, offset, pos = 0, ignorewhitespace = false)
    if pos > offset
        return nothing
    end
    if x.args !== nothing && typof(x) !== CSTParser.NONSTDIDENTIFIER
        for a in x.args
            if pos < offset <= (pos + a.fullspan)
                return get_expr(a, offset, pos, ignorewhitespace)
            end
            pos += a.fullspan
        end
    elseif pos == 0
        return x
    elseif (pos < offset <= (pos + x.fullspan))
        ignorewhitespace && pos + x.span < offset && return nothing
        return x
    end
end

function get_expr(x, offset::UnitRange{Int}, pos = 0, ignorewhitespace = false)
    if all(pos .> offset)
        return nothing
    end
    if x.args !== nothing && typof(x) !== CSTParser.NONSTDIDENTIFIER
        for a in x.args
            if all(pos .< offset .<= (pos + a.fullspan))
                return get_expr(a, offset, pos, ignorewhitespace)
            end
            pos += a.fullspan
        end
    elseif pos == 0
        return x
    elseif all(pos .< offset .<= (pos + x.fullspan))
        ignorewhitespace && all(pos + x.span .< offset) && return nothing
        return x
    end
    pos -= x.fullspan
    if all(pos .< offset .<= (pos + x.fullspan))
        ignorewhitespace && all(pos + x.span .< offset) && return nothing
        return x
    end
end

function get_expr1(x, offset, pos = 0)
    if x.args === nothing || isempty(x.args) || typof(x) === CSTParser.NONSTDIDENTIFIER
        if pos <= offset <= pos + x.span
            return x
        else
            return nothing
        end
    else
        for i = 1:length(x.args)
            arg = x.args[i]
            if pos < offset < (pos + arg.span) # def within span
                return get_expr1(arg, offset, pos)
            elseif arg.span == arg.fullspan
                if offset == pos
                    if i == 1
                        return get_expr1(arg, offset, pos)
                    elseif CSTParser.typof(x.args[i - 1]) === CSTParser.IDENTIFIER
                        return get_expr1(x.args[i - 1], offset, pos)
                    else
                        return get_expr1(arg, offset, pos)
                    end
                elseif i == length(x.args) # offset == pos + arg.fullspan
                    return get_expr1(arg, offset, pos)
                end
            else
                if offset == pos
                    if i == 1
                        return get_expr1(arg, offset, pos)
                    elseif CSTParser.typof(x.args[i - 1]) === CSTParser.IDENTIFIER
                        return get_expr1(x.args[i - 1], offset, pos)
                    else
                        return get_expr1(arg, offset, pos)
                    end
                elseif offset == pos + arg.span
                    return get_expr1(arg, offset, pos)
                elseif offset == pos + arg.fullspan
                elseif pos + arg.span < offset < pos + arg.fullspan
                    return nothing
                end
            end
            pos += arg.fullspan
        end
        return nothing
    end
end


function get_identifier(x, offset, pos = 0)
    if pos > offset
        return nothing
    end
    if x.args !== nothing
        for a in x.args
            if pos <= offset <= (pos + a.span)
                return get_identifier(a, offset, pos)
            end
            pos += a.fullspan
        end
    elseif typof(x) === CSTParser.IDENTIFIER && (pos <= offset <= (pos + x.span)) || pos == 0
        return x
    end
end

@static if Sys.iswindows() && VERSION < v"1.3"
    function _splitdir_nodrive(a::String, b::String)
        m = match(r"^(.*?)([/\\]+)([^/\\]*)$", b)
        m === nothing && return (a, b)
        a = string(a, isempty(m.captures[1]) ? m.captures[2][1] : m.captures[1])
        a, String(m.captures[3])
    end
    function _dirname(path::String)
        m = match(r"^([^\\]+:|\\\\[^\\]+\\[^\\]+|\\\\\?\\UNC\\[^\\]+\\[^\\]+|\\\\\?\\[^\\]+:|)(.*)$"s, path)
        a, b = String(m.captures[1]), String(m.captures[2])
        _splitdir_nodrive(a, b)[1]
    end
    function _splitdrive(path::String)
        m = match(r"^([^\\]+:|\\\\[^\\]+\\[^\\]+|\\\\\?\\UNC\\[^\\]+\\[^\\]+|\\\\\?\\[^\\]+:|)(.*)$"s, path)
        String(m.captures[1]), String(m.captures[2])
    end
    function _splitdir(path::String)
        a, b = _splitdrive(path)
        _splitdir_nodrive(a, b)
    end
else
    _dirname = dirname
    _splitdir = splitdir
end

function valid_id(s::String)
    !isempty(s) && all(i == 1 ? Base.is_id_start_char(c) : Base.is_id_char(c) for (i, c) in enumerate(s))
end

function sanitize_docstring(doc::String)
    doc = replace(doc, "```jldoctest" => "```julia")
    doc = replace(doc, "\n#" => "\n###")
    return doc
end

function parent_file(x::EXPR)
    if parentof(x) isa EXPR
        return parent_file(parentof(x))
    elseif parentof(x) === nothing && StaticLint.haserror(x) && StaticLint.errorof(x) isa Document
        return x.meta.error
    else
        return nothing
    end
end

function resolve_op_ref(x::EXPR)
    StaticLint.hasref(x) && return true
    typof(x) !== CSTParser.OPERATOR && return false
    pf = parent_file(x)
    pf === nothing && return false
    scope = StaticLint.retrieve_scope(x)
    scope === nothing && return false

    mn = CSTParser.str_value(x)
    while scope isa StaticLint.Scope
        if StaticLint.scopehasbinding(scope, mn)
            StaticLint.setref!(x, scope.names[mn])
            return true
        elseif scope.modules isa Dict && length(scope.modules) > 0
            for (_, m) in scope.modules
                if m isa SymbolServer.ModuleStore && StaticLint.isexportedby(Symbol(mn), m)
                    StaticLint.setref!(x, m[Symbol(mn)])
                    return true
                elseif m isa StaticLint.Scope && StaticLint.scopehasbinding(m, mn)
                    StaticLint.setref!(x, m.names[mn])
                    return true
                end
            end
        end
        CSTParser.defines_module(scope.expr) && return false
        scope = StaticLint.parentof(scope)
    end
end
