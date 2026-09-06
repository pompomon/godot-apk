extends Node
## Owns the future active Expedition and start/resolve/reveal orchestration.
## SaveManager serializes this state alongside GameState; never duplicate it there.
## Milestone 4 uses GameState, CombatSimulator, and SaveManager.


## party becomes PartyData in Milestone 3. No outcomes or rewards are generated.
func start_expedition(
		_region: RegionResource, _party: Variant, _duration_seconds: int) -> void:
	push_warning("ExpeditionManager.start_expedition is not implemented until Milestone 4.")


func reveal_progress() -> void:
	push_warning("ExpeditionManager.reveal_progress is not implemented until Milestone 4.")


func is_expedition_active() -> bool:
	return false


## Return type becomes ExpeditionData in Milestone 4.
func get_active_expedition() -> Variant:
	return null
