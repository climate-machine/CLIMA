abstract type OceanBoundaryCondition end

"""
    Defining dummy structs to dispatch on for boundary conditions.
"""
struct CoastlineFreeSlip             <: OceanBoundaryCondition end
struct CoastlineNoSlip               <: OceanBoundaryCondition end
struct OceanFloorFreeSlip            <: OceanBoundaryCondition end
struct OceanFloorNoSlip              <: OceanBoundaryCondition end
struct OceanSurfaceNoStressNoForcing <: OceanBoundaryCondition end
struct OceanSurfaceStressNoForcing   <: OceanBoundaryCondition end
struct OceanSurfaceNoStressForcing   <: OceanBoundaryCondition end
struct OceanSurfaceStressForcing     <: OceanBoundaryCondition end

"""
    CoastlineFreeSlip

applies boundary condition ν∇u = 0 and κ∇θ = 0
"""

"""
    ocean_boundary_state!(::HBModel, ::CoastlineFreeSlip, ::Union{Rusanov, CentralNumericalFluxGradient})

apply free slip boundary conditions for velocity
apply no penetration boundary for temperature
nothing needed to do since these are neumann BCs and no gradients here

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::CoastlineFreeSlip,
                                       ::Union{Rusanov,
                                               CentralNumericalFluxGradient},
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::CoastlineFreeSlip, ::CentralNumericalFluxDiffusive)

apply free slip boundary conditions for velocity
apply no penetration boundary for temperature
sets ghost point to have no numerical flux on the boundary for ν∇u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::CoastlineFreeSlip,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  D⁺.ν∇u = -D⁻.ν∇u

  D⁺.κ∇θ = -D⁻.κ∇θ

  return nothing
end

"""
    CoastlineNoSlip

applies boundary condition u = 0 and κ∇θ = 0
"""

"""
    ocean_boundary_state!(::HBModel, ::CoastlineNoSlip, ::Rusanov)

apply no slip boundary condition for velocity
apply no penetration boundary for temperature
set sets ghost point to have no numerical flux on the boundary for u

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::CoastlineNoSlip,
                                       ::Rusanov,
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  Q⁺.u = -Q⁻.u

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::CoastlineNoSlip, ::CentralNumericalFluxGradient)

apply no slip boundary condition for velocity
apply no penetration boundary for temperature
set numerical flux to zero for u

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::CoastlineNoSlip,
                                       ::CentralNumericalFluxGradient,
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  FT = eltype(Q⁺)
  Q⁺.u = SVector(-zero(FT), -zero(FT))

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::CoastlineNoSlip, ::CentralNumericalFluxDiffusive)

apply no slip boundary condition for velocity
apply no penetration boundary for temperature
sets ghost point to have no numerical flux on the boundary for u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::CoastlineNoSlip,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  Q⁺.u = -Q⁻.u

  D⁺.κ∇θ = -D⁻.κ∇θ

  return nothing
end

"""
    OceanFloorFreeSlip

applies boundary condition ν∇u = 0 and κ∇θ = 0
"""

"""
    ocean_boundary_state!(::HBModel, ::OceanFloorFreeSlip, ::Rusanov)

apply free slip boundary conditions for velocity
apply no penetration boundary for temperature
set ghost point to have no numerical flux on the boundary for w

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::OceanFloorFreeSlip,
                                       ::Rusanov,
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  A⁺.w = -A⁻.w

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanFloorFreeSlip, ::CentralNumericalFluxGradient)

apply free slip boundary condition for velocity
apply no penetration boundary for temperature
set numerical flux to zero for w

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::OceanFloorFreeSlip,
                                       ::CentralNumericalFluxGradient,
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  FT = eltype(Q⁺)
  A⁺.w = -zero(FT)

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanFloorFreeSlip, ::CentralNumericalFluxDiffusive)

apply free slip boundary conditions for velocity
apply no penetration boundary for temperature
sets ghost point to have no numerical flux on the boundary for ν∇u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::OceanFloorFreeSlip,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  A⁺.w = -A⁻.w
  D⁺.ν∇u = -D⁻.ν∇u

  D⁺.κ∇θ = -D⁻.κ∇θ

  return nothing
end

"""
    OceanFloorNoSlip

applies boundary condition u = 0 and κ∇θ = 0
"""

"""
    ocean_boundary_state!(::HBModel, ::OceanFloorNoSlip, ::Rusanov)

apply no slip boundary condition for velocity
apply no penetration boundary for temperature
set sets ghost point to have no numerical flux on the boundary for u and w

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::OceanFloorNoSlip,
                                       ::Rusanov,
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  Q⁺.u = -Q⁻.u
  A⁺.w = -A⁻.w

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanFloorNoSlip, ::CentralNumericalFluxGradient)

apply no slip boundary condition for velocity
apply no penetration boundary for temperature
set numerical flux to zero for u and w

# Arguments
- `Q⁺`: state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::OceanFloorNoSlip,
                                       ::CentralNumericalFluxGradient,
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  FT = eltype(Q⁺)
  Q⁺.u = SVector(-zero(FT), -zero(FT))
  A⁺.w = -zero(FT)

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanFloorNoSlip, ::CentralNumericalFluxDiffusive)

apply no slip boundary condition for velocity
apply no penetration boundary for temperature
sets ghost point to have no numerical flux on the boundary for u,w and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel, ::OceanFloorNoSlip,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)

  Q⁺.u = -Q⁻.u
  A⁺.w = -A⁻.w

  D⁺.κ∇θ = -D⁻.κ∇θ

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::Union{OceanSurface*}, ::Union{Rusanov, CentralNumericalFluxGradient})

applying neumann boundary conditions, so don't need to do anything for these numerical fluxes
"""
@inline function ocean_boundary_state!(::HBModel, ::Union{
                                       OceanSurfaceNoStressNoForcing,
                                       OceanSurfaceStressNoForcing,
                                       OceanSurfaceNoStressForcing,
                                       OceanSurfaceStressForcing},
                                       ::Union{Rusanov,
                                               CentralNumericalFluxGradient},
                                       Q⁺, A⁺, n⁻, Q⁻, A⁻, t)
  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanSurfaceNoStressNoForcing, ::CentralNumericalFluxDiffusive)

apply no flux boundary condition for velocity
apply no flux boundary condition for temperature
set ghost point to have no numerical flux on the boundary for ν∇u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(::HBModel,
                                       ::OceanSurfaceNoStressNoForcing,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  D⁺.ν∇u = -D⁻.ν∇u
  D⁺.κ∇θ = -D⁻.κ∇θ

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanSurfaceStressNoForcing, ::CentralNumericalFluxDiffusive)

apply wind-stress boundary condition for velocity
apply no flux boundary condition for temperature
set ghost point for numerical flux on the boundary for ν∇u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(m::HBModel,
                                       ::OceanSurfaceStressNoForcing,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  τᶻ = velocity_flux(m.problem, A⁻.y, m.ρₒ)
  τ = @SMatrix [ -0 -0; -0 -0; τᶻ -0]
  D⁺.ν∇u = -D⁻.ν∇u + 2 * τ

  D⁺.κ∇θ = -D⁻.κ∇θ

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanSurfaceNoStressForcing, ::CentralNumericalFluxDiffusive)

apply no flux boundary condition for velocity
apply forcing boundary condition for temperature
set ghost point for numerical flux on the boundary for ν∇u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(m::HBModel,
                                       ::OceanSurfaceNoStressForcing,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  D⁺.ν∇u = -D⁻.ν∇u

  σᶻ = temperature_flux(m.problem, A⁻.y, Q⁻.θ)
  σ = @SVector [-0, -0, σᶻ]
  D⁺.κ∇θ = -D⁻.κ∇θ + 2 * σ

  return nothing
end

"""
    ocean_boundary_state!(::HBModel, ::OceanSurfaceStressForcing, ::CentralNumericalFluxDiffusive)

apply wind-stress boundary condition for velocity
apply forcing boundary condition for temperature
set ghost point for numerical flux on the boundary for ν∇u and κ∇θ

# Arguments
- `Q⁺`: state vector at ghost point
- `D⁺`: diffusive state vector at ghost point
- `A⁺`: auxiliary state vector at ghost point
- `n⁻`: normal vector, not used
- `Q⁻`: state vector at interior
- `D⁻`: diffusive state vector at interior point
- `A⁻`: auxiliary state vector at interior point
- `t`:  time, not used
"""
@inline function ocean_boundary_state!(m::HBModel,
                                       ::OceanSurfaceStressForcing,
                                       ::CentralNumericalFluxDiffusive,
                                       Q⁺, D⁺, A⁺, n⁻, Q⁻, D⁻, A⁻, t)
  τᶻ = velocity_flux(m.problem, A⁻.y, m.ρₒ)
  τ = @SMatrix [ -0 -0; -0 -0; τᶻ -0]
  D⁺.ν∇u = -D⁻.ν∇u + 2 * τ

  σᶻ = temperature_flux(m.problem, A⁻.y, Q⁻.θ)
  σ = @SVector [-0, -0, σᶻ]
  D⁺.κ∇θ = -D⁻.κ∇θ + 2 * σ

  return nothing
end
