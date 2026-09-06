class_name SkillResource
extends Resource
## One authored active skill per class. Multipliers resolve through BalancingConfig.

## Combatant action categories. Physical scales Attack, Magic scales MagicPower,
## Heal restores MagicPower-scaled HP, Guard reduces incoming damage to the caster.
const KINDS := ["Physical", "Magic", "Heal", "Guard"]
## Self buffs the caster; LowestHpAlly heals an injured living ally (including the
## caster); FrontRowFirst/AnySlot mirror the basic-attack opponent rules.
const TARGET_RULES := ["FrontRowFirst", "AnySlot", "Self", "LowestHpAlly"]

@export var skill_id: StringName
@export var display_name: String
@export var class_id: StringName
@export_enum("Physical", "Magic", "Heal", "Guard") var kind: String = "Physical"
@export_enum("FrontRowFirst", "AnySlot", "Self", "LowestHpAlly") var target_rule: String = "AnySlot"
## Resolved through BalancingConfig.skill_damage_multipliers; damage/heal scale or,
## for Guard, the fraction of incoming damage removed (0.0-1.0).
@export var multiplier_id: StringName
## Personal turns to wait before reuse; 0 means usable every own turn.
@export var cooldown: int = 0
