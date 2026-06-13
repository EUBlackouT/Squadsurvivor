from pathlib import Path

main = Path(r"E:\SplitCode\godot\scripts\Main.gd").read_text(encoding="utf-8")
lines = main.splitlines()
chunk = lines[2864:3845]
header = '''extends CanvasLayer
class_name RecruitDraftUI

const _MenuMapPreview := preload("res://scripts/ui/MenuMapPreview.gd")
const _PixelUi := preload("res://scripts/ui/PixelUi.gd")

var _host: Node

static func present(host: Node) -> void:
\tif host.has_node("RecruitDraftUI"):
\t\treturn
\tvar ui := RecruitDraftUI.new()
\tui.name = "RecruitDraftUI"
\tui.layer = 100
\tui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
\tui._host = host
\thost.add_child(ui)
\tui._build()

func _build() -> void:
'''
out = []
skip = 0
for line in chunk:
    if line.startswith("func _show_recruit_draft"):
        skip = 1
        continue
    if skip == 1:
        if "var draft_ui := CanvasLayer.new()" in line:
            skip = 0
        continue
    if "draft_ui." in line:
        line = line.replace("draft_ui.", "")
    out.append(line)

text = header + "\n".join(out)
replacements = [
    ("_populate_recruit_cards(hbox, draft_ui,", "_populate_recruit_cards(hbox,"),
    ("_populate_recruit_cards(hbox, ui,", "_populate_recruit_cards(hbox,"),
    ("_create_character_card(c, ui)", "_create_character_card(c)"),
    ("_create_character_card(replacement, ui)", "_create_character_card(replacement)"),
    ("func _create_character_card(cd: CharacterData, ui: CanvasLayer)", "func _create_character_card(cd: CharacterData)"),
    ("func _banish_draft_card(card: Control, ui: CanvasLayer)", "func _banish_draft_card(card: Control)"),
    ("func _show_character_details(cd: CharacterData, ui: CanvasLayer)", "func _show_character_details(cd: CharacterData)"),
    ("func _select_character(cd: CharacterData, ui: CanvasLayer)", "func _select_character(cd: CharacterData)"),
    ("func _populate_recruit_cards(hbox: HBoxContainer, ui: CanvasLayer,", "func _populate_recruit_cards(hbox: HBoxContainer,"),
    ("func _show_swap_prompt(cd: CharacterData, ui: CanvasLayer)", "func show_swap_prompt(cd: CharacterData)"),
    ("_close_draft(ui)", "_close()"),
    ("_close_draft(draft_ui)", "_close()"),
    ("_show_swap_prompt(cd, ui)", "show_swap_prompt(cd)"),
    ("_select_character(cd, ui)", "_select_character(cd)"),
    ("_show_character_details(cd, ui)", "_show_character_details(cd)"),
    ("_banish_draft_card(card, ui)", "_banish_draft_card(card)"),
    ("get_tree()", "_host.get_tree()"),
    ("get_node_or_null", "_host.get_node_or_null"),
    ("toast_layer", "_host.toast_layer"),
    ("_recent_trophy_pool", "_host._recent_trophy_pool"),
    ("_force_rift_next_draft", "_host._force_rift_next_draft"),
    ("reroll_cost_essence", "_host.reroll_cost_essence"),
    ("banish_cost_essence", "_host.banish_cost_essence"),
    ("_map_mod", "_host._map_mod"),
    ("essence", "_host.essence"),
    ("rng", "_host.rng"),
    ("_elapsed_minutes()", "_host._elapsed_minutes()"),
]
for a, b in replacements:
    text = text.replace(a, b)
text = text.replace("_host._host.", "_host.")
text = text.replace("func _close() -> void:", "func _close() -> void:")
Path(r"E:\SplitCode\godot\scripts\run\RecruitDraftUI.gd").parent.mkdir(parents=True, exist_ok=True)
Path(r"E:\SplitCode\godot\scripts\run\RecruitDraftUI.gd").write_text(text, encoding="utf-8")
print("lines", len(text.splitlines()))
