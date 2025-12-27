class_name CharacterData
extends Resource

enum Origin {
	UNDEAD,
	MACHINE,
	BEAST,
	DEMON,
	ELEMENTAL,
	HUMAN
}

enum Class {
	WARRIOR,
	MAGE,
	ROGUE,
	GUARDIAN,
	HEALER,
	SUMMONER
}

enum AttackStyle { MELEE, RANGED }

@export var sprite_path: String = ""  # Usually PixelLab south rotation path
@export var pixellab_id: String = ""
@export var rarity_id: String = "common"
@export var archetype_id: String = "bruiser"
@export var origin: Origin = Origin.UNDEAD
@export var class_type: Class = Class.WARRIOR
@export var tier: int = 1  # Kept for UI; stats are data-driven now

@export var attack_style: AttackStyle = AttackStyle.RANGED
@export var passive_ids: PackedStringArray = PackedStringArray()
@export var crit_chance: float = 0.0
@export var crit_mult: float = 1.5

@export var max_hp: int = 100
@export var attack_damage: int = 10
@export var attack_range: float = 300.0
@export var attack_cooldown: float = 1.0
@export var move_speed: float = 120.0

func _init(
	p_sprite_path: String = "",
	p_origin: Origin = Origin.UNDEAD,
	p_class: Class = Class.WARRIOR,
	p_tier: int = 1
) -> void:
	sprite_path = p_sprite_path
	origin = p_origin
	class_type = p_class
	tier = p_tier
	# Stats are filled by UnitFactory (data-driven); keep safe defaults only.
	max_hp = 100
	attack_damage = 10
	attack_range = 300.0
	attack_cooldown = 1.0
	move_speed = 120.0

