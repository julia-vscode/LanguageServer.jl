# TODO Reenable this. But for now we disable because it starts
# lots of background tasks that never terminate which is not
# allowed in precompile

# @setup_workload begin
#     iob = IOBuffer()
#     println(iob)
#     @compile_workload begin
#         # Suppress errors
#         if get(ENV, "JULIA_DEBUG", "") in ("all", "LanguageServer")
#             precompile_logger = Logging.ConsoleLogger()
#         else
#             precompile_logger = Logging.NullLogger()
#         end
#         Logging.with_logger(precompile_logger) do
#             runserver(iob)
#         end
#     end
# end
precompile(runserver, ())
