info("Symbol server started")

# TODO Don't copy code, put into some shared code file
function load_mod_names(topmodname)
    load_mod_names(getfield(Main, Symbol(topmodname)))
end

# TODO Don't copy code, put into some shared code file
function load_mod_names(mod::Module)
    expt_names = Set{String}()
    for name in names(mod)
        sname = string(name)
        if !startswith(sname, "#")
            push!(expt_names, sname)
        end
    end
    int_names = Set{String}()
    for name in names(mod, true, true)
        sname = string(name)
        if !startswith(sname, "#")
            push!(int_names, sname)
        end
    end

    expt_names, int_names
end

while true
    message, payload = deserialize(STDIN)

    if message == :import
        try
            @eval import $payload

            mod_names = load_mod_names(string(payload))
            serialize(STDOUT, (:success, mod_names))
        catch er
            serialize(STDOUT, (:failure, nothing))
        end
    end
end
