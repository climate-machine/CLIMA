using ClimateMachine.Mesh.Elements
using GaussQuadrature
using LinearAlgebra
using Test

@testset "GaussQuadrature" begin
    for T in (Float32, Float64, BigFloat)
        let
            x, w = GaussQuadrature.legendre(T, 1)
            @test iszero(x)
            @test w ≈ [2 * one(T)]
        end

        let
            endpt = GaussQuadrature.left
            x, w = GaussQuadrature.legendre(T, 1, endpt)
            @test x ≈ [-one(T)]
            @test w ≈ [2 * one(T)]
        end

        let
            endpt = GaussQuadrature.right
            x, w = GaussQuadrature.legendre(T, 1, endpt)
            @test x ≈ [one(T)]
            @test w ≈ [2 * one(T)]
        end

        let
            endpt = GaussQuadrature.left
            x, w = GaussQuadrature.legendre(T, 2, endpt)
            @test x ≈ [-one(T); T(1 // 3)]
            @test w ≈ [T(1 // 2); T(3 // 2)]
        end

        let
            endpt = GaussQuadrature.right
            x, w = GaussQuadrature.legendre(T, 2, endpt)
            @test x ≈ [T(-1 // 3); one(T)]
            @test w ≈ [T(3 // 2); T(1 // 2)]
        end
    end

    let
        err = ErrorException("Must have at least two points for both ends.")
        endpt = GaussQuadrature.both
        @test_throws err GaussQuadrature.legendre(1, endpt)
    end

    let
        T = Float64
        n = 100
        endpt = GaussQuadrature.both

        a, b = GaussQuadrature.legendre_coefs(T, n)

        err = ErrorException(
            "No convergence after 1 iterations " * "(try increasing maxits)",
        )

        @test_throws err GaussQuadrature.custom_gauss_rule(
            -one(T),
            one(T),
            a,
            b,
            endpt,
            1,
        )
    end
end

@testset "Operators" begin
    P5(r::AbstractVector{T}) where {T} =
        T(1) / T(8) * (T(15) * r - T(70) * r .^ 3 + T(63) * r .^ 5)

    P6(r::AbstractVector{T}) where {T} =
        T(1) / T(16) *
        (-T(5) .+ T(105) * r .^ 2 - T(315) * r .^ 4 + T(231) * r .^ 6)
    DP6(r::AbstractVector{T}) where {T} =
        T(1) / T(16) *
        (T(2 * 105) * r - T(4 * 315) * r .^ 3 + T(6 * 231) * r .^ 5)

    IPN(::Type{T}, N) where {T} = T(2) / T(2 * N + 1)

    N = 6
    for test_type in (Float32, Float64, BigFloat)
        r, w = Elements.lglpoints(test_type, N)
        D = Elements.spectralderivative(r)
        x = LinRange{test_type}(-1, 1, 101)
        I = Elements.interpolationmatrix(r, x)

        @test sum(P5(r) .^ 2 .* w) ≈ IPN(test_type, 5)
        @test D * P6(r) ≈ DP6(r)
        @test I * P6(r) ≈ P6(x)
    end

    for test_type in (Float32, Float64, BigFloat)
        r, w = Elements.glpoints(test_type, N)
        D = Elements.spectralderivative(r)

        @test sum(P5(r) .^ 2 .* w) ≈ IPN(test_type, 5)
        @test sum(P6(r) .^ 2 .* w) ≈ IPN(test_type, 6)
        @test D * P6(r) ≈ DP6(r)
    end
end

@testset "Jacobip" begin
    for T in (Float32, Float64, BigFloat)
        let
            α, β, N = T(0), T(0), 3 # α, β (for Legendre polynomials) & polynomial order
            x, wt = Elements.lglpoints(T, N + 1) # lgl points for polynomial order N
            V = Elements.jacobip(α, β, N, x)
            # compare with orthonormalized exact solution
            # https://en.wikipedia.org/wiki/Legendre_polynomials
            V_exact = similar(V)
            V_exact[:, 1] .= 1
            V_exact[:, 2] .= x
            V_exact[:, 3] .= (3 * x .^ 2 .- 1) / 2
            V_exact[:, 4] .= (5 * x .^ 3 .- 3 * x) / 2
            scale = 1 ./ sqrt.(diag(V_exact' * Diagonal(wt) * V_exact))
            V_exact = V_exact * Diagonal(scale)
            @test V ≈ V_exact
        end
    end
end
