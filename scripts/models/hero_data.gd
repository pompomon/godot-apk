class_name HeroData
extends RefCounted
## Mutable roster state with a caller-allocated, lifetime-stable identity.

enum HeroStatus { IDLE, ASSIGNED, ON_EXPEDITION, RESTING, WOUNDED, DEAD }

var _hero_id: String
var hero_id: String:
	get:
		return _hero_id
	set(_value):
		pass

var hero_name: String = ""
var hero_class: HeroClassResource
var level: int = 1
var xp: int = 0
var attributes: Dictionary = {}
var traits: Array[HeroTraitResource] = []
var equipped_weapon: ItemResource = null
var equipped_armor: ItemResource = null
var status: HeroStatus = HeroStatus.IDLE
## Wall-clock second at which a WOUNDED Hero recovers to IDLE. 0 while not
## wounded; frozen from the Expedition at finalization so later balance tuning
## cannot extend or shorten an in-flight recovery.
var wounded_until: int = 0


func _init(id: String = "") -> void:
	_hero_id = id


func status_label() -> String:
	return String(HeroStatus.keys()[status]).capitalize()
