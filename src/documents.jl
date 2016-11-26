## Document open, change, save and close handlers ##

## didOpen ##

type DidOpenTextDocumentParams
    textDocument::TextDocumentItem
end
DidOpenTextDocumentParams(d::Dict) = DidOpenTextDocumentParams(TextDocumentItem(d["textDocument"]))

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didOpen")},DidOpenTextDocumentParams}, server)
    server.documents[r.params.textDocument.uri] = Document(r.params.textDocument.text.data, []) 
    parseblocks(r.params.textDocument.uri, server)
    
    if should_file_be_linted(r.params.textDocument.uri, server) 
        process_diagnostics(r.params.textDocument.uri, server) 
    end
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didOpen")}}, params)
    return DidOpenTextDocumentParams(params)
end

## didChange ##

type TextDocumentContentChangeEvent 
    range::Range
    rangeLength::Int
    text::String
end
TextDocumentContentChangeEvent(d::Dict) = TextDocumentContentChangeEvent(Range(d["range"]), d["rangeLength"], d["text"])

type DidChangeTextDocumentParams
    textDocument::VersionedTextDocumentIdentifier
    contentChanges::Vector{TextDocumentContentChangeEvent}
end
DidChangeTextDocumentParams(d::Dict) = DidChangeTextDocumentParams(VersionedTextDocumentIdentifier(d["textDocument"]),TextDocumentContentChangeEvent.(d["contentChanges"]))

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didChange")},DidChangeTextDocumentParams}, server)
    doc = server.documents[r.params.textDocument.uri].data
    blocks = server.documents[r.params.textDocument.uri].blocks 
    for c in r.params.contentChanges 
        startline, endline = get_rangelocs(doc, c.range) 
        io = IOBuffer(doc) 
        seek(io, startline) 
        s = e = 0 
        while s<c.range.start.character 
            s += 1 
            read(io, Char) 
        end 
        startpos = position(io) 
        seek(io, endline) 
        while e<c.range.stop.character 
            e += 1 
            read(io, Char) 
        end 
        endpos = position(io) 
         doc = length(doc)==0 ? c.text.data : vcat(doc[1:startpos], c.text.data, doc[endpos+1:end])
        
        for i = 1:length(blocks)
            intersect(blocks[i].range, c.range) && (blocks[i].uptodate = false)
        end
    end 
    server.documents[r.params.textDocument.uri].data = doc
    parseblocks(r.params.textDocument.uri, server) 
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didChange")}}, params)
    return DidChangeTextDocumentParams(params)
end

## didSave ##

type DidSaveTextDocumentParams
    textDocument::TextDocumentIdentifier
end
DidSaveTextDocumentParams(d::Dict) = DidSaveTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didSave")},DidSaveTextDocumentParams}, server)
    parseblocks(r.params.textDocument.uri, server, true)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didSave")}}, params)
    return DidSaveTextDocumentParams(params)
end

## didClose ##

type DidCloseTextDocumentParams
    textDocument::TextDocumentIdentifier
end
DidCloseTextDocumentParams(d::Dict) = DidCloseTextDocumentParams(TextDocumentIdentifier(d["textDocument"]))

function process(r::JSONRPC.Request{Val{Symbol("textDocument/didClose")},DidCloseTextDocumentParams}, server)
    delete!(server.documents, r.params.textDocument.uri)
end

function JSONRPC.parse_params(::Type{Val{Symbol("textDocument/didClose")}}, params)
    return DidCloseTextDocumentParams(params)
end

## parsing functions ##

function Block(utd, ex, r::Range)
    t, name, doc, lvars = classify_expr(ex)
    ctx = LintContext()
    ctx.lineabs = r.start.line+1
    dl = r.stop.line-r.start.line-ctx.line
    # Lint.lintexpr(ex, ctx)
    # diags = map(ctx.messages) do l
    #     return Diagnostic(Range(Position(r.start.line+l.line+dl-1, 0), Position(r.start.line+l.line+dl-1, 100)),
    #                     LintSeverity[string(l.code)[1]],
    #                     string(l.code),
    #                     "Lint.jl",
    #                     l.message) 
    # end
    diags = Diagnostic[]
    v = VarInfo(t, doc)

    return Block(utd, ex, r, name,v, lvars, diags)
end

function parseblocks(uri::String, server::LanguageServerInstance, updateall=false)
    doc = String(server.documents[uri].data)
    blocks = server.documents[uri].blocks
    linebreaks = get_linebreaks(doc) 
    n = length(doc.data)
    if doc==""
        server.documents[uri].blocks = []
        return
    end
    ifirstbad = findfirst(b->!b.uptodate, blocks)

    # Check which region of the source file to parse:

    # Parse the whole file if it's not been parsed or you're asked to,
    #  the last OR fixes something obscure (find it and fix it)
    if isempty(blocks) || updateall || ifirstbad==0
        i0 = i1 = 1 # Char position in document
        p0 = p1 = Position(0, 0) # vscode Protocul position
        out = Block[]
        inextgood = 0
    else # reparse the source from the first bad block to the next good block
        inextgood = findnext(b->b.uptodate, blocks, ifirstbad) # index of next up to date Block
        p0 = p1 = blocks[ifirstbad].range.start
        i0 = i1 = linebreaks[p0.line+1]+p0.character+1
        out = blocks[1:ifirstbad-1]
    end

    while 0 < i1 ≤ n
        (ex,i1) = parse(doc, i0, raise=false)
        p0 = get_pos(i0, linebreaks)
        p1 = get_pos(i1-1, linebreaks)
        if isa(ex, Expr) && ex.head in[:incomplete,:error]
            push!(out,Block(false, ex, Range(p0, Position(p0.line+1, 0))))
            while true
                !(doc[i0] in ['\n','\t',' ']) && break
                i0 += 1
            end
            i0 = i1 = search(doc,'\n',i0)
        else
            push!(out,Block(true,ex,Range(p0,p1)))
            i0 = i1
            if inextgood>0 && ex==blocks[inextgood].ex
                dl = p0.line - blocks[inextgood].range.start.line
                out = vcat(out,blocks[inextgood+1:end])
                for i  = inextgood+1:length(out)
                    out[i].range.start.line += dl
                    out[i].range.stop.line += dl
                end
                break
            end
        end
    end
    server.documents[uri].blocks = out
    server.documents[uri].blocks[end].range.stop = get_pos(linebreaks[end],linebreaks) #ensure last block fills document
    return 
end 



function classify_expr(ex)
    if isa(ex, Expr)
        if ex.head==:macrocall && ex.args[1]==GlobalRef(Core, Symbol("@doc"))
            return classify_expr(ex.args[3])
        elseif ex.head in [:const, :global]
            return classify_expr(ex.args[1])
        elseif ex.head==:function || (ex.head==:(=) && isa(ex.args[1], Expr) && ex.args[1].head==:call)
            return parsefunction(ex)
        elseif ex.head==:macro
            return "macro", string(ex.args[1].args[1]), "", Dict(string(x)=>VarInfo(Any,"macro argument") for x in ex.args[1].args[2:end])
        elseif ex.head in [:abstract, :bitstype, :type, :immutable]
            return parsedatatype(ex)
        elseif ex.head==:module
            return "Module", string(ex.args[2]), "", Dict()
        elseif ex.head == :(=) && isa(ex.args[1], Symbol)
            return "Any", string(ex.args[1]), "", Dict()
        end
    end
    return "Any", "none", "", Dict()
end

function parsefunction(ex)
    (isa(ex.args[1], Symbol) || isempty(ex.args[1].args)) && return "Function", "none", "", Dict()
    fname = string(isa(ex.args[1].args[1], Symbol) ? ex.args[1].args[1] : ex.args[1].args[1].args[1])
    lvars = Dict()
    for a in ex.args[1].args[2:end]
        if isa(a, Symbol)
            lvars[string(a)] = VarInfo(Any, "Function argument")
        elseif a.head==:(::)
            if length(a.args)>1
                lvars[string(a.args[1])] = VarInfo(a.args[2], "Function argument")
            else
                lvars[string(a.args[1])] = VarInfo(DataType, "Function argument")
            end
        elseif a.head==:kw
            if isa(a.args[1], Symbol)
                lvars[string(a.args[1])] = VarInfo(Any, "Function keyword argument")
            else
                lvars[string(a.args[1].args[1])] = VarInfo(Any,"Function keyword argument")
            end 
        elseif a.head==:parameters
            for sub_a in a.args
                if isa(sub_a, Symbol)
                    lvars[string(sub_a)] = VarInfo(Any, "Function argument")
                elseif sub_a.head==:...
                    lvars[string(sub_a.args[1])] = VarInfo("keywords", "Function Argument")
                elseif sub_a.head==:kw
                    if isa(sub_a.args[1], Symbol)                    
                        lvars[string(sub_a.args[1])] = VarInfo("", "Function Argument")
                    elseif sub_a.args[1].head==:(::)
                        lvars[string(sub_a.args[1].args[1])] = VarInfo(sub_a.args[1].args[2], "Function Argument")
                    end
                end
            end
        end
    end
    for a in ex.args[2].args
        if isa(a,Expr) && a.head==:(=) && isa(a.args[1], Symbol)
            name = string(a.args[1]) 
            if name in keys(lvars)
                lvars[name].doc = "$(lvars[name].doc) (redefined in body)"
                lvars[name].t = "Any"
            else
                lvars[name] = VarInfo("Any", "")
            end
        end
    end

    doc = string(ex.args[1])
    return "Function", fname, doc, lvars
end


function parsedatatype(ex)
    fields = Dict()
    if ex.head==:abstract
        name = string(isa(ex.args[1], Symbol) ? ex.args[1] : ex.args[1].args[1])
        doc = string(ex)
    elseif ex.head==:bitstype
        name = string(isa(ex.args[2], Symbol) ? ex.args[2] : ex.args[2].args[1])
        doc = string(ex)
    else
        name = string(isa(ex.args[2], Symbol) ? ex.args[2] : ex.args[2].args[1])
        st = string(isa(ex.args[2], Symbol) ? "Any" : string(ex.args[2].args[2]))
        for a in ex.args[3].args 
            if isa(a, Symbol)
                fields[string(a)] = VarInfo(Any, "")
            elseif a.head==:(::)
                fields[string(a.args[1])] = VarInfo(length(a.args)==1 ? a.args[1] : a.args[2], "")
            end
        end
        doc = "$name <: $(st)"
        doc *= length(fields)>0 ? "\n"*prod("  $fname::$(v.t)\n" for (fname,v) in fields) : "" 
    end
    return "DataType", name, doc, fields
end





