function parse_jmd(ps, str)
    currentbyte = 1
    blocks = []
    while ps.nt.kind != Tokens.ENDMARKER
        CSTParser.next(ps)
        if ps.t.kind == Tokens.CMD || ps.t.kind == Tokens.TRIPLE_CMD
            push!(blocks, (ps.t.startbyte, CSTParser.INSTANCE(ps)))
        end
    end
    top = EXPR(CSTParser.Block, CSTParser.EXPR[])
    if isempty(blocks)
        return top, ps
    end

    for (startbyte, b) in blocks
        if b.typ === CSTParser.LITERAL && b.kind == CSTParser.Tokens.TRIPLE_CMD && (startswith(b.val, "julia") || startswith(b.val, "{julia"))
            blockstr = b.val
            ps = CSTParser.ParseState(blockstr)
            # skip first line
            while ps.nt.startpos[1] == 1
                CSTParser.next(ps)
            end
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 3

            push!(top.args, CSTParser.mLITERAL(sizeof(str[prec_str_size]), sizeof(str[prec_str_size]) , "", CSTParser.Tokens.STRING))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        elseif b.typ === CSTParser.LITERAL && b.kind == CSTParser.Tokens.CMD && startswith(b.val, "j ")
            blockstr = b.val
            ps = CSTParser.ParseState(blockstr)
            CSTParser.next(ps)
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 1
            push!(top.args, CSTParser.mLITERAL(sizeof(str[prec_str_size]), sizeof(str[prec_str_size]), "", CSTParser.Tokens.STRING))

            args, ps = parse(ps, true)
            append!(top.args, args.args)
            CSTParser.update_span!(top)
            currentbyte = top.fullspan + 1
        end
    end
    prec_str_size = currentbyte:sizeof(str)
    push!(top.args, CSTParser.mLITERAL(sizeof(str[prec_str_size]), sizeof(str[prec_str_size]), "", CSTParser.Tokens.STRING))

    return top, ps
end
