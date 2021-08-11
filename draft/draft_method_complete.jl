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

struct Foo
    bar
    baz
end

function do_something(x::Foo)
    x
end

phi = Foo(1, 2)
psi = Foo(2, 3)

##
using CSTParser, StaticLint
expr = CSTParser.parse("""x=3
x""")
println(StaticLint.parentof(expr))

x = 3
