
module ModuleA
    importall Distributions

    module ModuleB
        bar()=3
    end
    
    """
    foo1 docs
    """
    foo1()=bar()

    """
    foo2 function docs
    """
    function foo2 end

    """
    foo2 method docs
    """
    foo2(a) = 3

    Base.run()=4
end

function Base.startswith(a::Tuple, b::Tuple)
    if length(a)<length(b)
        return false
    else
        for i in 1:length(b)
            if a[i]!=b[i]
                return false
            end
        end
        return true
    end
end


const storage_functions = Dict{String,Any}()
const storage_methods = []

# The general strategy is to traverse ALL modules and look for functions
# that have methods that are defined in the module we are really interested
# in. So say we want the stuff from ModuleA. We will then also traverse
# all functions in Base and all other modules, so that we can find a method
# that might have been added to a function in Base from ModuleA
function get_fs(M_of_interest, M=Main)
    # This is a bit of a hack, probably should move this into a separate function
    if M==Main
        empty!(storage_functions)
        empty!(storage_methods)
    end

    docstore = Docs.meta(M)

    fn_M = fullname(M)
    fn_M_of_interest = fullname(M_of_interest)

    # Look at all names in the current module M
    for i in names(M, true, true)
        i_string = string(i)
        # Ignore names that are not defined or are deprecated
        if isdefined(M, i) && !Base.isdeprecated(M,i)
            ii = eval(M,i)
            # Handle names that are functions
            if isa(ii, Function)
                fn_module = typeof(ii).name.module
                # We only look at functions that are defined in the current module
                # That is we ignore functions that are imported into the current module
                if fn_module == M
                    fn_function_module = fullname(fn_module)
                    # Because we are also traversing modules that we are not interested in
                    # we need this if, so that this pass only extracts docs for functions
                    # in the module that we want docs for
                    if startswith(fn_function_module, fn_M_of_interest)
                        # Get documentation
                        if haskey(docstore, Docs.Binding(M, i)) && haskey(docstore[Docs.Binding(M, i)].docs, Union{})
                            storage_functions[string(ii)] = docstore[Docs.Binding(M, i)].docs[Union{}]
                        else
                            storage_functions[string(ii)] = nothing
                        end
                    end
                    
                    # Now look at all the methods associated with the function
                    # in this case we are especially looking for methods that are
                    # defined in the module that we are interested in (but for a
                    # function in a different module)
                    for l in Base.MethodList(typeof(ii).name.mt)
                        fn_method_module = fullname(l.module)
                        if startswith(fn_method_module, fn_M_of_interest)
                            d = Dict()
                            d[:fname] = string(ii)
                            if haskey(docstore, Docs.Binding(M, i))
                                # TODO This should just extract the doc for the method
                                # Whereas this gets the doc for the whole function, which
                                # we don't want here
                                d[:doc] = Docs.doc(Docs.Binding(M, i))
                            else
                                d[:doc] = nothing
                            end
                            d[:file] = l.file
                            d[:line] = l.line
                            push!(storage_methods, d)
                        end
                    end
                end
            elseif isa(ii, DataType)
                #println("Datatype: $i")
            # Handle names that are modules
            elseif isa(ii, Module)
                fn = fullname(ii)                
                # We only want to traverse child modules here, not modules
                # that show up for some other reason
                if ii!=M && startswith(fn, fn_M)
                    get_fs(M_of_interest, ii)
                end
            else
                # println("$(typeof(ii))   $i")
            end
        end
    end
end

@time get_fs(Base)

length(storage_functions)
length(storage_methods)
