include("RegistryQuery.jl")

JSONRPC.@dict_readable struct LensParams <: JSONRPC.Outbound
    name::String
    uuid::String
    depotPath::Vector{String}
end

JSONRPC.@dict_readable struct LensResponse <: JSONRPC.Outbound
    latest_version::Union{String,Nothing}
    url::Union{String,Nothing}
    registry::Union{String,Nothing}
end
LensResponse(m::RegistryQuery.PkgMetadata) = LensResponse(m.latest_version, m.url, m.registry)


function lens_request(params::LensParams, server, conn)
    registries = RegistryQuery.reachable_registries(; depots=params.depotPath)
    @debug params.depotPath
    @debug registries
    for registry in registries
        uuid = nothing
        try
            uuid = UUID(params.uuid)
        catch
            uuid = RegistryQuery.uuids_from_name(registry, params.name)[1]
        end

        metadata = RegistryQuery.get_pkg_metadata(registry, uuid)
        # If the pakcage is knwown, return, i.e., don't query other registries.
        if metadata !== RegistryQuery.UnknownPkgMetadata
            return LensResponse(metadata)
        end
    end

    # If the package isn't found in all registries, return unknown package.
    return LensResponse(RegistryQuery.UnknownPkgMetadata)
end
