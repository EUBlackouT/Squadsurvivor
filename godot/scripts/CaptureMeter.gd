# CaptureMeter.gd
# Tracks capture progress from 0-100, triggers Recruit Drafts

class_name CaptureMeter

extends Node

signal draft_ready()

@export var capture_normal: float = 1.5  # Points per normal enemy kill
@export var capture_elite: float = 10.0  # Points per elite kill
@export var capture_camp: float = 15.0   # Points per camp cleared

var current_capture: float = 0.0
const CAPTURE_MAX: float = 100.0

func add_capture_normal() -> void:
	current_capture += capture_normal
	_check_draft()

func add_capture_elite() -> void:
	current_capture += capture_elite
	_check_draft()

func add_capture_camp() -> void:
	current_capture += capture_camp
	_check_draft()

func _check_draft() -> void:
	if current_capture >= CAPTURE_MAX:
		current_capture = 0.0
		draft_ready.emit()

func get_capture_percent() -> float:
	return current_capture / CAPTURE_MAX
