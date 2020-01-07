module CLIMA

include("misc.jl")
include("Utilities/TicToc/TicToc.jl")
include("Utilities/ParametersType/ParametersType.jl")
include("Utilities/FreeParameters/FreeParameters.jl")
include("Common/PlanetParameters/PlanetParameters.jl")
include("Utilities/RootSolvers/RootSolvers.jl")
include("Utilities/VariableTemplates/VariableTemplates.jl")
include("Common/MoistThermodynamics/MoistThermodynamics.jl")
include("Atmos/Parameterizations/CloudPhysics/MicrophysicsParameters.jl")
include("Atmos/Parameterizations/CloudPhysics/Microphysics.jl")
include("Atmos/Parameterizations/SurfaceFluxes/SurfaceFluxes.jl")
include("Atmos/Parameterizations/TurbulenceConvection/TurbulenceConvection.jl")
include("Atmos/Parameterizations/SubgridScaleTurbulence/SubgridScaleParameters.jl")
include("Arrays/MPIStateArrays.jl")
include("Mesh/Mesh.jl")
include("DGmethods/SpaceMethods.jl")
include("DGmethods/DGmethods.jl")
include("Ocean/Model/ShallowWaterModel.jl")
include("Ocean/Model/HydrostaticBoussinesqModel.jl")
include("DGmethods_old/DGBalanceLawDiscretizations.jl")
include("LinearSolvers/LinearSolvers.jl")
include("LinearSolvers/GeneralizedConjugateResidualSolver.jl")
include("LinearSolvers/GeneralizedMinimalResidualSolver.jl")
include("LinearSolvers/ColumnwiseLUSolver.jl")
include("ODESolvers/ODESolvers.jl")
include("ODESolvers/LowStorageRungeKuttaMethod.jl")
include("ODESolvers/StrongStabilityPreservingRungeKuttaMethod.jl")
include("ODESolvers/AdditiveRungeKuttaMethod.jl")
include("ODESolvers/MultirateInfinitesimalStepMethod.jl")
include("ODESolvers/MultirateRungeKuttaMethod.jl")
include("ODESolvers/GenericCallbacks.jl")
include("Atmos/Model/AtmosModel.jl")
include("Diagnostics/Diagnostics.jl")
include("InputOutput/VTK/VTK.jl")

end
