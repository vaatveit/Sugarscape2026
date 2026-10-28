# xxl geometry: torus distances, disc offsets, ring draws and the season weight (spec, "The rules").
using Sugarscape, Test
using Random: Xoshiro

# Kolmogorov-Smirnov distance of the samples from the CDF `F`.
function ks_distance(samples, F)
    xs = sort(samples)
    n = length(xs)
    return maximum(max(F(x) - (i - 1) / n, i / n - F(x)) for (i, x) in enumerate(xs))
end

@testset "xxl geometry" begin
    @testset "disc_offsets" begin
        @test disc_offsets(1.0) == [(-1, 0), (0, -1), (0, 1), (1, 0)]
        @test length(disc_offsets(1.5)) == 8
        @test length(disc_offsets(3.0)) == 28
        offs = disc_offsets(3.0)
        @test (0, 0) ∉ offs
        key(o) = (hypot(o...), o[1], o[2])
        @test issorted(offs; by=key)
    end

    @testset "torus" begin
        @test torus_delta(500, 498, 2) == 4
        @test torus_delta(500, 2, 498) == -4
        @test torus_delta(500, 0, 250) == 250     # the half-width goes positive
        @test torus_delta(500, 250, 0) == 250
        @test torus_delta(500, 7, 7) == 0
        @test torus_dist(500, 500, 0, 0, 499, 499) ≈ √2
        @test torus_dist(500, 400, 10, 10, 13, 14) ≈ 5
    end

    @testset "ring_point" begin
        n, N = 6.0, 20_000
        rng = Xoshiro(1)
        pts = [ring_point(rng, n, 60.0) for _ in 1:N]
        ρ = [hypot(p...) for p in pts]
        θ = [mod(atan(p[2], p[1]), 2π) for p in pts]
        @test all(r -> n < r <= 60.0 + 1e-9, ρ)
        crit = 1.63 / √N
        @test ks_distance(ρ, r -> (r^2 - 36) / (3600 - 36)) < crit
        @test ks_distance(θ, t -> t / 2π) < crit
        # exactly two draws, u1 then u2
        a, b = Xoshiro(5), Xoshiro(5)
        x, y = ring_point(a, 6.0, 60.0)
        u1, u2 = rand(b), rand(b)
        r = √(36.0 + u1 * (3600.0 - 36.0))
        @test (x, y) == (r * cos(2π * u2), r * sin(2π * u2))
        @test rand(a) == rand(b)
    end

    @testset "ring_draws" begin
        @test ring_draws(60) == 24
        @test ring_draws(10) == 4
    end

    @testset "winter_weight" begin
        @test winter_weight(0, 500) == 0
        @test winter_weight(250, 500) ≈ 0 atol = 1e-12
        @test winter_weight(125, 500) ≈ 1
        @test winter_weight(375, 500) ≈ 1
    end
end
