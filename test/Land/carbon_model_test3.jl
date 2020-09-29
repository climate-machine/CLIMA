# # Heat equation tutorial

# In this tutorial, we'll be solving the [heat
# equation](https://en.wikipedia.org/wiki/Heat_equation):

# ``
# \frac{∂ ρcT}{∂ t} + ∇ ⋅ (-α ∇ρcT) = 0
# ``

# where
#  - `t` is time
#  - `α` is the thermal diffusivity
#  - `T` is the temperature
#  - `ρ` is the density
#  - `c` is the heat capacity
#  - `ρcT` is the thermal energy

# To put this in the form of ClimateMachine's [`BalanceLaw`](@ref
# ClimateMachine.BalanceLaws.BalanceLaw), we'll re-write the equation as:

# ``
# \frac{∂ ρcT}{∂ t} + ∇ ⋅ (F(α, ρcT, t)) = 0
# ``

# where
#  - ``F(α, ρcT, t) = -α ∇ρcT`` is the second-order flux

# with boundary conditions
#  - Fixed temperature ``T_{surface}`` at ``z_{min}`` (non-zero Dirichlet)
#  - No thermal flux at ``z_{min}`` (zero Neumann)

# Solving these equations is broken down into the following steps:
# 1) Preliminary configuration
# 2) PDEs
# 3) Space discretization
# 4) Time discretization / solver
# 5) Solver hooks / callbacks
# 6) Solve
# 7) Post-processing

# # Preliminary configuration

# ## [Loading code](@id Loading-code-heat)

# First, we'll load our pre-requisites:
#  - load external packages:
using MPI
using OrderedCollections
using Plots
using StaticArrays
using OrdinaryDiffEq
using DiffEqBase

#  - load CLIMAParameters and set up to use it:

using CLIMAParameters
struct EarthParameterSet <: AbstractEarthParameterSet end
const param_set = EarthParameterSet()

#  - load necessary ClimateMachine modules:
using ClimateMachine
using ClimateMachine.Mesh.Topologies
using ClimateMachine.Mesh.Grids
using ClimateMachine.DGMethods
using ClimateMachine.DGMethods.NumericalFluxes
using ClimateMachine.BalanceLaws:
    BalanceLaw, Prognostic, Auxiliary, Gradient, GradientFlux

using ClimateMachine.Mesh.Geometry: LocalGeometry
using ClimateMachine.MPIStateArrays
using ClimateMachine.GenericCallbacks
using ClimateMachine.ODESolvers
using ClimateMachine.VariableTemplates
using ClimateMachine.SingleStackUtils

#  - import necessary ClimateMachine modules: (`import`ing enables us to
#  provide implementations of these structs/methods)
import ClimateMachine.BalanceLaws:
    vars_state,
    source!,
    flux_second_order!,
    flux_first_order!,
    compute_gradient_argument!,
    compute_gradient_flux!,
    update_auxiliary_state!,
    nodal_update_auxiliary_state!,
    init_state_auxiliary!,
    init_state_prognostic!,
    boundary_state!

import ClimateMachine.DGMethods: calculate_dt

# ## Initialization

# Define the float type (`Float64` or `Float32`)
FT = Float64;
# Initialize ClimateMachine for CPU.
ClimateMachine.init(; disable_gpu = true);

const clima_dir = dirname(dirname(pathof(ClimateMachine)));

# Load some helper functions for plotting
include(joinpath(clima_dir, "docs", "plothelpers.jl"));

# # Define the set of Partial Differential Equations (PDEs)

# ## Define the model

# Model parameters can be stored in the particular [`BalanceLaw`](@ref
# ClimateMachine.BalanceLaws.BalanceLaw), in this case, a `HeatModel`:

Base.@kwdef struct CarbonModel{FT, APS} <: BalanceLaw
    "Parameters"
    param_set::APS
    "Initial B (biomass) (g carbon/m^2)"
    B_init::FT = 5000
    "Initial S (soil) (g carbon/m^2)"
    S_init::FT = 20000
    "Net primary production (g carbon/m^2/yr)"
    NPP::FT = 295.15
    "k_1 (1/yr)"
    k_1::FT = 0.1*1
    "k_2 (1/yr)"
    k_2::FT = 0.02*1
    "Diffusivity (units?)"
    D::FT = 0.001
end

# Create an instance of the `HeatModel`:
m = CarbonModel{FT, typeof(param_set)}(; param_set = param_set);

# This model dictates the flow control, using [Dynamic Multiple
# Dispatch](https://en.wikipedia.org/wiki/Multiple_dispatch), for which
# kernels are executed.

# ## Define the variables

# All of the methods defined in this section were `import`ed in
# [Loading code](@ref Loading-code-heat) to let us provide
# implementations for our `HeatModel` as they will be used by
# the solver.

# Specify auxiliary variables for `CarbonModel`
vars_state(::CarbonModel, ::Auxiliary, FT) = @vars(z::FT, Sk_2::FT);

# Specify state variables, the variables solved for in the PDEs, for
# `CarbonModel`
vars_state(::CarbonModel, ::Prognostic, FT) = @vars(B::FT, S::FT);

# Specify state variables whose gradients are needed for `CarbonModel`
vars_state(::CarbonModel, ::Gradient, FT) = @vars();

# Specify gradient variables for `CarbonModel`
vars_stat(::CarbonModel, ::GradientFlux, FT) = @vars();

# ## Define the compute kernels

# Specify the initial values in `aux::Vars`, which are available in
# `init_state_prognostic!`. Note that
# - this method is only called at `t=0`
# - `aux.z` and `aux.T` are available here because we've specified `z` and `T`
# in `vars_state` given `Auxiliary`
# in `vars_state`
function carbon_eq_nodal_init_state_auxiliary!(
    m::CarbonModel,
    aux::Vars,
    tmp::Vars,
    geom::LocalGeometry,
)
    aux.z = geom.coord[3]
    aux.Sk_2 = m.S_init*m.k_2
end;

function init_state_auxiliary!(
    m::CarbonModel,
    state_auxiliary::MPIStateArray,
    grid,
)
    nodal_init_state_auxiliary!(
        m,
        carbon_eq_nodal_init_state_auxiliary!,
        state_auxiliary,
        grid,
    )
end

# Specify the initial values in `state::Vars`. Note that
# - this method is only called at `t=0`
# - `state.ρcT` is available here because we've specified `ρcT` in
# `vars_state` given `Prognostic`
function init_state_prognostic!(
    m::CarbonModel,
    state::Vars,
    aux::Vars,
    coords,
    t::Real,
)
    state.B = m.B_init
    state.S = m.S_init
end;

# The remaining methods, defined in this section, are called at every
# time-step in the solver by the [`BalanceLaw`](@ref
# ClimateMachine.BalanceLaws.BalanceLaw) framework.

# Overload `update_auxiliary_state!` to call `heat_eq_nodal_update_aux!`, or
# any other auxiliary methods
function update_auxiliary_state!(
    dg::DGModel,
    m::CarbonModel,
    Q::MPIStateArray,
    t::Real,
    elems::UnitRange,
)
    nodal_update_auxiliary_state!(Carbon_eq_nodal_update_aux!, dg, m, Q, t, elems)
end;

# Compute/update all auxiliary variables at each node. Note that
# - `aux.T` is available here because we've specified `T` in
# `vars_state` given `Auxiliary`
function Carbon_eq_nodal_update_aux!(
    m::CarbonModel,
    state::Vars,
    aux::Vars,
    t::Real,
)
   aux.Sk_2 = state.S * m.k_2
end;

# Since we have second-order fluxes, we must tell `ClimateMachine` to compute
# the gradient of `ρcT`. Here, we specify how `ρcT` is computed. Note that
#  - `transform.ρcT` is available here because we've specified `ρcT` in
#  `vars_state` given `Gradient`
function compute_gradient_argument!(
    m::CarbonModel,
    transform::Vars,
    state::Vars,
    aux::Vars,
    t::Real,
)
end;

# Specify where in `diffusive::Vars` to store the computed gradient from
# `compute_gradient_argument!`. Note that:
#  - `diffusive.α∇ρcT` is available here because we've specified `α∇ρcT` in
#  `vars_state` given `Gradient`
#  - `∇transform.ρcT` is available here because we've specified `ρcT`  in
#  `vars_state` given `Gradient`
function compute_gradient_flux!(
    m::CarbonModel,
    diffusive::Vars,
    ∇transform::Grad,
    state::Vars,
    aux::Vars,
    t::Real,
)
end;

# We have no sources, nor non-diffusive fluxes.
function source!(
    m::CarbonModel,
    source::Vars,
    state::Vars,
    diffusive::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    Bk_1 = state.B*m.k_1
    source.B = m.NPP - Bk_1
    source.S = Bk_1 - aux.Sk_2
end;

function flux_first_order!(m::CarbonModel, _...) end;

# Compute diffusive flux (``F(α, ρcT, t) = -α ∇ρcT`` in the original PDE).
# Note that:
# - `diffusive.α∇ρcT` is available here because we've specified `α∇ρcT` in
# `vars_state` given `GradientFlux`
function flux_second_order!(
    m::CarbonModel,
    flux::Grad,
    state::Vars,
    diffusive::Vars,
    hyperdiffusive::Vars,
    aux::Vars,
    t::Real,
)
end;

# ### Boundary conditions

# Second-order terms in our equations, ``∇⋅(F)`` where ``F = -α∇ρcT``, are
# internally reformulated to first-order unknowns.
# Boundary conditions must be specified for all unknowns, both first-order and
# second-order unknowns which have been reformulated.

# The boundary conditions for `ρcT` (first order unknown)
function boundary_state!(
    nf,
    m::CarbonModel,
    state⁺::Vars,
    aux⁺::Vars,
    n⁻,
    state⁻::Vars,
    aux⁻::Vars,
    bctype,
    t,
    _...,
)
end;

# The boundary conditions for `ρcT` are specified here for second-order
# unknowns
function boundary_state!(
    nf,
    m::CarbonModel,
    state⁺::Vars,
    diff⁺::Vars,
    aux⁺::Vars,
    n⁻,
    state⁻::Vars,
    diff⁻::Vars,
    aux⁻::Vars,
    bctype,
    t,
    _...,
)
end;

# # Spatial discretization

# Prescribe polynomial order of basis functions in finite elements
N_poly = 5;

# Specify the number of vertical elements
nelem_vert = 10;

# Specify the domain height
zmax = FT(1);

# Establish a `ClimateMachine` single stack configuration
driver_config = ClimateMachine.SingleStackConfiguration(
    "HeatEquation",
    N_poly,
    nelem_vert,
    zmax,
    param_set,
    m,
    numerical_flux_first_order = CentralNumericalFluxFirstOrder(),
);

# # Time discretization / solver

# Specify simulation time (SI units)
t0 = FT(0)
timeend = FT(100)
#dt = FT(10)

# In this section, we initialize the state vector and allocate memory for
# the solution in space (`dg` has the model `m`, which describes the PDEs
# as well as the function used for initialization). `SolverConfiguration`
# initializes the ODE solver, by default an explicit Low-Storage
# [Runge-Kutta](https://en.wikipedia.org/wiki/Runge%E2%80%93Kutta_methods)
# method. In this tutorial, we prescribe an option for an implicit
# `Kvaerno3` method.

# First, let's define how the time-step is computed, based on the
# [Fourier number](https://en.wikipedia.org/wiki/Fourier_number)
# (i.e., diffusive Courant number) is defined. Because
# the `HeatModel` is a custom model, we must define how both are computed.
# First, we must define our own implementation of `DGMethods.calculate_dt`,
# (which we imported):
function calculate_dt(dg, model::CarbonModel, Q, Courant_number, t, direction)
    Δt = one(eltype(Q))
    CFL = DGMethods.courant(diffusive_courant, dg, model, Q, Δt, t, direction)
    return Courant_number / CFL
end

# Next, we'll define our implementation of `diffusive_courant`:
function diffusive_courant(
    m::CarbonModel,
    state::Vars,
    aux::Vars,
    diffusive::Vars,
    Δx,
    Δt,
    t,
    direction,
)
    return Δt * m.D / (Δx * Δx)
end

# Finally, we initialize the state vector and solver
# configuration based on the given Fourier number.
# Note that, we can use a much larger Fourier number
# for implicit solvers as compared to explicit solvers.
use_implicit_solver = false
if use_implicit_solver
    given_Fourier = FT(30)

    solver_config = ClimateMachine.SolverConfiguration(
        t0,
        timeend,
        driver_config;
        ode_solver_type = ImplicitSolverType(OrdinaryDiffEq.Kvaerno3(
            autodiff = false,
            linsolve = LinSolveGMRES(),
        )),
        Courant_number = given_Fourier,
        CFL_direction = VerticalDirection(),
    )
else
    given_Fourier = FT(0.7)

    solver_config = ClimateMachine.SolverConfiguration(
        t0,
        timeend,
        driver_config;
        Courant_number = given_Fourier,
        CFL_direction = VerticalDirection(),
    )
end;


grid = solver_config.dg.grid;
Q = solver_config.Q;
aux = solver_config.dg.state_auxiliary;

# ## Inspect the initial conditions

# Let's export a plot of the initial state
output_dir = @__DIR__;

mkpath(output_dir);

z_scale = 100; # convert from meters to cm
z_key = "z";
z_label = "z [cm]";
z = get_z(grid, z_scale);

# Create an array to store the solution:
all_data = Dict[dict_of_nodal_states(solver_config, [z_key])]  # store initial condition at ``t=0``
time_data = FT[0]                                      # store time data

export_plot(
    z,
    all_data,
    ("B", "S",),
    joinpath(output_dir, "initial_condition.png"),
    xlabel = "g carbon/m^2",
    ylabel = z_label,
    time_data = time_data,
);
# ![](initial_condition.png)

# It matches what we have in `init_state_prognostic!(m::HeatModel, ...)`, so
# let's continue.

# # Solver hooks / callbacks

# Define the number of outputs from `t0` to `timeend`
const n_outputs = 20;

# This equates to exports every ceil(Int, timeend/n_outputs) time-step:
const every_x_simulation_time = ceil(Int, timeend / n_outputs);

# The `ClimateMachine`'s time-steppers provide hooks, or callbacks, which
# allow users to inject code to be executed at specified intervals. In this
# callback, a dictionary of prognostic and auxiliary states are appended to
# `all_data` for time the callback is executed. In addition, time is collected
# and appended to `time_data`.
callback = GenericCallbacks.EveryXSimulationTime(every_x_simulation_time) do
    push!(all_data, dict_of_nodal_states(solver_config, [z_key]))
    push!(time_data, gettime(solver_config.solver))
    nothing
end;

# # Solve

# This is the main `ClimateMachine` solver invocation. While users do not have
# access to the time-stepping loop, code may be injected via `user_callbacks`,
# which is a `Tuple` of callbacks in [`GenericCallbacks`](@ref ClimateMachine.GenericCallbacks).
ClimateMachine.invoke!(solver_config; user_callbacks = (callback,));

# Append result at the end of the last time step:
push!(all_data, dict_of_nodal_states(solver_config, [z_key]));
push!(time_data, gettime(solver_config.solver));

# # Post-processing

# Our solution is stored in the array of dictionaries `all_data` whose keys are
# the output interval. The next level keys are the variable names, and the
# values are the values along the grid:

# To get `T` at ``t=0``, we can use `T_at_t_0 = all_data[1]["T"][:]`
@show keys(all_data[1])

# Let's plot the solution:

S_vs_t = [all_data[i]["S"][1] for i in keys(all_data)]
B_vs_t = [all_data[i]["B"][1] for i in keys(all_data)]
plot(time_data, B_vs_t, label = "B")
plot!(time_data, S_vs_t, label = "S")
savefig(joinpath(output_dir, "sol_vs_time.png"))
# ![](solution_vs_time.png)

# The results look as we would expect: a fixed temperature at the bottom is
# resulting in heat flux that propagates up the domain. To run this file, and
# inspect the solution in `all_data`, include this tutorial in the Julia REPL
# with:

# ```julia
# include(joinpath("tutorials", "Land", "Heat", "heat_equation.jl"))
# ```
