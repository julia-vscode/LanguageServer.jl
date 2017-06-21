function parse_jmd(ps, str)
    currentbyte = 1
    blocks = []
    while ps.nt.kind != Tokens.ENDMARKER
        next(ps)
        if ps.t.kind == Tokens.CMD || ps.t.kind == Tokens.TRIPLE_CMD
            push!(blocks, (ps.t.startbyte, CSTParser.INSTANCE(ps)))
        end
    end
    top = CSTParser.EXPR{CSTParser.Block}([], 0, [], "")
    if isempty(blocks)
        return top, ps
    end

    for (startbyte, b) in blocks
        if b isa CSTParser.EXPR{CSTParser.LITERAL{CSTParser.Tokens.TRIPLE_CMD}} && (startswith(b.val, "```julia") || startswith(b.val, "```{julia"))
            blockstr = b.val[4:end - 3]
            ps = CSTParser.ParseState(blockstr)
            while ps.nt.startpos[1] == 1
                next(ps)
            end
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 3

            push!(top.args, CSTParser.EXPR{CSTParser.LITERAL{CSTParser.Tokens.STRING}}([], sizeof(str[prec_str_size]), [], ""))

            args, ps = CSTParser.parse(ps, true)
            append!(top.args, args.args)
            top.span = sum(x.span for x in top.args)
            currentbyte = top.span + 1
        elseif b isa CSTParser.EXPR{CSTParser.LITERAL{CSTParser.Tokens.CMD}} && startswith(b.val, "`j ")
            blockstr = b.val[4:end - 1]
            ps = ParseState(blockstr)
            next(ps)
            prec_str_size = currentbyte:startbyte + ps.nt.startbyte + 1
            push!(top.args, CSTParser.EXPR{CSTParser.LITERAL{CSTParser.Tokens.STRING}}([], sizeof(str[prec_str_size]), [], ""))

            args, ps = parse(ps, true)
            append!(top.args, args.args)
            top.span = sum(x.span for x in top.args)
            currentbyte = top.span + 1
        end
    end

    prec_str_size = currentbyte:sizeof(str)
    push!(top.args, CSTParser.EXPR{CSTParser.LITERAL{CSTParser.Tokens.STRING}}([], sizeof(str[prec_str_size]), [], ""))
    top.span = sum(x.span for x in top.args)

    return top, ps
end
