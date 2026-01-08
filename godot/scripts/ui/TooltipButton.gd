class_name TooltipButton
extends Button

@export var tooltip_accent: Color = UiSkin.ACCENT

func _make_custom_tooltip(for_text: String) -> Object:
	# `for_text` is whatever is in `tooltip_text`.
	return UiTooltip.build(for_text, tooltip_accent)



