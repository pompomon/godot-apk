extends Node
## Stateless simulation interface; autoload registration is only a runtime facade.
## Resolution must not access the scene tree, GameState, clocks, or global RNG.


func resolve_combat(
		party: ExpeditionPartySnapshot, current_hero_states: Dictionary,
		enemy_group: EnemyGroupResource, seed: int, balancing: BalancingConfig) -> Dictionary:
	return CombatEngine.resolve_combat(party, current_hero_states, enemy_group, seed, balancing)
