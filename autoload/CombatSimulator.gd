extends Node
## Stateless simulation interface; autoload registration is only a runtime facade.
## Resolution must not access the scene tree, GameState, clocks, or global RNG:
## it simply forwards to the pure CombatResolver so callers outside the scene
## tree (e.g. ExpeditionGenerator) can resolve combat without this singleton.


## JSON-safe result: outcome (VICTORY/DEFEAT/RETREAT), round-by-round log, and
## final_hero_states keyed by stable Hero ID. {} signals malformed input/config.
func resolve_combat(
		party: ExpeditionPartySnapshot, current_hero_states: Dictionary,
		enemy_group: EnemyGroupResource, seed: int, balancing: BalancingConfig) -> Dictionary:
	return CombatResolver.resolve(party, current_hero_states, enemy_group, seed, balancing)
