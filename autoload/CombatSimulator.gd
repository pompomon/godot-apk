extends Node
## Stateless simulation interface; autoload registration is only a runtime facade.
## Resolution must not access the scene tree, GameState, clocks, or global RNG.


## Milestone 5 types party as PartyData and enemy_group as EnemyGroupResource.
## Inputs must remain unchanged. The future JSON-safe result contains outcome,
## rounds, and final_hero_states keyed by stable Hero ID; {} is NOT an outcome.
func resolve_combat(
		_party: Variant, _current_hero_states: Dictionary, _enemy_group: Variant,
		_seed: int, _balancing: BalancingConfig) -> Dictionary:
	push_warning("CombatSimulator.resolve_combat is not implemented until Milestone 5.")
	return {}
