extends Node
## Company state only; party and expedition ownership belong to later milestones.

var roster: Array[HeroData] = []
var recruitment_offers: Array[HeroData] = []
var gold: int = 0
var inventory: Array = []
var unlocked_regions: Array[StringName] = []
var roster_capacity: int = 12
var next_hero_id: int = 1
var recruitment_seed: int = 0
var recruitment_sequence: int = 0
var offer_seeds: Array[int] = []
var initialized: bool = false


func find_hero(hero_id: String) -> HeroData:
	for hero in roster:
		if hero.hero_id == hero_id:
			return hero
	return null


func reserve_hero_id() -> String:
	if next_hero_id < 1 or next_hero_id >= HeroCatalog.MAX_SAFE_INT:
		return ""
	var result := "hero-%d" % next_hero_id
	next_hero_id += 1
	return result


## Runtime checkpoint retains hero identity when a purchase has to roll back.
func checkpoint() -> Dictionary:
	return {
		"roster": roster.duplicate(), "recruitment_offers": recruitment_offers.duplicate(),
		"gold": gold, "inventory": inventory.duplicate(),
		"unlocked_regions": unlocked_regions.duplicate(), "roster_capacity": roster_capacity,
		"next_hero_id": next_hero_id, "recruitment_seed": recruitment_seed,
		"recruitment_sequence": recruitment_sequence, "offer_seeds": offer_seeds.duplicate(),
		"initialized": initialized,
	}


func restore_checkpoint(state: Dictionary) -> void:
	roster.assign(state.roster)
	recruitment_offers.assign(state.recruitment_offers)
	gold = state.gold
	inventory = state.inventory.duplicate()
	unlocked_regions.assign(state.unlocked_regions)
	roster_capacity = state.roster_capacity
	next_hero_id = state.next_hero_id
	recruitment_seed = state.recruitment_seed
	recruitment_sequence = state.recruitment_sequence
	offer_seeds.assign(state.offer_seeds)
	initialized = state.initialized


func reset() -> void:
	roster.clear()
	recruitment_offers.clear()
	gold = 0
	inventory.clear()
	unlocked_regions.clear()
	roster_capacity = 12
	next_hero_id = 1
	recruitment_seed = 0
	recruitment_sequence = 0
	offer_seeds.clear()
	initialized = false
