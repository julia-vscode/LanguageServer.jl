# VSCode specific
# ---------------

nodocuemnt_error(uri, data=nothing) =
    return JSONRPC.JSONRPCError(-32099, "document $(uri) requested but not present in the JLS", data)

function mismatched_version_error(uri, doc, params, msg, data=nothing)
    return JSONRPC.JSONRPCError(
        -32099,
        "version mismatch in $(msg) request for $(uri): JLS $(doc._version), client: $(params.version)",
        data
    )
end

# lookup
# ------

traverse_by_name(f, cache = SymbolServer.stdlibs) = traverse_store!.(f, values(cache))

traverse_store!(_, _) = return
traverse_store!(f, store::SymbolServer.EnvStore) = traverse_store!.(f, values(store))
function traverse_store!(f, store::SymbolServer.ModuleStore)
    for (sym, val) in store.vals
        f(sym, val)
        traverse_store!(f, val)
    end
end

# misc
# ----

function uri2filepath(uri::AbstractString)
    parsed_uri = try
        URIParser.URI(uri)
    catch
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
        return any(i -> startswith(uri_path, i), server.workspaceFolders)
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
        # We first check whether the doc still exists on the server
        # because a previous loop iteration could have deleted it
        # via dependency removal of files
        hasdocument(server, uri) || continue
        fpath = getpath(doc)
        isempty(fpath) && continue
        get_open_in_editor(doc) && continue
        # If the file is in any other workspace folder, don't delete it
        any(folder -> startswith(fpath, folder), server.workspaceFolders) && continue
            deletedocument!(server, uri)
        end
    end


function Base.getindex(server::LanguageServerInstance, r::Regex)
    out = []
    for (uri, doc) in getdocuments_pair(server)
        occursin(r, uri._uri) && push!(out, doc)
    end
    return out
end

function _offset_unitrange(r::UnitRange{Int}, first=true)
    return r.start - 1:r.stop
end

function get_toks(doc, offset)
    ts = CSTParser.Tokenize.tokenize(get_text(doc))
    ppt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0, 0), (0, 0), 1, 0, CSTParser.Tokens.NO_ERR, false, false)
    pt = CSTParser.Tokens.RawToken(CSTParser.Tokens.ERROR, (0, 0), (0, 0), 1, 0, CSTParser.Tokens.NO_ERR, false, false)
    t = CSTParser.Tokenize.Lexers.next_token(ts)

    prevpos = -1 # TODO: remove.
    while t.kind != CSTParser.Tokenize.Tokens.ENDMARKER
        if t.startbyte === prevpos # TODO: remove.
            throw(LSInfiniteLoop("Loop did not progress between iterations.")) # TODO: remove.
        else # TODO: remove.
            prevpos = t.startbyte # TODO: remove.
        end # TODO: remove.

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

function get_expr(x, offset, pos=0, ignorewhitespace=false)
    if pos > offset
        return nothing
    end
    if length(x) > 0 && headof(x) !== :NONSTDIDENTIFIER
        for a in x
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

# like get_expr, but only returns a expr if offset is not on the edge of its span
function get_expr_or_parent(x, offset, pos=0)
    if pos > offset
        return nothing, pos
    end
    ppos = pos
    if length(x) > 0 && headof(x) !== :NONSTDIDENTIFIER
        for a in x
            if pos < offset <= (pos + a.fullspan)
                if pos < offset < (pos + a.span)
                    return get_expr_or_parent(a, offset, pos)
                else
                    return x, ppos
                end
            end
            pos += a.fullspan
        end
    elseif pos == 0
        return x, pos
    elseif (pos < offset <= (pos + x.fullspan))
        if pos + x.span < offset
            return x.parent, ppos
        end
        return x, pos
    end
    return nothing, pos
end

function get_expr(x, offset::UnitRange{Int}, pos=0, ignorewhitespace=false)
    if all(pos .> offset)
        return nothing
    end
    if length(x) > 0 && headof(x) !== :NONSTDIDENTIFIER
        for a in x
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

function get_expr1(x, offset, pos=0)
    if length(x) == 0 || headof(x) === :NONSTDIDENTIFIER
        if pos <= offset <= pos + x.span
            return x
        else
            return nothing
        end
    else
        for i = 1:length(x)
            arg = x[i]
            if pos < offset < (pos + arg.span) # def within span
                return get_expr1(arg, offset, pos)
            elseif arg.span == arg.fullspan
                if offset == pos
                    if i == 1
                        return get_expr1(arg, offset, pos)
                    elseif headof(x[i - 1]) === :IDENTIFIER
                        return get_expr1(x[i - 1], offset, pos)
                    else
                        return get_expr1(arg, offset, pos)
                    end
                elseif i == length(x) # offset == pos + arg.fullspan
                    return get_expr1(arg, offset, pos)
                end
            else
                if offset == pos
                    if i == 1
                        return get_expr1(arg, offset, pos)
                    elseif headof(x[i - 1]) === :IDENTIFIER
                        return get_expr1(x[i - 1], offset, pos)
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


function get_identifier(x, offset, pos=0)
    if pos > offset
        return nothing
    end
    if length(x) > 0
        for a in x
            if pos <= offset <= (pos + a.span)
                return get_identifier(a, offset, pos)
            end
            pos += a.fullspan
        end
    elseif headof(x) === :IDENTIFIER && (pos <= offset <= (pos + x.span)) || pos == 0
        return x
    end
end


if VERSION < v"1.1" || Sys.iswindows() && VERSION < v"1.3"
    _splitdir_nodrive(path::String) = _splitdir_nodrive("", path)
    function _splitdir_nodrive(a::String, b::String)
        m = match(Base.Filesystem.path_dir_splitter, b)
        m === nothing && return (a, b)
        a = string(a, isempty(m.captures[1]) ? m.captures[2][1] : m.captures[1])
        a, String(m.captures[3])
    end
    splitpath(p::AbstractString) = splitpath(String(p))

    function splitpath(p::String)
        drive, p = _splitdrive(p)
        out = String[]
        isempty(p) && (pushfirst!(out, p))  # "" means the current directory.
        while !isempty(p)
            dir, base = _splitdir_nodrive(p)
            dir == p && (pushfirst!(out, dir); break)  # Reached root node.
            if !isempty(base)  # Skip trailing '/' in basename
                pushfirst!(out, base)
            end
            p = dir
        end
        if !isempty(drive)  # Tack the drive back on to the first element.
            out[1] = drive * out[1]  # Note that length(out) is always >= 1.
        end
        return out
    end
    _path_separator    = "\\"
    _path_separator_re = r"[/\\]+"
    function _pathsep(paths::AbstractString...)
        for path in paths
            m = match(_path_separator_re, String(path))
            m !== nothing && return m.match[1:1]
        end
        return _path_separator
    end
    function joinpath(a::String, b::String)
        isabspath(b) && return b
        A, a = _splitdrive(a)
        B, b = _splitdrive(b)
        !isempty(B) && A != B && return string(B,b)
        C = isempty(B) ? A : B
        isempty(a)                              ? string(C,b) :
        occursin(_path_separator_re, a[end:end]) ? string(C,a,b) :
                                                  string(C,a,_pathsep(a,b),b)
    end
    joinpath(a::AbstractString, b::AbstractString) = joinpath(String(a), String(b))
    joinpath(a, b, c, paths...) = joinpath(joinpath(a, b), c, paths...)
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
        m === nothing && return ""
        a, b = String(m.captures[1]), String(m.captures[2])
        _splitdir_nodrive(a, b)[1]
    end
    function _splitdrive(path::String)
        m = match(r"^([^\\]+:|\\\\[^\\]+\\[^\\]+|\\\\\?\\UNC\\[^\\]+\\[^\\]+|\\\\\?\\[^\\]+:|)(.*)$"s, path)
        m === nothing && return "", path
        String(m.captures[1]), String(m.captures[2])
    end
    function _splitdir(path::String)
        a, b = _splitdrive(path)
        _splitdir_nodrive(a, b)
    end
else
    _dirname = dirname
    _splitdir = splitdir
    _splitdrive = splitdrive
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

function resolve_op_ref(x::EXPR, server)
    StaticLint.hasref(x) && return true
    !CSTParser.isoperator(x) && return false
    pf = parent_file(x)
    pf === nothing && return false
    scope = StaticLint.retrieve_scope(x)
    scope === nothing && return false

    return op_resolve_up_scopes(x, CSTParser.str_value(x), scope, server)
end

function op_resolve_up_scopes(x, mn, scope, server)
    scope isa StaticLint.Scope || return false
    if StaticLint.scopehasbinding(scope, mn)
        StaticLint.setref!(x, scope.names[mn])
        return true
    elseif scope.modules isa Dict && length(scope.modules) > 0
        for (_, m) in scope.modules
            if m isa SymbolServer.ModuleStore && StaticLint.isexportedby(Symbol(mn), m)
                StaticLint.setref!(x, maybe_lookup(m[Symbol(mn)], server))
                return true
            elseif m isa StaticLint.Scope && StaticLint.scopehasbinding(m, mn)
                StaticLint.setref!(x, maybe_lookup(m.names[mn], server))
                return true
            end
        end
    end
    CSTParser.defines_module(scope.expr) || !(StaticLint.parentof(scope) isa StaticLint.Scope) && return false
    return op_resolve_up_scopes(x, mn, StaticLint.parentof(scope), server)
end

maybe_lookup(x, server) = x isa SymbolServer.VarRef ? SymbolServer._lookup(x, getsymbolserver(server), true) : x # TODO: needs to go to SymbolServer

function is_in_target_dir_of_package(pkgpath, target)
    try # Safe failure - attempts to read disc.
        spaths = splitpath(pkgpath)
        if (i = findfirst(==(target), spaths)) !== nothing && "src" in readdir(joinpath(spaths[1:i - 1]...))
            return true
        end
        return false
    catch
        return false
    end
end

