#####
##### Table
#####

export Button, SmallBlind, BigBlind, FirstToAct
export Table
export move_button!

Base.@kwdef mutable struct Winners
    declared::Bool = false
    players::Union{Nothing,Tuple,Player} = nothing
end

function Base.show(io::IO, winners::Winners, include_type = true)
    include_type && println(io, typeof(winners))
    println(io, "Winners declared = $(winners.declared)")
    println(io, "Winners          = $(winners.players)")
end

struct Blinds{S,B}
    small::S
    big::B
end

Blinds() = Blinds(1,2) # default
default_button_id() = 1 # default

function Base.show(io::IO, blinds::Blinds, include_type = true)
    include_type && println(io, typeof(blinds))
    println(io, "Blinds           = (small=$(blinds.small),big=$(blinds.big))")
end

mutable struct Table
    deck::PlayingCards.Deck
    players::Tuple
    cards::Union{Nothing,Tuple{<:Card,<:Card,<:Card,<:Card,<:Card}}
    blinds::Blinds
    pot::Float64
    state::AbstractGameState
    button_id::Int
    current_raise_amt::Float64
    transactions::TransactionManager
    winners::Winners
end

function Table(;
    players::Tuple,
    deck = ordered_deck(),
    cards = nothing,
    blinds = Blinds(),
    pot = Float64(0),
    state = PreFlop(),
    button_id = default_button_id(),
    current_raise_amt = Float64(0),
    transactions = nothing,
    winners = Winners(),
)
    if transactions == nothing
        transactions = TransactionManager(players)
    end
    return Table(deck,
        players,
        cards,
        blinds,
        pot,
        state,
        button_id,
        current_raise_amt,
        transactions,
        winners)
end

function Base.show(io::IO, table::Table, include_type = true)
    include_type && println(io, typeof(table))
    show(io, blinds(table), false)
    show(io, table.winners, false)
    println(io, "Button           = $(button_id(table))")
    println(io, "Pot              = $(table.transactions)")
    println(io, "All cards        = $(table.cards)")
    println(io, "Observed cards   = $(observed_cards(table))")
end

get_table_cards!(deck::PlayingCards.Deck) =
    Iterators.flatten(ntuple(i->pop!(deck, 1), 5)) |> collect |> Tuple
cards(table::Table) = table.cards

observed_cards(table::Table) = observed_cards(table, table.state)
observed_cards(table::Table, ::PreFlop) = ()
observed_cards(table::Table, ::Flop) = table.cards[1:3]
observed_cards(table::Table, ::Turn) = table.cards[1:4]
observed_cards(table::Table, ::River) = table.cards
current_raise_amt(table::Table) = table.current_raise_amt

state(table::Table) = table.state
button_id(table::Table) = table.button_id
players_at_table(table::Table) = table.players
all_checked_or_folded(table::Table) = all(map(x -> folded(x) || checked(x), players_at_table(table)))
all_all_in_or_folded(table::Table) = all(map(x -> folded(x) || all_in(x), players_at_table(table)))
all_all_in_or_checked(table::Table) = all(map(x -> checked(x) || all_in(x), players_at_table(table)))

"""
    bank_roll_leader(table::Table)

Return the player who
 - Is still playing and
 - Has the highest bank roll
and a `Bool` indicating if there
are multiple players with the largest
bank roll.
"""
function bank_roll_leader(table::Table)
    max_rbr = 0
    players = players_at_table(table)
    br_leader = first(players)
    for player in players
        still_playing(player) || continue # only consider players still playing
        pbr = round_bank_roll(player)
        if pbr > max_rbr
            br_leader = player
            max_rbr = pbr
        end
    end
    multiple_leaders = count(map(players) do player
        round_bank_roll(player) ≈ max_rbr && !folded(player)
    end) > 1
    return br_leader, multiple_leaders
end

# Can be true in exactly 2 cases:
#  1) Everyone (still playing) is all-in.
#  2) Everyone (still playing), except `player`, is all-in.
function all_oppononents_all_in(table::Table, player::Player)
    all_opp_all_in = true
    for opponent in players_at_table(table)
        seat_number(opponent) == seat_number(player) && continue
        not_playing(opponent) && continue
        if action_required(opponent)
            all_opp_all_in = false
        else
            all_opp_all_in = all_opp_all_in && all_in(opponent)
        end
    end
    return all_opp_all_in
end

# One case that we need to catch is when everyone, except
# the bank roll leader, has folded or gone all-in. In this
# case, while the bank roll leader may have required actions
# everyone else does not, so nobody can respond to their raise
# (if they chose to do so). Therefore, we must "play out" the
# entire game with no further actions.
function all_all_in_except_bank_roll_leader(table::Table)
    br_leader, multiple_leaders = bank_roll_leader(table)
    players = players_at_table(table)
    multiple_leaders && return false # the bank roll leader can go all-in

    @assert !multiple_leaders # We have a single bank roll leader

    return all(map(players) do player
        not_playing(player) || all_in(player) || seat_number(player) == seat_number(br_leader)
    end)
end

blinds(table::Table) = table.blinds

function is_blind_call(table::Table, player::Player, amt = call_amount(table, player))
    pot_inv = pot_investment(player)
    @debug "amt = $amt, pot_investment(player) = $pot_inv"
    bb = blinds(table).big
    sb = blinds(table).small
    if is_small_blind(table, player)
        return amt ≈ sb && pot_inv ≈ sb
    elseif is_big_blind(table, player)
        return amt ≈ 0 && pot_inv ≈ bb
    else
        return amt ≈ bb && pot_inv ≈ 0
    end
end

function reset_round_bank_rolls!(table::Table)
    players = players_at_table(table)
    for player in players
        player.round_bank_roll = bank_roll(player)
    end
end

function reset_round!(table::Table)
    players = players_at_table(table)
    for player in players
        folded(player) && continue
        all_in(player) && continue
        player.checked = false
        player.action_required = true
        player.last_to_raise = false
        player.round_contribution = 0
    end
    table.current_raise_amt = 0
end

function set_state!(table::Table, state::AbstractGameState)
    table.state = state
end

function check_for_winner!(table::Table)
    players = players_at_table(table)
    n_players = length(players)
    table.winners.declared = count(folded.(players)) == n_players-1
    if table.winners.declared
        for player in players
            folded(player) && continue
            table.winners.players = player
        end
    end
end


#####
##### Circling the table
#####

"""
    move_button!(table::Table)

Move the button to the next player on
the table.
"""
function move_button!(table::Table)
    table.button_id = mod(button_id(table), length(table.players))+1
    players = players_at_table(table)
    player_not_playing = not_playing(players[button_id(table)])
    counter = 0
    if player_not_playing
        while !player_not_playing
            table.button_id = mod(button_id(table), length(table.players))+1
            counter+=1
            if counter > length(players)
                error("Button has nowhere to move!")
            end
        end
    end
end

"""
    position(table, player::Player, relative)

Player position, given
 - `table` the table
 - `player` the player
 - `relative::Int = 0` the relative location to the player
"""
position(table, player::Player, relative=0) =
    mod(relative + seat_number(player) - 1, length(table.players))+1

"""
    circle_table(n_players, button_id, state)

Circle the table, starting from the `button_id`
which corresponds to `state = 1`.
 - `state` the global iteration state (starting from 1)
 - `n_players` the total number of players
 - `button_id` the dealer ID (from `1:n_players`)
"""
circle_table(n_players, button_id, state) =
    mod(state + button_id-2, n_players)+1

circle_table(table::Table, state) =
    circle_table(length(table.players), button_id(table), state)

small_blind(table::Table) = players_at_table(table)[circle_table(table, 2)]
big_blind(table::Table) = players_at_table(table)[circle_table(table, 3)]
first_to_act(table::Table) = players_at_table(table)[circle_table(table, 4)]

is_small_blind(table::Table, player::Player) = seat_number(player) == seat_number(small_blind(table))
is_big_blind(table::Table, player::Player) = seat_number(player) == seat_number(big_blind(table))
is_first_to_act(table::Table, player::Player) = seat_number(player) == seat_number(first_to_act(table))

any_actions_required(table::Table) = any(action_required.(players_at_table(table)))

abstract type TablePosition end
struct Button <: TablePosition end
struct SmallBlind <: TablePosition end
struct BigBlind <: TablePosition end
struct FirstToAct <: TablePosition end # (after BigBlind)

struct CircleTable{CircType,P}
    players::Tuple
    button_id::Int
    n_players::Int
    player::P
end

circle(table::Table, tp::TablePosition) =
    CircleTable{typeof(tp),Nothing}(table.players, button_id(table), length(table.players), nothing)

circle(table::Table, player::Player) =
    CircleTable{typeof(player),typeof(player)}(table.players, button_id(table), length(table.players), player)

Base.iterate(ct::CircleTable{Button}, state = 1) =
    (ct.players[circle_table(ct.n_players, ct.button_id, state)], state+1)

Base.iterate(ct::CircleTable{SmallBlind}, state = 2) =
    (ct.players[circle_table(ct.n_players, ct.button_id, state)], state+1)

Base.iterate(ct::CircleTable{BigBlind}, state = 3) =
    (ct.players[circle_table(ct.n_players, ct.button_id, state)], state+1)

Base.iterate(ct::CircleTable{FirstToAct}, state = 4) =
    (ct.players[circle_table(ct.n_players, ct.button_id, state)], state+1)

Base.iterate(ct::CircleTable{P}, state = 1) where {P <: Player} =
    (ct.players[circle_table(ct.n_players, seat_number(ct.player), state)], state+1)

#####
##### Deal
#####

function deal!(table::Table, blinds::Blinds)
    players = players_at_table(table)
    shuffle!(table.deck)
    call_blinds = true
    for (i, player) in enumerate(circle(table, SmallBlind()))

        i>length(players) && break # deal cards to each player once

        player.cards = pop!(table.deck, 2)

        folded(player) && continue # TODO: folded players should not get cards.
        # Right now they do to allow calling FullHandEval on their hand, but we should remove
        # this, or remove the players entirely.

        if is_small_blind(table, player) && bank_roll(player) ≤ blinds.small
            contribute!(table, player, bank_roll(player), call_blinds)
            @info "$(name(player)) paid the small blind (all-in) and dealt cards: $(player.cards)"
        elseif is_big_blind(table, player) && bank_roll(player) ≤ blinds.big
            contribute!(table, player, bank_roll(player), call_blinds)
            @info "$(name(player)) paid the  big  blind (all-in) and dealt cards: $(player.cards)"
        else
            if is_small_blind(table, player)
                contribute!(table, player, blinds.small, call_blinds)
                @info "$(name(player)) paid the small blind and dealt cards: $(player.cards)"
            elseif is_big_blind(table, player)
                contribute!(table, player, blinds.big, call_blinds)
                @info "$(name(player)) paid the  big  blind and dealt cards: $(player.cards)"
            else
                @info "$(name(player)) dealt (free) cards:                   $(player.cards)"
            end
        end
    end

    table.cards = get_table_cards!(table.deck)
    @info "Table cards dealt (face-down)."
end

