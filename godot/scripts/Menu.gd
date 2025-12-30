extends Control

@onready var start_btn: Button = get_node_or_null("Root/Right/StartRun") as Button
@onready var roster_box: VBoxContainer = get_node_or_null("Root/Right/RosterBox") as VBoxContainer
@onready var collection_box: VBoxContainer = get_node_or_null("Root/Left/CollectionBox") as VBoxContainer

var _selected_unlock: Dictionary = {}

func _ready() -> void:
	# Force load save
	var cm := get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm) and cm.has_method("load_save"):
		cm.load_save()
	_refresh()

	if start_btn:
		start_btn.pressed.connect(_on_start_run)

func _refresh() -> void:
	_refresh_collection()
	_refresh_roster()

func _refresh_collection() -> void:
	if collection_box == null:
		return
	for c in collection_box.get_children():
		c.queue_free()

	var cm := Engine.get_singleton("CollectionManager") if Engine.has_singleton("CollectionManager") else null
	if cm == null:
		cm = get_node_or_null("/root/CollectionManager")
	if cm == null:
		return
	var unlocked: Array = cm.unlocked
	if unlocked.is_empty():
		var l := Label.new()
		l.text = "No unlocked characters yet.\n(Play a run, unlock trophies in the draft.)"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		collection_box.add_child(l)
		return

	for e in unlocked:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var data: Dictionary = d.get("data", {}) as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		collection_box.add_child(row)

		var name := Label.new()
		var rarity := String(data.get("rarity_id", "common"))
		var arch := String(data.get("archetype_id", "bruiser"))
		name.text = "%s • %s" % [UnitFactory.rarity_name(rarity), arch]
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)

		var add := Button.new()
		add.text = "Add"
		row.add_child(add)
		add.pressed.connect(func():
			_add_unlock_to_roster(data)
		)

func _refresh_roster() -> void:
	if roster_box == null:
		return
	for c in roster_box.get_children():
		c.queue_free()

	var cm := Engine.get_singleton("CollectionManager") if Engine.has_singleton("CollectionManager") else null
	if cm == null:
		cm = get_node_or_null("/root/CollectionManager")
	if cm == null:
		return

	var roster: Array = cm.active_roster
	for i in range(6):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		roster_box.add_child(row)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < roster.size() and typeof(roster[i]) == TYPE_DICTIONARY:
			var d: Dictionary = roster[i]
			var rarity := String(d.get("rarity_id", "common"))
			var arch := String(d.get("archetype_id", "bruiser"))
			label.text = "%d) %s • %s" % [i + 1, UnitFactory.rarity_name(rarity), arch]
		else:
			label.text = "%d) (empty)" % [i + 1]
		row.add_child(label)

		if i < roster.size():
			var remove := Button.new()
			remove.text = "Remove"
			row.add_child(remove)
			remove.pressed.connect(func():
				cm.remove_from_roster(i)
				_refresh()
			)

func _add_unlock_to_roster(data: Dictionary) -> void:
	var cm := Engine.get_singleton("CollectionManager") if Engine.has_singleton("CollectionManager") else null
	if cm == null:
		cm = get_node_or_null("/root/CollectionManager")
	if cm == null:
		return
	if cm.active_roster.size() >= 6:
		return
	var cd := cm._dict_to_cd(data) if cm.has_method("_dict_to_cd") else null
	if cd == null:
		return
	cm.add_to_roster(cd)
	_refresh()

func _on_start_run() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


