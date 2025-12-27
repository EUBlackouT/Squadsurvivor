# CaptureMeterUI.gd
# UI overlay showing capture meter progress

extends Control

@onready var progress_bar: ProgressBar = get_node_or_null("ProgressBar")
@onready var label: Label = get_node_or_null("Label")

var capture_meter: CaptureMeter

func setup(meter: CaptureMeter) -> void:
	capture_meter = meter
	if not capture_meter:
		return
	
	# Update every frame
	set_process(true)

func _process(_delta: float) -> void:
	if not capture_meter:
		return
	
	if progress_bar:
		progress_bar.value = capture_meter.get_capture_percent() * 100.0
	
	if label:
		label.text = "Capture: " + str(int(capture_meter.current_capture)) + "/100"

