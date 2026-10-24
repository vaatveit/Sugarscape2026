# Ports tests/test_disease.py. Bit strings are written as in the book, first character = position 1 = bit 0.
using Sugarscape, Test
isdefined(@__MODULE__, :tiny_model) || include("helpers.jl")

b(s) = bits([c == '1' ? 1 : 0 for c in s])
str(v::UInt64, n) = join((v >> (i - 1)) & 1 for i in 1:n)

function immune_agent(s)
    a = loose(0)
    a.immune, a.immune_genotype, a.nimmune = b(s), b(s), length(s)
    return a
end

host() = Model(Config(; initial_population=0))
disease!(m, s) = intern_disease!(m, b(s), length(s))

@testset "test_table_v1_example" begin  # pp.143-144
    @test nearest_substring(b("1011101001"), 10, b("10011"), 5) == (0, 1)
    a = immune_agent("1011101001")
    @test immune_step!(a, b("10011"), 5) === true  # one flip, at I's position 3
    @test str(a.immune, 10) == "1001101001"
end

@testset "test_leftmost_window_wins_ties" begin  # fn 11
    @test nearest_substring(b("0011"), 4, b("1"), 1) == (2, 0)
    @test nearest_substring(b("1010"), 4, b("01"), 2) == (1, 0)
    @test nearest_substring(b("0000"), 4, b("11"), 2) == (0, 2)
end

@testset "test_learning_takes_one_flip_per_period" begin
    a = immune_agent("0000000")
    @test [immune_step!(a, b("111"), 3) for _ in 1:3] == [false, false, true]
end

@testset "test_infect_skips_immune_and_duplicates" begin
    m = host()
    a = immune_agent("110010")
    a.disease_fee = 1.0
    @test infect!(m, a, disease!(m, "010")) === false && isempty(a.diseases)  # 010 is a substring
    d = disease!(m, "111")
    @test infect!(m, a, d) === true && infect!(m, a, d) === false
    @test a.diseases == [d] && sugar_burn(a) == a.metabolism + 1.0
end

@testset "test_immune_response_clears_matched_diseases" begin
    m = host()
    a = immune_agent("1011101001")
    near, far = disease!(m, "10011"), disease!(m, "000000")  # 000000 is 3 bits from its nearest window
    a.diseases = [near, far]
    immune_response!(m, a)
    @test a.diseases == [far]
end

@testset "test_memory_corruption_allows_reinfection" begin  # p.145
    m = host()
    a = immune_agent("110")
    @test infect!(m, a, disease!(m, "00")) === true
    immune_response!(m, a)
    immune_response!(m, a)
    @test isempty(a.diseases) && !is_immune(a.immune, 3, b("11"), 2)
    @test infect!(m, a, disease!(m, "11")) === true  # 11 was unlearned
end

@testset "test_equal_diseases_intern_once" begin
    m = host()
    @test disease!(m, "101") == disease!(m, "101")
    @test disease!(m, "101") != disease!(m, "1010")  # same bits, different length
    m2 = Model(Config(; initial_population=0))
    x, y = disease!(m2, "11"), disease!(m2, "11")
    new_agent!(m2, 0, 0, 1, 1, 10.0).diseases = [x]
    new_agent!(m2, 1, 0, 1, 1, 10.0).diseases = [y]
    @test collect_metrics(m2)[findfirst(==("diseases_circulating"), METRIC_COLUMNS)] == 1.0
end
