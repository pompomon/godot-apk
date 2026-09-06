class_name SkillResource
extends Resource
## One authored active action; snapshots retain plain values, not this Resource.

@export var skill_id: StringName
@export var display_name: String
@export_enum("Physical", "Magic", "Heal", "Guard") var effect: String = "Physical"
@export_enum("FrontRowFirst", "AnySlot", "LowestHPAlly", "Self") var target_rule: String = "AnySlot"
@export_range(0, 100) var cooldown_turns: int = 2


func snapshot() -> Dictionary:
	return {
		"skill_id": String(skill_id), "display_name": display_name,
		"effect": effect, "target_rule": target_rule, "cooldown_turns": cooldown_turns,
	}
