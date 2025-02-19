#=
This file implements functions shared by all discrete spaces.
Discrete spaces are by definition spaces with a finite amount of possible positions.

All these functions are granted "for free" to discrete spaces by simply extending:
- positions(space)
- ids_in_position(position, model)

Notice that the default version of the remaining functions assumes that
agents are stored in a field `stored_ids` of the space.
=#

export positions, npositions, ids_in_position, agents_in_position,
       empty_positions, random_empty, has_empty_positions, empty_nearby_positions,
       random_id_in_position, random_agent_in_position


positions(model::ABM) = positions(abmspace(model))
"""
    positions(model::ABM{<:DiscreteSpace}) → ns
Return an iterator over all positions of a model with a discrete space.

    positions(model::ABM{<:DiscreteSpace}, by::Symbol) → ns
Return all positions of a model with a discrete space, sorting them
using the argument `by` which can be:
* `:random` - randomly sorted
* `:population` - positions are sorted depending on how many agents they accommodate.
  The more populated positions are first.
"""
function positions(model::ABM{<:DiscreteSpace}, by::Symbol)
    n = collect(positions(model))
    itr = vec(n)
    if by == :random
        shuffle!(abmrng(model), itr)
    elseif by == :population
        sort!(itr, by = i -> length(ids_in_position(i, model)), rev = true)
    else
        error("unknown `by`")
    end
    return itr
end

"""
    npositions(model::ABM{<:DiscreteSpace})

Return the number of positions of a model with a discrete space.
"""
npositions(model::ABM) = npositions(abmspace(model))

"""
    ids_in_position(position, model::ABM{<:DiscreteSpace})
    ids_in_position(agent, model::ABM{<:DiscreteSpace})

Return the ids of agents in the position corresponding to `position` or position
of `agent`.
"""
ids_in_position(agent::AbstractAgent, model) = ids_in_position(agent.pos, model)

"""
    agents_in_position(position, model::ABM{<:DiscreteSpace})
    agents_in_position(agent, model::ABM{<:DiscreteSpace})

Return an iterable of the agents in `position``, or in the position of `agent`.
"""
agents_in_position(agent::AbstractAgent, model) = agents_in_position(agent.pos, model)
agents_in_position(pos, model) = (model[id] for id in ids_in_position(pos, model))

"""
    empty_positions(model)

Return a list of positions that currently have no agents on them.
"""
function empty_positions(model::ABM{<:DiscreteSpace})
    Iterators.filter(i -> length(ids_in_position(i, model)) == 0, positions(model))
end

"""
    isempty(pos, model::ABM{<:DiscreteSpace})
Return `true` if there are no agents in `position`.
"""
Base.isempty(pos::Int, model::ABM{<:DiscreteSpace}) = isempty(pos, abmspace(model))
Base.isempty(pos::Int, space::DiscreteSpace) = isempty(ids_in_position(pos, space))

"""
    has_empty_positions(model::ABM{<:DiscreteSpace})
Return `true` if there are any positions in the model without agents.
"""
function has_empty_positions(model::ABM{<:DiscreteSpace})
    return any(pos -> isempty(pos, model), positions(model))
end

"""
    random_empty(model::ABM{<:DiscreteSpace})
Return a random position without any agents, or `nothing` if no such positions exist.
"""
function random_empty(model::ABM{<:DiscreteSpace}, cutoff = 0.998)
    # This switch assumes the worst case (for this algorithm) of one
    # agent per position, which is not true in general but is appropriate
    # here.
    if clamp(nagents(model) / npositions(model), 0.0, 1.0) < cutoff
        # 0.998 has been benchmarked as a performant branching point
        # It sits close to where the maximum return time is better
        # than the code in the else loop runs. So we guarantee
        # an increase in performance overall, not just when we
        # get lucky with the random rolls.
        while true
            pos = random_position(model)
            isempty(pos, model) && return pos
        end
    else
        empty = empty_positions(model)
        return itsample(abmrng(model), empty, StreamSampling.AlgRSWRSKIP())
    end
end

"""
    empty_nearby_positions(pos, model::ABM{<:DiscreteSpace}, r = 1; kwargs...)
    empty_nearby_positions(agent, model::ABM{<:DiscreteSpace}, r = 1; kwargs...)

Return an iterable of all empty positions within radius `r` from the given position or the given agent.

The value of `r` and possible keywords operate identically to [`nearby_positions`](@ref).
"""
function empty_nearby_positions(agent::AbstractAgent, model, r = 1; kwargs...)
    return empty_nearby_positions(agent.pos, model, r; kwargs...)
end
function empty_nearby_positions(pos, model, r = 1; kwargs...)
    return Iterators.filter(pos -> isempty(pos, model), nearby_positions(pos, model, r; kwargs...))
end

"""
    random_id_in_position(pos, model::ABM, [f, alloc = false]) → id
Return a random id in the position specified in `pos`.

A filter function `f(id)` can be passed so that to restrict the sampling on only those agents
for which the function returns `true`. The argument `alloc` can be used if the filtering condition
is expensive since in this case the allocating version can be more performant.
`nothing` is returned if no nearby position satisfies `f`.

Use [`random_nearby_id`](@ref) instead to return the `id` of a random agent near the position of a
given `agent`.
"""
function random_id_in_position(pos, model)
    ids = ids_in_position(pos, model)
    isempty(ids) && return nothing
    return rand(abmrng(model), ids)
end
function random_id_in_position(pos, model, f, alloc = false, transform = identity)
    iter_ids = ids_in_position(pos, model)
    if alloc
        return sampling_with_condition_single(iter_ids, f, model, transform)
    else
        iter_filtered = Iterators.filter(id -> f(transform(id)), iter_ids)
        id = itsample(abmrng(model), iter_filtered, StreamSampling.AlgRSWRSKIP())
        isnothing(id) && return nothing
        return id
    end
end

"""
    random_agent_in_position(pos, model::ABM, [f, alloc = false]) → agent
Return a random agent in the position specified in `pos`.

A filter function `f(agent)` can be passed so that to restrict the sampling on only those agents
for which the function returns `true`. The argument `alloc` can be used if the filtering condition
is expensive since in this case the allocating version can be more performant.
`nothing` is returned if no nearby position satisfies `f`.

Use [`random_nearby_agent`](@ref) instead to return a random agent near the position of a given `agent`.
"""
function random_agent_in_position(pos, model)
    id = random_id_in_position(pos, model)
    isnothing(id) && return nothing
    return model[id]
end
function random_agent_in_position(pos, model, f, alloc = false)
    id = random_id_in_position(pos, model, f, alloc, id -> model[id])
    isnothing(id) && return nothing
    return model[id]
end

#######################################################################################
# Discrete space extra agent adding stuff
#######################################################################################
export add_agent_single!, fill_space!, move_agent_single!, swap_agents!

"""
    add_agent_single!(agent, model::ABM{<:DiscreteSpace}) → agent

Add the `agent` to a random position in the space while respecting a maximum of one agent
per position, updating the agent's position to the new one.

This function does nothing if there aren't any empty positions.
"""
function add_agent_single!(agent::AbstractAgent, model::ABM{<:DiscreteSpace})
    position = random_empty(model)
    isnothing(position) && return nothing
    agent.pos = position
    add_agent_own_pos!(agent, model)
    return agent
end

"""
    add_agent_single!(model::ABM{<:DiscreteSpace}, properties...; kwargs...)
Same as `add_agent!(model, properties...; kwargs...)` but ensures that it adds an agent
into a position with no other agents (does nothing if no such position exists).
"""
function add_agent_single!(model::ABM{<:DiscreteSpace}, properties::Vararg{Any, N}; kwargs...) where {N}
    position = random_empty(model)
    isnothing(position) && return nothing
    agent = add_agent!(position, model, properties...; kwargs...)
    return agent
end

"""
    add_agent_single!(A, model::ABM{<:DiscreteSpace}, properties...; kwargs...)
Same as `add_agent!(A, model, properties...; kwargs...)` but ensures that it adds an agent
into a position with no other agents (does nothing if no such position exists).
"""
function add_agent_single!(A::Union{Function, Type}, model::ABM, properties::Vararg{Any, N}; kwargs...) where {N}
    position = random_empty(model)
    isnothing(position) && return nothing
    agent = add_agent!(position, A, model, properties...; kwargs...)
    return agent
end

"""
    fill_space!([A ,] model::ABM{<:DiscreteSpace,A}, args...)
    fill_space!([A ,] model::ABM{<:DiscreteSpace,A}; kwargs...)
    fill_space!([A ,] model::ABM{<:DiscreteSpace,A}, f::Function)

Add one agent to each position in the model's space. Similarly with [`add_agent!`](@ref),
`fill_space` creates the necessary agents and adds them to the model.
Like in [`add_agent!`](@ref) you may use either `args...` or `kwargs...` to set
the remaining properties of the agent.

Alternatively, you may use the third version.
If instead of `args...` a function `f` is provided, then `args = f(pos)` is the result of
applying `f` where `pos` is each position (tuple for grid, integer index for graph).
Hence, in this case `f` must create all other agent properties besides mandatory `id, pos`.

An optional first argument is an agent **type** to be created, and targets mixed agent
models where the agent constructor cannot be deduced (since it is a union).
"""
function fill_space!(model::ABM, args::Vararg{Any, N}; kwargs...) where {N}
    A = agenttype(model)
    fill_space!(A, model, args...; kwargs...)
end

function fill_space!(
    A::Union{Function, Type}, 
    model::ABM{<:DiscreteSpace},
    args::Vararg{Any, N};
    kwargs...,
) where {N}
    for p in positions(model)
        add_agent!(p, A, model, args...; kwargs...)
    end
    return model
end

function fill_space!(A::Type, model::ABM{<:DiscreteSpace}, f::Function)
    for p in positions(model)
        args = f(p)
        add_agent!(p, A, model, args...)
    end
    return model
end

"""
    move_agent_single!(agent, model::ABM{<:DiscreteSpace}; cutoff) → agent

Move agent to a random position while respecting a maximum of one agent
per position. If there are no empty positions, the agent won't move.

The keyword `cutoff = 0.998` is sent to [`random_empty`](@ref).
"""
function move_agent_single!(
    agent::AbstractAgent,
    model::ABM{<:DiscreteSpace};
    cutoff = 0.998,
)
    position = random_empty(model, cutoff)
    isnothing(position) && return nothing
    move_agent!(agent, position, model)
    return agent
end

"""
    swap_agents!(agent1, agent2, model::ABM{<:DiscreteSpace})

Swap the given agent's positions, moving each of them to the position
of the other agent.
"""
function swap_agents!(agent1, agent2, model::ABM{<:DiscreteSpace})
    remove_agent_from_space!(agent1, model)
    remove_agent_from_space!(agent2, model)
    agent1.pos, agent2.pos = agent2.pos, agent1.pos
    add_agent_to_space!(agent1, model)
    add_agent_to_space!(agent2, model)
    return nothing
end

function remove_all_from_space!(model::ABM{<:DiscreteSpace})
    for p in positions(model)
        empty!(ids_in_position(p, model))
    end
end
