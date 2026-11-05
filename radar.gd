extends Control
## Heading-up top-down radar. `game` is set by main.gd.

const RANGE := 1200.0

var game


func _draw() -> void:
	if game == null or game.cam == null:
		return
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 3.0
	draw_circle(c, r, Color(0.0, 0.1, 0.0, 0.6))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.2, 1.0, 0.2), 1.5)
	draw_arc(c, r * 0.5, 0.0, TAU, 48, Color(0.1, 0.5, 0.1), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.1, 0.45, 0.1), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.1, 0.45, 0.1), 1.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(-5, 6), c + Vector2(5, 6)]), Color(1, 1, 1))

	for b in game.bases:
		var bn: Node3D = b["node"]
		_blip(bn.position, Color(0.4, 0.6, 1.0), 3, r)
	for e in game.enemies:
		var en: Node3D = e["node"]
		match e["kind"]:
			"walker":
				_blip(en.position, Color(1, 0.25, 0.25), 0, r)
			"tank":
				_blip(en.position, Color(1, 0.6, 0.1), 2, r)
			"flyer":
				_blip(en.position, Color(1, 0.2, 1), 1, r)
			_:
				_blip(en.position, Color(1, 1, 0.2), 4, r)


func _blip(pos: Vector3, col: Color, shape: int, r: float) -> void:
	var delta: Vector3 = pos - game.cam.position
	var local: Vector3 = Basis(Vector3.UP, game.yaw).inverse() * delta
	var p := Vector2(local.x, local.z) * (r / RANGE)
	if p.length() > r - 4.0:
		p = p.normalized() * (r - 4.0)
		col = col.darkened(0.45)
	var c: Vector2 = size * 0.5 + p
	match shape:
		0:
			draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), col)
		1:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.5), c + Vector2(4.5, 0), c + Vector2(0, 4.5), c + Vector2(-4.5, 0)]), col)
		2:
			draw_circle(c, 3.5, col)
		3:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 4), c + Vector2(-5, 4)]), col)
		_:
			draw_circle(c, 6.0, col)
			draw_arc(c, 9.0, 0.0, TAU, 20, col, 1.0)
