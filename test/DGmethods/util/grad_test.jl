include(joinpath("..", "..", "shared", "DGDriverPrep.jl"))

@inline function auxiliary_state_initialization!(aux, x, y, z, dim)
  @inbounds begin
    if dim == 2
      aux[1] = x^2 + y^3 - x*y
      aux[5] = 2*x - y
      aux[6] = 3*y^2 - x
      aux[7] = 0
    else
      aux[1] = x^2 + y^3 + z^2*y^2 - x*y*z
      aux[5] = 2*x - y*z
      aux[6] = 3*y^2 + 2*z^2*y - x*z
      aux[7] = 2*z*y^2 - x*y
    end
  end
end

using Test
function run(mpicomm, dim, ArrayType, Ne, N, DFloat)

  brickrange = ntuple(j->range(DFloat(-1); length=Ne[j]+1, stop=1), dim)
  topl = BrickTopology(mpicomm, brickrange, periodicity=ntuple(j->true, dim))

  grid = DiscontinuousSpectralElementGrid(topl,
                                          FloatType = DFloat,
                                          DeviceArray = ArrayType,
                                          polynomialorder = N,
                                         )

  spacedisc = DGBalanceLaw(grid = grid,
                           length_state_vector = 0,
                           flux! = (x...) -> (),
                           numerical_flux! = (x...) -> (),
                           auxiliary_state_length = 7,
                           auxiliary_state_initialization! = (x...) ->
                           auxiliary_state_initialization!(x..., dim))

  DGBalanceLawDiscretizations.grad_auxiliary_state!(spacedisc, 1, (2,3,4))

  # Wrapping in Array ensure both GPU and CPU code use same approx
  @test Array(spacedisc.auxstate.Q[:, 2, :]) ≈ Array(spacedisc.auxstate.Q[:, 5, :])
  @test Array(spacedisc.auxstate.Q[:, 3, :]) ≈ Array(spacedisc.auxstate.Q[:, 6, :])
  @test Array(spacedisc.auxstate.Q[:, 4, :]) ≈ Array(spacedisc.auxstate.Q[:, 7, :])
end

let
  include(joinpath("..", "..", "shared", "PrepLogger.jl"))

  numelem = (5, 5, 1)
  lvls = 1

  polynomialorder = 4

  @testset "$(@__FILE__)" for ArrayType in ArrayTypes
    for DFloat in (Float64,) #Float32)
      for dim = 2:3
        err = zeros(DFloat, lvls)
        for l = 1:lvls
          @info (ArrayType, DFloat, dim)
          run(mpicomm, dim, ArrayType, ntuple(j->2^(l-1) * numelem[j], dim),
              polynomialorder, DFloat)
        end
      end
    end
  end
end

isinteractive() || MPI.Finalize()

nothing
