@setup_workload begin
    iob = IOBuffer()
    println(iob)
    @compile_workload begin
        # Suppress errors
        if get(ENV, "JULIA_DEBUG", "") == "LanguageServer"
            precompile_logger = Logging.ConsoleLogger()
        else
            precompile_logger = Logging.NullLogger()
        end
        Logging.with_logger(precompile_logger) do
            runserver(iob)
        end
    end
end
precompile(runserver, ())

