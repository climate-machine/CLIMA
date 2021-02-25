"""
    ImpermeableTracer()

No tracer diffusion across boundary
"""
struct ImpermeableTracer{PV <: Tracers{N} where {N}} <: BCDef{PV} end

# No tracers by default:
ImpermeableTracer() = ImpermeableTracer{Tracers{0}}()

function atmos_tracer_normal_boundary_flux_second_order!(
    nf,
    bc_tracer::ImpermeableTracer,
    atmos,
    args...,
)
    nothing
end
