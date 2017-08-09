using LanguageServer
function test_undefvar(str, offset = 0)
    server = LanguageServer.LanguageServerInstance(false,false,false)
    x = CSTParser.parse(str,true)
    s = LanguageServer.TopLevelScope(LanguageServer.ScopePosition("none", typemax(Int)), LanguageServer.ScopePosition("none", 0), false, Dict(), EXPR[], Symbol[], false, true, Dict(:toplevel => []), [])
    LanguageServer.toplevel(x, s, server)
    L = LanguageServer.LintState(true, [], [], [])
    LanguageServer.lint(x, s, L, server, true)
    isempty(L.diagnostics)
end


test_undefvar("""
var = 1
var""")
