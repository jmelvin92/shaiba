class_name ScreenFade
extends CanvasLayer
## A reusable full-screen fade to and from black (Phase 6.8 Part 3, built
## for the worm's swallow but generic by design — future sleep, teleport or
## cutscene transitions get it free). Sits above the game and below the
## pause menu; ignores the mouse; costs nothing while fully transparent.

## Seconds a fade takes when the caller doesn't say.
@export_range(0.1, 5.0, 0.05) var default_seconds: float = 0.8

var _rect: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	_rect = get_node(^"Rect") as ColorRect
	_rect.visible = _rect.color.a > 0.0


## Fade to black. Awaitable: `await fade.fade_out(0.9)` resumes at full
## black. Restartable mid-fade — the newest call wins.
func fade_out(seconds: float = -1.0) -> void:
	await _fade_to(1.0, seconds)


## Fade back in. Awaitable like [method fade_out].
func fade_in(seconds: float = -1.0) -> void:
	await _fade_to(0.0, seconds)


func is_black() -> bool:
	return _rect.color.a >= 0.999


func _fade_to(alpha: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_rect.visible = true
	_tween = create_tween()
	_tween.tween_property(
		_rect, ^"color:a", alpha,
		seconds if seconds > 0.0 else default_seconds
	)
	await _tween.finished
	_rect.visible = _rect.color.a > 0.0
