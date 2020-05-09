using Distributions
using Random
using StaticArrays
using Test
using DocStringExtensions
using LinearAlgebra
using ClimateMachine
using ClimateMachine.Atmos
using ClimateMachine.ConfigTypes
using ClimateMachine.Diagnostics
using ClimateMachine.GenericCallbacks
using ClimateMachine.ODESolvers
using ClimateMachine.Mesh.Filters
using ClimateMachine.MoistThermodynamics
using ClimateMachine.VariableTemplates
using CLIMAParameters
using CLIMAParameters.Atmos.SubgridScale: C_smag
using CLIMAParameters.Planet: R_d, cp_d, cv_d, MSLP, grav
struct EarthParameterSet <: AbstractEarthParameterSet end
const param_set = EarthParameterSet()
function init_greenvortex!(bl, state, aux, (x, y, z), t)
    # Problem float-type
    FT = eltype(state)

    # Unpack constant parameters
    R_gas::FT = R_d(bl.param_set)
    c_p::FT = cp_d(bl.param_set)
    c_v::FT = cv_d(bl.param_set)
    p0::FT = MSLP(bl.param_set)
    _grav::FT = grav(bl.param_set)
    γ::FT = c_p / c_v

    # Compute perturbed thermodynamic state:
    ρ = FT(1.178)      # density
    ρu = SVector(FT(0), FT(0), FT(0))  # momentum
    #State (prognostic) variable assignment
    e_pot = FT(0)# potential energy
    Pinf = 101325
    Uzero = FT(100)
    p = Pinf + (ρ * Uzero / 16) * (2 + cos(z)) * (cos(x) + cos(y))
    u = Uzero * sin(x) * cos(y) * cos(z)
    v = -Uzero * cos(x) * sin(y) * cos(z)
    e_kin = 0.5 * (u^2 + v^2)
    T = p / (ρ * R_gas)
    e_int = internal_energy(bl.param_set, T, PhasePartition(FT(0)))
    ρe_tot = ρ * (e_kin + e_pot + e_int)
    # Assign State Variables
    state.ρ = ρ
    state.ρu = SVector(FT(ρ * u), FT(ρ * v), FT(0))
    state.ρe = ρe_tot
end

"""
    config_greenvortex(FT, N, resolution, xmax, ymax, zmax)

Arguments
- FT = Floating-point type. Currently `Float64` or `Float32`
- N  = DG Polynomial order
- resolution = 3-component Tuple (Δx, Δy, Δz) with effective resolutions for Cartesian directions
- xmax, ymax, zmax = Domain maximum extents. Assumes (0,0,0) to be the domain minimum extents unless otherwise specified.

Returns
- `config` = Object using the constructor for the `AtmosLESConfiguration`
"""
function config_greenvortex(
    FT,
    N,
    resolution,
    xmax,
    ymax,
    zmax,
    xmin,
    ymin,
    zmin,
)

    ode_solver = ClimateMachine.ExplicitSolverType(
        solver_method = LSRK144NiegemannDiehlBusch,
    )

    _C_smag = FT(C_smag(param_set))
    model = AtmosModel{FT}(
        AtmosLESConfigType,                 # Flow in a box, requires the AtmosLESConfigType
        orientation = NoOrientation(),
        param_set;                          # Parameter set corresponding to earth parameters
        turbulence = Vreman(_C_smag),       # Turbulence closure model
        moisture = DryModel(),
        source = (),
        init_state_conservative = init_greenvortex!,             # Apply the initial condition
    )

    # Finally,  we pass a `Problem Name` string, the mesh information, and the model type to  the [`AtmosLESConfiguration`] object.
    config = ClimateMachine.AtmosLESConfiguration(
        "GreenVortex",       # Problem title [String]
        N,                       # Polynomial order [Int]
        resolution,              # (Δx, Δy, Δz) effective resolution [m]
        xmax,                    # Domain maximum size [m]
        ymax,                    # Domain maximum size [m]
        zmax,                    # Domain maximum size [m]
        param_set,               # Parameter set.
        init_greenvortex!,      # Function specifying initial condition
        boundary = ((0, 0), (0, 0), (0, 0)),
        periodicity = (true, true, true),
        xmin = xmin,
        ymin = ymin,
        zmin = zmin,
        solver_type = ode_solver,# Time-integrator type
        model = model,           # Model type
    )
    return config
end
# Here we define the diagnostic configuration specific to this problem.
function config_diagnostics(driver_config)
    interval = "10000steps"
    dgngrp = setup_atmos_default_diagnostics(interval, driver_config.name)
    return ClimateMachine.DiagnosticsConfiguration([dgngrp])
end

function main()
    ClimateMachine.init()

    FT = Float64
    N = 4
    Ncellsx = 64
    Ncellsy = 64
    Ncellsz = 64
    Δx = FT(2 * pi / Ncellsx)
    Δy = Δx
    Δz = Δx
    resolution = (Δx, Δy, Δz)
    xmax = FT(pi)
    ymax = FT(pi)
    zmax = FT(pi)
    xmin = FT(-pi)
    ymin = FT(-pi)
    zmin = FT(-pi)
    t0 = FT(0)
    timeend = FT(0.5)
    CFL = FT(1.8)

    driver_config = config_greenvortex(
        FT,
        N,
        resolution,
        xmax,
        ymax,
        zmax,
        xmin,
        ymin,
        zmin,
    )
    solver_config = ClimateMachine.SolverConfiguration(
        t0,
        timeend,
        driver_config,
        init_on_cpu = true,
        Courant_number = CFL,
    )
    dgn_config = config_diagnostics(driver_config)

    cbtmarfilter = GenericCallbacks.EveryXSimulationSteps(1) do (init = false)
        Filters.apply!(solver_config.Q, 6, solver_config.dg.grid, TMARFilter())
        nothing
    end
    # information.
    result = ClimateMachine.invoke!(
        solver_config;
        diagnostics_config = dgn_config,
        check_euclidean_distance = true,
    )

end

main()
