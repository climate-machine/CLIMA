"""
the hyperdiffusion model in a 3D periodic box
∂ρ
-- = - ∇^4 (ρ) = - ∇ ⋅ (∇Δρ)
∂t
test the spatical discretization vs the analytical solution
init cond:  ρ_0 = sin(kx+ly+mz)
analytical solution:  ∇^4 ρ = (k^2+l^2+m^2)^2 ρ
"""

using MPI
using ClimateMachine
using Logging
using ClimateMachine.Mesh.Topologies
using ClimateMachine.Mesh.Grids
using ClimateMachine.DGMethods
using ClimateMachine.DGMethods.NumericalFluxes
using ClimateMachine.MPIStateArrays
using LinearAlgebra
using Printf
using Dates
using ClimateMachine.GenericCallbacks:
    EveryXWallTimeSeconds, EveryXSimulationSteps
using ClimateMachine.ODESolvers
using ClimateMachine.VTK: writevtk, writepvtu
using ClimateMachine.Mesh.Grids: min_node_distance

const output = parse(Bool, lowercase(get(ENV, "JULIA_CLIMA_OUTPUT", "false")))

if !@isdefined integration_testing
    const integration_testing = parse(
        Bool,
        lowercase(get(ENV, "JULIA_CLIMA_INTEGRATION_TESTING", "false")),
    )
end

include("hyperdiffusion_model.jl")

struct ConstantHyperDiffusion{dim, dir, FT} <: HyperDiffusionProblem
    D::SMatrix{3, 3, FT, 9}
end

function nodal_init_state_auxiliary!(
    balance_law::HyperDiffusion,
    aux::Vars,
    tmp::Vars,
    geom::LocalGeometry,
)
    aux.D = balance_law.problem.D
end

"""
    initial condition is given by ρ0 = sin(kx+ly+mz)
"""

function initial_condition!(
    problem::ConstantHyperDiffusion{dim, dir},
    state,
    aux,
    x,
    t,
) where {dim, dir}
    @inbounds begin
        k = SVector(1, 2, 3)
        kD = k * k' .* problem.D
        if dir === EveryDirection()
            c = sum(abs2, k[SOneTo(dim)]) * sum(kD[SOneTo(dim), SOneTo(dim)])
        elseif dir === HorizontalDirection()
            c =
                sum(abs2, k[SOneTo(dim - 1)]) *
                sum(kD[SOneTo(dim - 1), SOneTo(dim - 1)])
        elseif dir === VerticalDirection()
            c = k[dim]^2 * kD[dim, dim]
        end
        state.ρ = sin(dot(k[SOneTo(dim)], x[SOneTo(dim)])) * exp(-c * t)
    end
end

function run(
    mpicomm,
    ArrayType,
    dim,
    topl,
    N,
    FT,
    direction,
    D
)
"""
balance_law = DivergenceDampingLaw()
model = DGModel(
        balance_law,
        grid,
        numerical_flux_first_order,
        numerical_flux_second_order,
        numerical_flux_gradient
    )
Q_0 = cool_state()
Q_1 = similar(Q_0)
model(Q_1, Q_0, nothing, 0)
"""
    grid = DiscontinuousSpectralElementGrid(
            topl,
            FloatType = FT,
            DeviceArray = ArrayType,
            polynomialorder = N,
        )
    model = HyperDiffusion{dim}(ConstantHyperDiffusion{dim, direction(), FT}(D))
    dg = DGModel(
            model,
            grid,
            CentralNumericalFluxFirstOrder(),
            CentralNumericalFluxSecondOrder(),
            CentralNumericalFluxGradient(),
            direction = direction(),
        )

    Q0 = init_ode_state(dg, FT(0))
    dx = min_node_distance(grid)
    dt = dx^4 / 25 / sum(D)
    @info "time step" dt
    # dt = outputtime / ceil(Int64, outputtime / dt) 

    rhs_diag = similar(Q0)
    dg(rhs_diag, Q0, nothing, 0)

    Q1_diag = Q0+dt*rhs_diag

    Q1_lsrk = Q0
    lsrk = LSRK54CarpenterKennedy(dg, Q1_lsrk; dt = dt, t0 = 0)
    solve!(Q1_lsrk, lsrk; timeend = FT(dt))

    Q1_form = init_ode_state(dg, FT(dt)) 

    rhs_lsrk = (Q1_lsrk-Q0)/dt

    k = SVector(1, 2, 3)
    rhs_anal = -(sum(abs2, k)^2).*Q0  

    Q1_lsrk_diag = euclidean_distance(Q1_diag, Q1_lsrk)
    Q1_form_diag = euclidean_distance(Q1_diag, Q1_form)
    Q1_form_lsrk = euclidean_distance(Q1_lsrk, Q1_form)
    rhs_diag_ana = euclidean_distance(rhs_diag,rhs_anal)
    rhs_lsrk_ana = euclidean_distance(rhs_lsrk,rhs_anal)
    rhs_lsrk_diag = euclidean_distance(rhs_lsrk,rhs_diag)
    
    @info @sprintf """Finished
    norm(Q1_lsrk_diag)                 = %.16e
    norm(Q1_form_diag)                 = %.16e
    norm(Q1_form_lsrk)                 = %.16e
    norm(rhs_diag_ana)                 = %.16e
    norm(rhs_lsrk_ana)                 = %.16e
    norm(rhs_lsrk_diag)                = %.16e
    """ Q1_lsrk_diag Q1_form_diag Q1_form_lsrk rhs_diag_ana rhs_lsrk_ana rhs_lsrk_diag 

    return Q1_lsrk_diag
end

ClimateMachine.init()
ArrayType = ClimateMachine.array_type()
mpicomm = MPI.COMM_WORLD
FT = Float64
dim = 3
Ne = 4
xrange = range(FT(0); length = Ne + 1, stop = FT(2pi))
brickrange = ntuple(j -> xrange, dim)
periodicity = ntuple(j -> true, dim)
topl = StackedBrickTopology(
    mpicomm,
    brickrange;
    periodicity = periodicity,
)
polynomialorder = 4
D = SMatrix{3, 3, FT}(
       ones(3,3), 
    )

outnorm = run(mpicomm, ArrayType, dim, topl, polynomialorder, Float64, HorizontalDirection, D)
# @info @sprintf """Finished
# outnorm(Q)                 = %.16e
# """ outnorm