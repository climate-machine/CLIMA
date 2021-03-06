using ClimateMachine.VariableTemplates: Vars, Grad, @vars
using ClimateMachine.BalanceLaws
import ClimateMachine.BalanceLaws:
    BalanceLaw,
    vars_state,
    state_to_entropy_variables!,
    entropy_variables_to_state!,
    nodal_init_state_auxiliary!,
    init_state_prognostic!,
    state_to_entropy,
    boundary_conditions,
    boundary_state!,
    wavespeed,
    flux_first_order!,
    source!

using StaticArrays
using LinearAlgebra: dot, I
using ClimateMachine.DGMethods.NumericalFluxes: NumericalFluxFirstOrder
import ClimateMachine.DGMethods.NumericalFluxes:
    EntropyConservative,
    numerical_volume_conservative_flux_first_order!,
    numerical_volume_fluctuation_flux_first_order!,
    ave,
    logave,
    numerical_flux_first_order!,
    numerical_flux_second_order!,
    numerical_boundary_flux_second_order!

using ClimateMachine.Orientations:
    Orientation, FlatOrientation, SphericalOrientation
using ClimateMachine.Atmos: NoReferenceState
using ClimateMachine.Grids

using CLIMAParameters: AbstractEarthParameterSet
using CLIMAParameters.Planet: grav, R_d, cp_d, cv_d, planet_radius, MSLP, Omega

struct EarthParameterSet <: AbstractEarthParameterSet end
const param_set = EarthParameterSet()

const total_energy = false
const fluctuation_gravity = false

@inline gamma(ps::EarthParameterSet) = cp_d(ps) / cv_d(ps)

abstract type AbstractDryAtmosProblem end

struct DryAtmosModel{D, O, P, RS, S, DS} <: BalanceLaw
    orientation::O
    problem::P
    ref_state::RS
    sources::S
    drag_source::DS
end
function DryAtmosModel{D}(
    orientation,
    problem::AbstractDryAtmosProblem;
    ref_state = NoReferenceState(),
    sources = (),
    drag_source = NoDrag(),
) where {D}
    O = typeof(orientation)
    P = typeof(problem)
    RS = typeof(ref_state)
    S = typeof(sources)
    DS = typeof(drag_source)
    DryAtmosModel{D, O, P, RS, S, DS}(
        orientation,
        problem,
        ref_state,
        sources,
        drag_source,
    )
end

boundary_conditions(::DryAtmosModel) = (1, 2)
# XXX: Hack for Impenetrable.
#      This is NOT entropy stable / conservative!!!!
function boundary_state!(
    ::NumericalFluxFirstOrder,
    bctype,
    ::DryAtmosModel,
    state⁺,
    aux⁺,
    n,
    state⁻,
    aux⁻,
    _...,
)
    state⁺.ρ = state⁻.ρ
    state⁺.ρu -= 2 * dot(state⁻.ρu, n) .* SVector(n)
    state⁺.ρe = state⁻.ρe
    aux⁺.Φ = aux⁻.Φ
end

function init_state_prognostic!(m::DryAtmosModel, args...)
    init_state_prognostic!(m, m.problem, args...)
end

function nodal_init_state_auxiliary!(
    m::DryAtmosModel,
    state_auxiliary,
    tmp,
    geom,
)
    init_state_auxiliary!(m, m.orientation, state_auxiliary, geom)
    init_state_auxiliary!(m, m.ref_state, state_auxiliary, geom)
    init_state_auxiliary!(m, m.problem, state_auxiliary, geom)
end

function altitude(::DryAtmosModel{dim}, ::FlatOrientation, geom) where {dim}
    @inbounds geom.coord[dim]
end

function altitude(::DryAtmosModel, ::SphericalOrientation, geom)
    FT = eltype(geom)
    _planet_radius::FT = planet_radius(param_set)
    norm(geom.coord) - _planet_radius
end

"""
    init_state_auxiliary!(
        m::DryAtmosModel,
        aux::Vars,
        geom::LocalGeometry
        )

Initialize geopotential for the `DryAtmosModel`.
"""
function init_state_auxiliary!(
    ::DryAtmosModel{dim},
    ::FlatOrientation,
    state_auxiliary,
    geom,
) where {dim}
    FT = eltype(state_auxiliary)
    _grav = FT(grav(param_set))
    @inbounds r = geom.coord[dim]
    state_auxiliary.Φ = _grav * r
    state_auxiliary.∇Φ =
        dim == 2 ? SVector{3, FT}(0, _grav, 0) : SVector{3, FT}(0, 0, _grav)
end
function init_state_auxiliary!(
    ::DryAtmosModel,
    ::SphericalOrientation,
    state_auxiliary,
    geom,
)
    FT = eltype(state_auxiliary)
    _grav = FT(grav(param_set))
    r = norm(geom.coord)
    state_auxiliary.Φ = _grav * r
    state_auxiliary.∇Φ = _grav * geom.coord / r
end

function init_state_auxiliary!(
    ::DryAtmosModel,
    ::NoReferenceState,
    state_auxiliary,
    geom,
) end

function init_state_auxiliary!(
    ::DryAtmosModel,
    ::AbstractDryAtmosProblem,
    state_auxiliary,
    geom,
) end

struct DryReferenceState{TP}
    temperature_profile::TP
end
vars_state(::DryAtmosModel, ::DryReferenceState, ::Auxiliary, FT) =
    @vars(T::FT, p::FT, ρ::FT, ρe::FT)
vars_state(::DryAtmosModel, ::NoReferenceState, ::Auxiliary, FT) = @vars()

function init_state_auxiliary!(
    m::DryAtmosModel,
    ref_state::DryReferenceState,
    state_auxiliary,
    geom,
)
    FT = eltype(state_auxiliary)
    z = altitude(m, m.orientation, geom)
    T, p = ref_state.temperature_profile(param_set, z)

    _R_d::FT = R_d(param_set)
    ρ = p / (_R_d * T)
    Φ = state_auxiliary.Φ
    ρu = SVector{3, FT}(0, 0, 0)

    state_auxiliary.ref_state.T = T
    state_auxiliary.ref_state.p = p
    state_auxiliary.ref_state.ρ = ρ
    state_auxiliary.ref_state.ρe = totalenergy(ρ, ρu, p, Φ)
end

@inline function flux_first_order!(
    m::DryAtmosModel,
    flux::Grad,
    state::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    ρ = state.ρ
    ρinv = 1 / ρ
    ρu = state.ρu
    ρe = state.ρe
    u = ρinv * ρu
    Φ = aux.Φ

    p = pressure(ρ, ρu, ρe, Φ)

    flux.ρ = ρ * u
    flux.ρu = p * I + ρ * u .* u'
    flux.ρe = u * (state.ρe + p)
end

function wavespeed(
    ::DryAtmosModel,
    nM,
    state::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    ρ = state.ρ
    ρu = state.ρu
    ρe = state.ρe
    Φ = aux.Φ
    p = pressure(ρ, ρu, ρe, Φ)

    u = ρu / ρ
    uN = abs(dot(nM, u))
    return uN + soundspeed(ρ, p)
end

"""
    pressure(ρ, ρu, ρe, Φ)

Compute the pressure given density `ρ`, momentum `ρu`, total energy `ρe`, and
gravitational potential `Φ`.
"""
function pressure(ρ, ρu, ρe, Φ)
    FT = eltype(ρ)
    γ = FT(gamma(param_set))
    if total_energy
        (γ - 1) * (ρe - dot(ρu, ρu) / 2ρ - ρ * Φ)
    else
        (γ - 1) * (ρe - dot(ρu, ρu) / 2ρ)
    end
end

"""
    totalenergy(ρ, ρu, p, Φ)

Compute the total energy given density `ρ`, momentum `ρu`, pressure `p`, and
gravitational potential `Φ`.
"""
function totalenergy(ρ, ρu, p, Φ)
    FT = eltype(ρ)
    γ = FT(gamma(param_set))
    if total_energy
        return p / (γ - 1) + dot(ρu, ρu) / 2ρ + ρ * Φ
    else
        return p / (γ - 1) + dot(ρu, ρu) / 2ρ
    end
end

"""
    soundspeed(ρ, p)

Compute the speed of sound from the density `ρ` and pressure `p`.
"""
function soundspeed(ρ, p)
    FT = eltype(ρ)
    γ = FT(gamma(param_set))
    sqrt(γ * p / ρ)
end

"""
    vars_state(::DryAtmosModel, ::Prognostic, FT)

The prognostic state variables for the `DryAtmosModel` are density `ρ`, momentum `ρu`,
and total energy `ρe`
"""
function vars_state(::DryAtmosModel, ::Prognostic, FT)
    @vars begin
        ρ::FT
        ρu::SVector{3, FT}
        ρe::FT
    end
end

"""
    vars_state(::DryAtmosModel, ::Auxiliary, FT)

The auxiliary variables for the `DryAtmosModel` is gravitational potential
`Φ`
"""
function vars_state(m::DryAtmosModel, st::Auxiliary, FT)
    @vars begin
        Φ::FT
        ∇Φ::SVector{3, FT} # TODO: only needed for the linear model
        ref_state::vars_state(m, m.ref_state, st, FT)
        problem::vars_state(m, m.problem, st, FT)
    end
end
vars_state(::DryAtmosModel, ::AbstractDryAtmosProblem, ::Auxiliary, FT) =
    @vars()

"""
    vars_state(::DryAtmosModel, ::Entropy, FT)

The entropy variables for the `DryAtmosModel` correspond to the state
variables density `ρ`, momentum `ρu`, and total energy `ρe` as well as the
auxiliary variable gravitational potential `Φ`
"""
function vars_state(::DryAtmosModel, ::Entropy, FT)
    @vars begin
        ρ::FT
        ρu::SVector{3, FT}
        ρe::FT
        Φ::FT
    end
end

"""
    state_to_entropy_variables!(
        ::DryAtmosModel,
        entropy::Vars,
        state::Vars,
        aux::Vars,
    )

See [`BalanceLaws.state_to_entropy_variables!`](@ref)
"""
function state_to_entropy_variables!(
    ::DryAtmosModel,
    entropy::Vars,
    state::Vars,
    aux::Vars,
)
    ρ, ρu, ρe, Φ = state.ρ, state.ρu, state.ρe, aux.Φ

    FT = eltype(state)
    γ = FT(gamma(param_set))

    p = pressure(ρ, ρu, ρe, Φ)
    s = log(p / ρ^γ)
    b = ρ / 2p
    u = ρu / ρ

    if total_energy
        entropy.ρ = (γ - s) / (γ - 1) - (dot(u, u) - 2Φ) * b
    else
        entropy.ρ = (γ - s) / (γ - 1) - (dot(u, u)) * b
    end
    entropy.ρu = 2b * u
    entropy.ρe = -2b
    entropy.Φ = 2ρ * b
end

"""
    entropy_variables_to_state!(
        ::DryAtmosModel,
        state::Vars,
        aux::Vars,
        entropy::Vars,
    )

See [`BalanceLaws.entropy_variables_to_state!`](@ref)
"""
function entropy_variables_to_state!(
    ::DryAtmosModel,
    state::Vars,
    aux::Vars,
    entropy::Vars,
)
    FT = eltype(state)
    β = entropy
    γ = FT(gamma(param_set))

    b = -β.ρe / 2
    ρ = β.Φ / (2b)
    ρu = ρ * β.ρu / (2b)

    p = ρ / (2b)
    s = log(p / ρ^γ)
    Φ = dot(ρu, ρu) / (2 * ρ^2) - ((γ - s) / (γ - 1) - β.ρ) / (2b)

    ρe = p / (γ - 1) + dot(ρu, ρu) / (2ρ) + ρ * Φ

    state.ρ = ρ
    state.ρu = ρu
    state.ρe = ρe
    aux.Φ = Φ
end

function state_to_entropy(::DryAtmosModel, state::Vars, aux::Vars)
    FT = eltype(state)
    ρ, ρu, ρe, Φ = state.ρ, state.ρu, state.ρe, aux.Φ
    p = pressure(ρ, ρu, ρe, Φ)
    γ = FT(gamma(param_set))
    s = log(p / ρ^γ)
    η = -ρ * s / (γ - 1)
    return η
end

function numerical_volume_conservative_flux_first_order!(
    ::EntropyConservative,
    ::DryAtmosModel,
    F::Grad,
    state_1::Vars,
    aux_1::Vars,
    state_2::Vars,
    aux_2::Vars,
)
    FT = eltype(F)
    ρ_1, ρu_1, ρe_1 = state_1.ρ, state_1.ρu, state_1.ρe
    ρ_2, ρu_2, ρe_2 = state_2.ρ, state_2.ρu, state_2.ρe
    Φ_1, Φ_2 = aux_1.Φ, aux_2.Φ
    u_1 = ρu_1 / ρ_1
    u_2 = ρu_2 / ρ_2
    p_1 = pressure(ρ_1, ρu_1, ρe_1, Φ_1)
    p_2 = pressure(ρ_2, ρu_2, ρe_2, Φ_2)
    b_1 = ρ_1 / 2p_1
    b_2 = ρ_2 / 2p_2

    ρ_avg = ave(ρ_1, ρ_2)
    u_avg = ave(u_1, u_2)
    b_avg = ave(b_1, b_2)
    Φ_avg = ave(Φ_1, Φ_2)

    usq_avg = ave(dot(u_1, u_1), dot(u_2, u_2))

    ρ_log = logave(ρ_1, ρ_2)
    b_log = logave(b_1, b_2)
    α = b_avg * ρ_log / 2b_1

    γ = FT(gamma(param_set))

    Fρ = u_avg * ρ_log
    Fρu = u_avg * Fρ' + ρ_avg / 2b_avg * I
    if total_energy
        Fρe =
            (1 / (2 * (γ - 1) * b_log) - usq_avg / 2 + Φ_avg) * Fρ + Fρu * u_avg
    else
        Fρe = (1 / (2 * (γ - 1) * b_log) - usq_avg / 2) * Fρ + Fρu * u_avg
    end

    F.ρ += Fρ
    F.ρu += Fρu
    F.ρe += Fρe
end

function numerical_volume_fluctuation_flux_first_order!(
    ::NumericalFluxFirstOrder,
    ::DryAtmosModel,
    D::Grad,
    state_1::Vars,
    aux_1::Vars,
    state_2::Vars,
    aux_2::Vars,
)
    if fluctuation_gravity
        FT = eltype(D)
        ρ_1, ρu_1, ρe_1 = state_1.ρ, state_1.ρu, state_1.ρe
        ρ_2, ρu_2, ρe_2 = state_2.ρ, state_2.ρu, state_2.ρe
        Φ_1, Φ_2 = aux_1.Φ, aux_2.Φ
        p_1 = pressure(ρ_1, ρu_1, ρe_1, Φ_1)
        p_2 = pressure(ρ_2, ρu_2, ρe_2, Φ_2)
        b_1 = ρ_1 / 2p_1
        b_2 = ρ_2 / 2p_2

        ρ_log = logave(ρ_1, ρ_2)
        b_avg = ave(b_1, b_2)
        α = b_avg * ρ_log / 2b_1

        D.ρu -= α * (Φ_1 - Φ_2) * I
    end
end

struct CentralVolumeFlux <: NumericalFluxFirstOrder end
function numerical_volume_conservative_flux_first_order!(
    ::CentralVolumeFlux,
    m::DryAtmosModel,
    F::Grad,
    state_1::Vars,
    aux_1::Vars,
    state_2::Vars,
    aux_2::Vars,
)
    FT = eltype(F)
    F_1 = similar(F)
    flux_first_order!(m, F_1, state_1, aux_1, FT(0), EveryDirection())

    F_2 = similar(F)
    flux_first_order!(m, F_2, state_2, aux_2, FT(0), EveryDirection())

    parent(F) .= (parent(F_1) .+ parent(F_2)) ./ 2
end

struct KGVolumeFlux <: NumericalFluxFirstOrder end
function numerical_volume_conservative_flux_first_order!(
    ::KGVolumeFlux,
    m::DryAtmosModel,
    F::Grad,
    state_1::Vars,
    aux_1::Vars,
    state_2::Vars,
    aux_2::Vars,
)
    Φ_1 = aux_1.Φ
    ρ_1 = state_1.ρ
    ρu_1 = state_1.ρu
    ρe_1 = state_1.ρe
    u_1 = ρu_1 / ρ_1
    e_1 = ρe_1 / ρ_1
    p_1 = pressure(ρ_1, ρu_1, ρe_1, Φ_1)

    Φ_2 = aux_2.Φ
    ρ_2 = state_2.ρ
    ρu_2 = state_2.ρu
    ρe_2 = state_2.ρe
    u_2 = ρu_2 / ρ_2
    e_2 = ρe_2 / ρ_2
    p_2 = pressure(ρ_2, ρu_2, ρe_2, Φ_2)

    ρ_avg = ave(ρ_1, ρ_2)
    u_avg = ave(u_1, u_2)
    e_avg = ave(e_1, e_2)
    p_avg = ave(p_1, p_2)

    F.ρ = ρ_avg * u_avg
    F.ρu = p_avg * I + ρ_avg * u_avg .* u_avg'
    F.ρe = ρ_avg * u_avg * e_avg + p_avg * u_avg
end


struct Coriolis end
function source!(
    m::DryAtmosModel,
    ::Coriolis,
    source,
    state_prognostic,
    state_auxiliary,
)
    FT = eltype(state_prognostic)
    _Omega::FT = Omega(param_set)
    # note: this assumes a SphericalOrientation
    source.ρu -= SVector(0, 0, 2 * _Omega) × state_prognostic.ρu
end

function source!(m::DryAtmosModel, source, state_prognostic, state_auxiliary)
    ntuple(Val(length(m.sources))) do s
        Base.@_inline_meta
        source!(m, m.sources[s], source, state_prognostic, state_auxiliary)
    end
end


struct EntropyConservativeWithPenalty <: NumericalFluxFirstOrder end
function numerical_flux_first_order!(
    numerical_flux::EntropyConservativeWithPenalty,
    balance_law::BalanceLaw,
    fluxᵀn::Vars{S},
    normal_vector::SVector,
    state_prognostic⁻::Vars{S},
    state_auxiliary⁻::Vars{A},
    state_prognostic⁺::Vars{S},
    state_auxiliary⁺::Vars{A},
    t,
    direction,
) where {S, A}

    FT = eltype(fluxᵀn)

    numerical_flux_first_order!(
        EntropyConservative(),
        balance_law,
        fluxᵀn,
        normal_vector,
        state_prognostic⁻,
        state_auxiliary⁻,
        state_prognostic⁺,
        state_auxiliary⁺,
        t,
        direction,
    )
    fluxᵀn = parent(fluxᵀn)

    wavespeed⁻ = wavespeed(
        balance_law,
        normal_vector,
        state_prognostic⁻,
        state_auxiliary⁻,
        t,
        direction,
    )
    wavespeed⁺ = wavespeed(
        balance_law,
        normal_vector,
        state_prognostic⁺,
        state_auxiliary⁺,
        t,
        direction,
    )
    max_wavespeed = max.(wavespeed⁻, wavespeed⁺)
    penalty =
        max_wavespeed .* (parent(state_prognostic⁻) - parent(state_prognostic⁺))

    fluxᵀn .+= penalty / 2
end

Base.@kwdef struct MatrixFlux{FT} <: NumericalFluxFirstOrder
    Mcut::FT = 0
    low_mach::Bool = false
    kinetic_energy_preserving::Bool = false
end

function numerical_flux_first_order!(
    numerical_flux::MatrixFlux,
    balance_law::BalanceLaw,
    fluxᵀn::Vars{S},
    normal_vector::SVector,
    state_prognostic⁻::Vars{S},
    state_auxiliary⁻::Vars{A},
    state_prognostic⁺::Vars{S},
    state_auxiliary⁺::Vars{A},
    t,
    direction,
) where {S, A}

    FT = eltype(fluxᵀn)
    numerical_flux_first_order!(
        EntropyConservative(),
        balance_law,
        fluxᵀn,
        normal_vector,
        state_prognostic⁻,
        state_auxiliary⁻,
        state_prognostic⁺,
        state_auxiliary⁺,
        t,
        direction,
    )
    fluxᵀn = parent(fluxᵀn)

    γ = FT(gamma(param_set))

    low_mach = numerical_flux.low_mach
    Mcut = numerical_flux.Mcut
    kinetic_energy_preserving = numerical_flux.kinetic_energy_preserving

    ω = FT(π) / 3
    δ = FT(π) / 5
    random_unit_vector = SVector(sin(ω) * cos(δ), cos(ω) * cos(δ), sin(δ))
    # tangent space basis
    τ1 = random_unit_vector × normal_vector
    τ2 = τ1 × normal_vector

    ρ⁻ = state_prognostic⁻.ρ
    ρu⁻ = state_prognostic⁻.ρu
    ρe⁻ = state_prognostic⁻.ρe

    Φ⁻ = state_auxiliary⁻.Φ
    u⁻ = ρu⁻ / ρ⁻
    p⁻ = pressure(ρ⁻, ρu⁻, ρe⁻, Φ⁻)
    β⁻ = ρ⁻ / 2p⁻

    Φ⁺ = state_auxiliary⁺.Φ
    ρ⁺ = state_prognostic⁺.ρ
    ρu⁺ = state_prognostic⁺.ρu
    ρe⁺ = state_prognostic⁺.ρe

    u⁺ = ρu⁺ / ρ⁺
    p⁺ = pressure(ρ⁺, ρu⁺, ρe⁺, Φ⁺)
    β⁺ = ρ⁺ / 2p⁺

    ρ_log = logave(ρ⁻, ρ⁺)
    β_log = logave(β⁻, β⁺)
    if total_energy
        Φ_avg = ave(Φ⁻, Φ⁺)
    else
        Φ_avg = 0
    end
    u_avg = ave.(u⁻, u⁺)
    p_avg = ave(ρ⁻, ρ⁺) / 2ave(β⁻, β⁺)
    u²_bar = 2 * sum(u_avg .^ 2) - sum(ave(u⁻ .^ 2, u⁺ .^ 2))

    h_bar = γ / (2 * β_log * (γ - 1)) + u²_bar / 2 + Φ_avg
    c_bar = sqrt(γ * p_avg / ρ_log)

    umc = u_avg - c_bar * normal_vector
    upc = u_avg + c_bar * normal_vector
    u_avgᵀn = u_avg' * normal_vector
    R = hcat(
        SVector(1, umc[1], umc[2], umc[3], h_bar - c_bar * u_avgᵀn),
        SVector(1, u_avg[1], u_avg[2], u_avg[3], u²_bar / 2 + Φ_avg),
        SVector(0, τ1[1], τ1[2], τ1[3], τ1' * u_avg),
        SVector(0, τ2[1], τ2[2], τ2[3], τ2' * u_avg),
        SVector(1, upc[1], upc[2], upc[3], h_bar + c_bar * u_avgᵀn),
    )

    if low_mach
        M = abs(u_avg' * normal_vector) / c_bar
        c_bar *= max(min(M, FT(1)), Mcut)
    end

    if kinetic_energy_preserving
        λl = abs(u_avgᵀn) + c_bar
        λr = λl
    else
        λl = abs(u_avgᵀn - c_bar)
        λr = abs(u_avgᵀn + c_bar)
    end

    Λ = SDiagonal(λl, abs(u_avgᵀn), abs(u_avgᵀn), abs(u_avgᵀn), λr)
    #Ξ = sqrt(abs((p⁺ - p⁻) / (p⁺ + p⁻)))
    #Λ = Ξ * abs(u_avgᵀn + c_bar) * I + (1 - Ξ) * ΛM

    T = SDiagonal(ρ_log / 2γ, ρ_log * (γ - 1) / γ, p_avg, p_avg, ρ_log / 2γ)

    entropy⁻ = similar(parent(state_prognostic⁻), Size(6))
    state_to_entropy_variables!(
        balance_law,
        Vars{vars_state(balance_law, Entropy(), FT)}(entropy⁻),
        state_prognostic⁻,
        state_auxiliary⁻,
    )

    entropy⁺ = similar(parent(state_prognostic⁺), Size(6))
    state_to_entropy_variables!(
        balance_law,
        Vars{vars_state(balance_law, Entropy(), FT)}(entropy⁺),
        state_prognostic⁺,
        state_auxiliary⁺,
    )

    Δentropy = parent(entropy⁺) - parent(entropy⁻)

    fluxᵀn .-= R * Λ * T * R' * Δentropy[SOneTo(5)] / 2
end

function vertical_unit_vector(m::DryAtmosModel, aux::Vars)
    FT = eltype(aux)
    aux.∇Φ / FT(grav(param_set))
end

norm_u(state::Vars, k̂::AbstractVector, ::VerticalDirection) =
    abs(dot(state.ρu, k̂)) / state.ρ
norm_u(state::Vars, k̂::AbstractVector, ::HorizontalDirection) =
    norm((state.ρu .- dot(state.ρu, k̂) * k̂) / state.ρ)
norm_u(state::Vars, k̂::AbstractVector, ::Direction) = norm(state.ρu / state.ρ)

function advective_courant(
    m::DryAtmosModel,
    state::Vars,
    aux::Vars,
    diffusive::Vars,
    Δx,
    Δt,
    t,
    direction,
)
    k̂ = vertical_unit_vector(m, aux)
    normu = norm_u(state, k̂, direction)
    return Δt * normu / Δx
end

function nondiffusive_courant(
    m::DryAtmosModel,
    state::Vars,
    aux::Vars,
    diffusive::Vars,
    Δx,
    Δt,
    t,
    direction,
)
    ρ = state.ρ
    ρu = state.ρu
    ρe = state.ρe
    Φ = aux.Φ
    p = pressure(ρ, ρu, ρe, Φ)

    k̂ = vertical_unit_vector(m, aux)
    normu = norm_u(state, k̂, direction)
    ss = soundspeed(ρ, p)
    return Δt * (normu + ss) / Δx
end

function drag_source!(m::DryAtmosModel, args...)
    drag_source!(m, m.drag_source, args...)
end
struct NoDrag end
drag_source!(m::DryAtmosModel, ::NoDrag, args...) = nothing

struct Gravity end
function source!(m::DryAtmosModel, ::Gravity, source, state, aux)
    ∇Φ = aux.∇Φ
    if !fluctuation_gravity
        source.ρu -= state.ρ * ∇Φ
    end
    if !total_energy
        source.ρe -= state.ρu' * ∇Φ
    end
end

# Numerical Flux 
#=
numerical_flux_first_order!(::Nothing, _...) = nothing
numerical_boundary_flux_first_order!(::Nothing, _...) = nothing
numerical_flux_second_order!(::Nothing, _...) = nothing
numerical_boundary_flux_second_order!(::Nothing, _...) = nothing
=#
numerical_flux_first_order!(::Nothing, ::DryAtmosModel, _...) = nothing
numerical_flux_second_order!(::Nothing, ::DryAtmosModel, _...) = nothing
numerical_boundary_flux_second_order!(::Nothing, a, ::DryAtmosModel, _...) =
    nothing

include("linear.jl")

# Throwing this in for convenience
function cubedshellwarp(a, b, c, R = max(abs(a), abs(b), abs(c)))

    function f(sR, ξ, η)
        X, Y = tan(π * ξ / 4), tan(π * η / 4)
        x1 = sR / sqrt(X^2 + Y^2 + 1)
        x2, x3 = X * x1, Y * x1
        x1, x2, x3
    end

    fdim = argmax(abs.((a, b, c)))
    if fdim == 1 && a < 0
        # (-R, *, *) : Face I from Ronchi, Iacono, Paolucci (1996)
        x1, x2, x3 = f(-R, b / a, c / a)
    elseif fdim == 2 && b < 0
        # ( *,-R, *) : Face II from Ronchi, Iacono, Paolucci (1996)
        x2, x1, x3 = f(-R, a / b, c / b)
    elseif fdim == 1 && a > 0
        # ( R, *, *) : Face III from Ronchi, Iacono, Paolucci (1996)
        x1, x2, x3 = f(R, b / a, c / a)
    elseif fdim == 2 && b > 0
        # ( *, R, *) : Face IV from Ronchi, Iacono, Paolucci (1996)
        x2, x1, x3 = f(R, a / b, c / b)
    elseif fdim == 3 && c > 0
        # ( *, *, R) : Face V from Ronchi, Iacono, Paolucci (1996)
        x3, x2, x1 = f(R, b / c, a / c)
    elseif fdim == 3 && c < 0
        # ( *, *,-R) : Face VI from Ronchi, Iacono, Paolucci (1996)
        x3, x2, x1 = f(-R, b / c, a / c)
    else
        error("invalid case for cubedshellwarp: $a, $b, $c")
    end

    return x1, x2, x3
end
