class_name RecruitmentService
extends RefCounted
## Three persistent offers. Only a purchased slot is replaced.

const OFFER_COUNT := 3
const SEED_MODULUS := 2147483647
static var last_error: String = ""


## Bounded integer arithmetic, not a truncated native RNG state.
static func seed_at(seed: int, sequence: int) -> int:
	if seed < 0 or seed > HeroCatalog.MAX_SAFE_INT:
		return -1
	if sequence < 0 or sequence > HeroCatalog.MAX_SAFE_INT:
		return -1
	return (seed % SEED_MODULUS + (sequence % SEED_MODULUS) * 48271) % SEED_MODULUS


static func generate_offers(
		seed: int, hero_ids: Array[String], class_pool: Array[HeroClassResource],
		trait_pool: Array[HeroTraitResource]) -> Array[HeroData]:
	var result: Array[HeroData] = []
	if seed_at(seed, 0) < 0 or not HeroCatalog.validate_catalog(class_pool, trait_pool):
		return result
	var seen := {}
	for index in hero_ids.size():
		var id := hero_ids[index]
		if id.is_empty() or seen.has(id):
			return []
		seen[id] = true
		var hero := HeroGenerator.generate_hero(
			id, seed_at(seed, index), class_pool, trait_pool)
		if hero == null:
			return []
		result.append(hero)
	return result


static func initialize_new_game(seed: int) -> bool:
	if seed_at(seed, 0) < 0 or not HeroCatalog.validate_catalog(
			HeroCatalog.classes(), HeroCatalog.traits()):
		return false
	var old_state := GameState.checkpoint()
	GameState.reset()
	GameState.recruitment_seed = seed
	GameState.gold = 100
	for hero_class in HeroCatalog.classes():
		var single_class: Array[HeroClassResource] = [hero_class]
		var hero := _reserve_hero(single_class)
		if hero == null:
			GameState.restore_checkpoint(old_state)
			return false
		GameState.roster.append(hero)
	for index in OFFER_COUNT:
		var offer_seed := seed_at(seed, GameState.recruitment_sequence)
		var hero := _reserve_hero(HeroCatalog.classes())
		if hero == null:
			GameState.restore_checkpoint(old_state)
			return false
		GameState.recruitment_offers.append(hero)
		GameState.offer_seeds.append(offer_seed)
	GameState.initialized = true
	return true


static func _reserve_hero(class_pool: Array[HeroClassResource]) -> HeroData:
	if GameState.recruitment_sequence >= HeroCatalog.MAX_SAFE_INT:
		return null
	var id := GameState.reserve_hero_id()
	if id.is_empty():
		return null
	var hero := HeroGenerator.generate_hero(id,
		seed_at(GameState.recruitment_seed, GameState.recruitment_sequence),
		class_pool, HeroCatalog.traits())
	GameState.recruitment_sequence += 1
	return hero


static func availability_error(hero_id: String, balancing: BalancingConfig) -> String:
	if not GameState.initialized:
		return "Company is not initialized. Return Home and retry."
	if GameState.find_hero(hero_id) != null:
		return "This hero has already joined your company."
	var found := false
	for offer in GameState.recruitment_offers:
		if offer != null and offer.hero_id == hero_id:
			found = true
			break
	if not found:
		return "This offer is no longer available. Choose a current offer."
	if balancing == null or balancing.recruitment_cost < 0:
		return "Recruitment price is invalid. Check the balancing configuration."
	if GameState.roster.size() >= GameState.roster_capacity:
		return "Roster full (%d / %d)." % [GameState.roster.size(), GameState.roster_capacity]
	if GameState.gold < balancing.recruitment_cost:
		return "Not enough gold: need %d, have %d." % [balancing.recruitment_cost, GameState.gold]
	if (GameState.next_hero_id >= HeroCatalog.MAX_SAFE_INT
			or GameState.recruitment_sequence >= HeroCatalog.MAX_SAFE_INT):
		return "Recruitment ID or seed sequence is exhausted; no gold was spent."
	return ""


static func recruit(hero: HeroData, balancing: BalancingConfig) -> bool:
	last_error = "Choose a current recruitment offer." if hero == null else availability_error(
		hero.hero_id, balancing)
	if not last_error.is_empty():
		return false
	var index := -1
	for slot in GameState.recruitment_offers.size():
		if GameState.recruitment_offers[slot].hero_id == hero.hero_id:
			index = slot
			break
	var checkpoint := GameState.checkpoint()
	var replacement_seed := seed_at(GameState.recruitment_seed, GameState.recruitment_sequence)
	var replacement := _reserve_hero(HeroCatalog.classes())
	if replacement == null:
		GameState.restore_checkpoint(checkpoint)
		last_error = "Could not generate the replacement offer; no gold was spent."
		return false
	var actual_offer := GameState.recruitment_offers[index]
	GameState.gold -= balancing.recruitment_cost
	GameState.roster.append(actual_offer)
	GameState.recruitment_offers[index] = replacement
	GameState.offer_seeds[index] = replacement_seed
	SaveManager.save()
	if not SaveManager.last_committed:
		GameState.restore_checkpoint(checkpoint)
		last_error = "Purchase was not saved; no gold was spent. %s" % SaveManager.last_error
		return false
	return true
