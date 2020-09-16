####
#### Defines list of how-to-guides
####

how_to_guides = Any[
    "Common" => Any["Thermodynamics" => "HowToGuides/Common/Thermodynamics.md",],
    "Atmos" => Any[
        "Temperature profiles" => "HowToGuides/Atmos/TemperatureProfiles.md",
        "Reference profiles" => "HowToGuides/Atmos/AtmosReferenceState.md",
    ],
    "Ocean" => Any[
    # "Home" => "HowToGuides/Ocean/index.md"
    ],
    "Land" => Any[
    # "Home" => "HowToGuides/Land/index.md"
    ],
    "Numerics" => Any[
        "Meshes" => Any[
        # "Home" => "HowToGuides/Numerics/Meshes/index.md",
        ],
        "DG methods" => Any[
            "How to make a balance law" => "HowToGuides/Numerics/DGMethods/how_to_make_a_balance_law.md",
            "RHS evaluation sequence" => "HowToGuides/Numerics/DGMethods/rhs_sequence.md",
        ],
        "ODE Solvers" => Any["Time-integration" => "HowToGuides/Numerics/ODESolvers/Timestepping.md",],
        "System Solvers" => Any["Iterative Solvers" => "HowToGuides/Numerics/SystemSolvers/IterativeSolvers.md",],
    ],
]
