using Test
using NoLimitHoldem
const NLH = NoLimitHoldem

@testset "Suit" begin
  s = Club()
  s = Spade()
  s = Heart()
  s = Diamond()
end

@testset "Ranks" begin
  r = Two();   Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 2
  r = Three(); Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 3
  r = Four();  Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 4
  r = Five();  Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 5
  r = Six();   Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 6
  r = Seven(); Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 7
  r = Eight(); Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 8
  r = Nine();  Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 9
  r = Ten();   Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 10
  r = Jack();  Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 11
  r = Queen(); Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 12
  r = King();  Tr = typeof(r); @test NLH.value(Tr) == NLH.low_value(Tr) == 13

  r = Ace()
  Tr = typeof(r)
  @test NLH.value(Tr) == 14
  @test NLH.low_value(Tr) == 1
end

@testset "Card" begin
  two_clubs = Card(Two(), Club())
  ace_clubs = Card(Ace(), Club())
  jack_clubs = Card(Jack(), Club())
  jack_hearts = Card(Jack(), Heart())

  @test same_suit(ace_clubs  , jack_clubs) == true
  @test same_suit(jack_hearts, jack_clubs) == false

  @test same_rank(jack_hearts, jack_clubs) == true
  @test same_rank(ace_clubs  , jack_clubs) == false

  @test get_string(two_clubs) == "(2, Club)"
  @test get_string(jack_clubs) == "(Jack, Club)"
  @test get_string(ace_clubs) == "(Ace, Club)"

  @test NLH.rank_type(typeof(jack_clubs)) == Jack
  @test NLH.suit_type(typeof(jack_clubs)) == Club
  @test NLH.rank(jack_clubs) == Jack()
  @test NLH.suit(jack_clubs) == Club()
  @test sprint(show, two_clubs) == "(2, Club)"
  @test sprint(show, jack_clubs) == "(Jack, Club)"
end

