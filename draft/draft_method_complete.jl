using REPL

# Test with or without arbitrary additional arguments
moreargs = true

x = 3

teststr = "x,x,x,x,x"
callstr = "_(" * teststr * ")"
ex_org = Meta.parse(callstr, raise=false, depwarn=false)
res = REPL.REPLCompletions.complete_any_methods(ex_org, Main, Main, moreargs)

# Reference directly from REPL
refstr = "?(" * teststr
if !moreargs
    refstr *= ")"
end
ref = REPL.REPLCompletions.completions(refstr, length(refstr))[1]

println(ref == res)
