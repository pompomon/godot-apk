class_name HeroGenerator
extends RefCounted
## Local RNG only. Catalog, name, and attribute order are part of seeded generation.

const NAMES = [
	"Alden", "Bryn", "Cora", "Dain", "Elara", "Finn", "Galen", "Hana",
	"Ivo", "Jora", "Kael", "Lina", "Marek", "Nessa", "Orin", "Petra",
]


static func generate_hero(
		hero_id: String, seed: int, class_pool: Array[HeroClassResource],
		trait_pool: Array[HeroTraitResource], level: int = 1) -> HeroData:
	if hero_id.is_empty() or seed < 0 or seed > HeroCatalog.MAX_SAFE_INT:
		return null
	if level < 1 or level > HeroCatalog.MAX_LEVEL:
		return null
	if not HeroCatalog.validate_catalog(class_pool, trait_pool):
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hero := HeroData.new(hero_id)
	hero.hero_class = class_pool[rng.randi_range(0, class_pool.size() - 1)]
	hero.hero_name = NAMES[rng.randi_range(0, NAMES.size() - 1)]
	hero.level = level
	for attribute in HeroCatalog.ATTRIBUTES:
		var bounds: Vector2i = hero.hero_class.base_attribute_ranges[attribute]
		hero.attributes[attribute] = rng.randi_range(bounds.x, bounds.y)
	if not trait_pool.is_empty() and rng.randi_range(0, 1) == 1:
		hero.traits.append(trait_pool[rng.randi_range(0, trait_pool.size() - 1)])
	return hero
