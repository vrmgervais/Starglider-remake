extends Node3D
## Starglider-style wireframe flight shooter (Godot 4.x).
## Everything is drawn from code as line meshes, and sound comes from synth.gd.

const SynthScript := preload("res://synth.gd")
const RadarScript := preload("res://radar.gd")

const SPACING := 40.0           # ground grid cell size
const GRID_HALF := 32           # grid lines each side of the player
const WORLD_LIMIT := 1500.0     # invisible walls
const BOSS_KILLS := 14          # kills before Starglider One arrives
const PYLON_COUNT := 90
const BASE_COUNT := 3
const MAX_MISSILES := 9
const TUNNEL_ORIGIN := Vector3(9000, 0, 0)
const TUNNEL_LEN := 700.0
const SETTINGS_PATH := "user://starglider.cfg"

const ACTION_IDS := ["turn_left", "turn_right", "climb", "dive", "faster", "slower", "fire", "missile"]
const ACTION_NAMES := {
	"turn_left": "Turn left", "turn_right": "Turn right", "climb": "Climb", "dive": "Dive",
	"faster": "Speed up", "slower": "Slow down", "fire": "Fire lasers", "missile": "Fire missile",
}
const DEFAULT_KEYS := {
	"turn_left": [KEY_LEFT, KEY_A],
	"turn_right": [KEY_RIGHT, KEY_D],
	"climb": [KEY_UP, KEY_W],
	"dive": [KEY_DOWN, KEY_S],
	"faster": [KEY_E, KEY_EQUAL],
	"slower": [KEY_Q, KEY_MINUS],
	"fire": [KEY_SPACE, KEY_NONE],
	"missile": [KEY_M, KEY_CTRL],
}

# --- scene nodes
var cam: Camera3D
var grid: MeshInstance3D
var synth
var radar
var hud: Label
var cross: Label
var msg: Label
var lock_lbl: Label
var dim: ColorRect
var menu_lbl: Label

# --- options
var bindings: Dictionary = {}
var fullscreen := false
var mouse_flight := false
var invert_y := false
var sens_level := 5
var volume := 0.7

# --- flight state
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var speed := 80.0
var shields := 100.0
var score := 0
var kills := 0
var missiles := 6
var fire_cd := 0.0
var missile_cd := 0.0
var spawn_cd := 1.0
var alarm_t := 0.0
var msg_t := 0.0
var banner := ""
var boss_spawned := false
var state := "play"            # play, tunnel, menu, dead, won
var menu_prev := "play"
var menu_idx := 0
var rebinding := ""
var mouse_dx := 0.0
var mouse_dy := 0.0
var lock = null

# --- world objects
var enemies: Array = []
var shots: Array = []
var enemy_shots: Array = []
var rockets: Array = []
var fx: Array = []
var pylons: Array = []
var bases: Array = []

# --- tunnel run
var tunnel_node: Node3D = null
var obstacles: Array = []
var core: Dictionary = {}
var active_base: Dictionary = {}
var tunnel_speed := 130.0
var tunnel_exit_t := 0.0

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_default_keys()
	_load_settings()
	synth = SynthScript.new()
	add_child(synth)
	synth.volume = volume
	_build_world()
	_build_hud()
	_apply_window()
	_reset()


# ================================================================ settings

func _default_keys() -> void:
	bindings.clear()
	for a in ACTION_IDS:
		bindings[a] = DEFAULT_KEYS[a].duplicate()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	fullscreen = bool(cf.get_value("options", "fullscreen", false))
	mouse_flight = bool(cf.get_value("options", "mouse_flight", false))
	invert_y = bool(cf.get_value("options", "invert_y", false))
	sens_level = int(cf.get_value("options", "sens_level", 5))
	volume = float(cf.get_value("options", "volume", 0.7))
	for a in ACTION_IDS:
		var v = cf.get_value("keys", a, null)
		if v is Array and v.size() == 2:
			bindings[a] = [int(v[0]), int(v[1])]


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("options", "fullscreen", fullscreen)
	cf.set_value("options", "mouse_flight", mouse_flight)
	cf.set_value("options", "invert_y", invert_y)
	cf.set_value("options", "sens_level", sens_level)
	cf.set_value("options", "volume", volume)
	for a in ACTION_IDS:
		cf.set_value("keys", a, bindings[a])
	cf.save(SETTINGS_PATH)


func _apply_window() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_mouse() -> void:
	if mouse_flight and (state == "play" or state == "tunnel"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ================================================================ setup

func _build_world() -> void:
	cam = Camera3D.new()
	cam.far = 5000.0
	add_child(cam)
	cam.current = true

	var segs: Array = []
	var ext: float = GRID_HALF * SPACING
	for i in range(-GRID_HALF, GRID_HALF + 1):
		var o: float = i * SPACING
		segs.append([Vector3(o, 0, -ext), Vector3(o, 0, ext)])
		segs.append([Vector3(-ext, 0, o), Vector3(ext, 0, o)])
	grid = make_wire(segs, Color(0.0, 0.55, 0.15))
	add_child(grid)

	for i in PYLON_COUNT:
		_spawn_pylon(false)
	for i in BASE_COUNT:
		_spawn_base()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = Label.new()
	layer.add_child(hud)
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

	cross = Label.new()
	layer.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.add_theme_font_size_override("font_size", 28)
	cross.text = "+"

	lock_lbl = Label.new()
	layer.add_child(lock_lbl)
	lock_lbl.text = "[   ]"
	lock_lbl.add_theme_font_size_override("font_size", 26)
	lock_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0))
	lock_lbl.visible = false

	msg = Label.new()
	layer.add_child(msg)
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	msg.add_theme_font_size_override("font_size", 22)
	msg.add_theme_color_override("font_color", Color(1, 1, 0.3))

	radar = RadarScript.new()
	layer.add_child(radar)
	radar.game = self
	radar.size = Vector2(190, 190)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	dim = ColorRect.new()
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.8)
	dim.visible = false

	menu_lbl = Label.new()
	layer.add_child(menu_lbl)
	menu_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_lbl.add_theme_font_size_override("font_size", 20)
	menu_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	menu_lbl.visible = false


func _reset() -> void:
	for arr in [enemies, shots, enemy_shots, rockets, fx]:
		for d in arr:
			d["node"].queue_free()
		arr.clear()
	if tunnel_node != null:
		tunnel_node.queue_free()
		tunnel_node = null
	core = {}
	active_base = {}
	obstacles.clear()
	grid.visible = true

	cam.position = Vector3(0, 40, 0)
	yaw = 0.0
	pitch = 0.0
	roll = 0.0
	speed = 80.0
	shields = 100.0
	score = 0
	kills = 0
	missiles = 6
	fire_cd = 0.0
	missile_cd = 0.0
	spawn_cd = 1.0
	boss_spawned = false
	lock = null
	state = "play"
	cross.visible = true
	radar.visible = true
	msg.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	dim.visible = false
	menu_lbl.visible = false
	_say("ESC: options (fullscreen, mouse, keys)    SPACE: lasers    M: missile\nFly into a blue BASE gate for a reactor run!", 9.0)
	_apply_mouse()


func _say(text: String, t: float) -> void:
	banner = text + "\n\n"
	msg_t = t


# ================================================================ wireframe helpers

func make_wire(segs: Array, color: Color) -> MeshInstance3D:
	var verts := PackedVector3Array()
	for s in segs:
		verts.append(s[0])
		verts.append(s[1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func box_segs(c: Vector3, h: Vector3) -> Array:
	var p: Array = []
	for i in 8:
		var x: float = h.x if (i & 1) != 0 else -h.x
		var y: float = h.y if (i & 2) != 0 else -h.y
		var z: float = h.z if (i & 4) != 0 else -h.z
		p.append(c + Vector3(x, y, z))
	var segs: Array = []
	for i in 8:
		for b in [1, 2, 4]:
			if (i & b) == 0:
				segs.append([p[i], p[i | b]])
	return segs


func rect_segs(z: float, x0: float, x1: float, y0: float, y1: float) -> Array:
	var a := Vector3(x0, y0, z)
	var b := Vector3(x1, y0, z)
	var c := Vector3(x1, y1, z)
	var d := Vector3(x0, y1, z)
	return [[a, b], [b, c], [c, d], [d, a]]


func pyramid_segs(half: float, h: float) -> Array:
	var c := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	var apex := Vector3(0, h, 0)
	var segs: Array = []
	for i in 4:
		segs.append([c[i], c[(i + 1) % 4]])
		segs.append([c[i], apex])
	return segs


func cross_segs(r: float) -> Array:
	return [
		[Vector3(-r, 0, 0), Vector3(r, 0, 0)],
		[Vector3(0, -r, 0), Vector3(0, r, 0)],
		[Vector3(0, 0, -r), Vector3(0, 0, r)],
	]


func walker_segs() -> Array:
	var s: Array = []
	s.append_array(box_segs(Vector3(0, 7, 0), Vector3(4, 2.5, 7)))
	s.append_array(box_segs(Vector3(0, 9.5, -9), Vector3(2, 1.8, 2.5)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			s.append([Vector3(sx * 4.0, 5, sz * 5.0), Vector3(sx * 6.5, 0, sz * 6.5)])
	s.append([Vector3(0, 9.5, -11.5), Vector3(0, 9.5, -17)])
	return s


func tank_segs() -> Array:
	var s: Array = []
	s.append_array(box_segs(Vector3(0, 1.8, 0), Vector3(2.6, 1.2, 5)))
	s.append_array(box_segs(Vector3(-3.4, 1.0, 0), Vector3(0.7, 1.0, 5.4)))
	s.append_array(box_segs(Vector3(3.4, 1.0, 0), Vector3(0.7, 1.0, 5.4)))
	s.append_array(box_segs(Vector3(0, 3.8, 0.5), Vector3(1.6, 0.8, 2)))
	s.append([Vector3(0, 3.8, -1.5), Vector3(0, 3.8, -9)])
	return s


func flyer_segs() -> Array:
	var s: Array = []
	var ring: Array = []
	for i in 6:
		var a: float = TAU * i / 6.0
		ring.append(Vector3(cos(a) * 6.0, 0, sin(a) * 6.0))
	for i in 6:
		s.append([ring[i], ring[(i + 1) % 6]])
		s.append([ring[i], Vector3(0, 2.5, 0)])
		s.append([ring[i], Vector3(0, -2.5, 0)])
	s.append([Vector3(0, 0, -6), Vector3(0, 0, -13)])
	return s


func boss_segs() -> Array:
	var s: Array = []
	var nose := Vector3(0, 0, -45)
	var tail := Vector3(0, 0, 30)
	var top := Vector3(0, 8, 0)
	var bot := Vector3(0, -6, 0)
	var fin := Vector3(0, 16, 30)
	s.append([nose, top])
	s.append([nose, bot])
	s.append([top, tail])
	s.append([bot, tail])
	s.append([tail, fin])
	s.append([fin, top])
	for sd in [-1.0, 1.0]:
		var root := Vector3(sd * 8.0, 0, -8)
		var tip := Vector3(sd * 55.0, 6, 28)
		var trail := Vector3(sd * 10.0, 0, 22)
		s.append([nose, root])
		s.append([top, root])
		s.append([bot, root])
		s.append([root, tip])
		s.append([tip, trail])
		s.append([trail, tail])
	return s


func missile_segs() -> Array:
	return [
		[Vector3(0, 0, -3), Vector3(0, 0, 3)],
		[Vector3(0, 0, -3), Vector3(0.8, 0, -1.5)],
		[Vector3(0, 0, -3), Vector3(-0.8, 0, -1.5)],
		[Vector3(0, 0, 2.5), Vector3(1.5, 0, 4)],
		[Vector3(0, 0, 2.5), Vector3(-1.5, 0, 4)],
		[Vector3(0, 0, 2.5), Vector3(0, 1.5, 4)],
		[Vector3(0, 0, 2.5), Vector3(0, -1.5, 4)],
	]


func base_segs() -> Array:
	var s: Array = []
	s.append_array(box_segs(Vector3(0, 10, 0), Vector3(30, 10, 30)))
	# entrance gate in the -Z face, with a ramp and cross-bars
	s.append_array(rect_segs(-30.0, -10.0, 10.0, 1.0, 17.0))
	s.append([Vector3(-10, 1, -30), Vector3(10, 17, -30)])
	s.append([Vector3(10, 1, -30), Vector3(-10, 17, -30)])
	s.append([Vector3(-10, 1, -30), Vector3(-16, 0, -52)])
	s.append([Vector3(10, 1, -30), Vector3(16, 0, -52)])
	s.append([Vector3(-16, 0, -52), Vector3(16, 0, -52)])
	# beacon mast so it can be spotted from afar
	s.append([Vector3(0, 20, 0), Vector3(0, 55, 0)])
	s.append([Vector3(-8, 50, 0), Vector3(8, 50, 0)])
	s.append([Vector3(0, 50, -8), Vector3(0, 50, 8)])
	return s


func core_segs() -> Array:
	var pts := [Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 8, 0), Vector3(0, -8, 0), Vector3(0, 0, 8), Vector3(0, 0, -8)]
	var s: Array = []
	for i in 6:
		for j in range(i + 1, 6):
			if (i >> 1) != (j >> 1):
				s.append([pts[i], pts[j]])
	s.append_array(box_segs(Vector3.ZERO, Vector3(4.5, 4.5, 4.5)))
	return s


# ================================================================ input

func _flying() -> bool:
	return state == "play" or state == "tunnel"


func _bound(k: int, action: String) -> bool:
	return k in bindings[action]


func _held(action: String) -> bool:
	for k in bindings[action]:
		if k != 0 and Input.is_key_pressed(k):
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)
	elif event is InputEventMouseMotion and mouse_flight and _flying():
		mouse_dx += event.relative.x
		mouse_dy += event.relative.y
	elif event is InputEventMouseButton and event.pressed and mouse_flight and _flying():
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_fire_missile()
			MOUSE_BUTTON_WHEEL_UP:
				_change_speed(10.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_change_speed(-10.0)


func _change_speed(d: float) -> void:
	if state == "tunnel":
		tunnel_speed = clampf(tunnel_speed + d, 60.0, 260.0)
	else:
		speed = clampf(speed + d, 30.0, 220.0)


func _on_key(event: InputEventKey) -> void:
	var k: int = event.keycode
	if k == KEY_F11 or (k == KEY_ENTER and event.alt_pressed):
		fullscreen = not fullscreen
		_apply_window()
		_save_settings()
		return
	if rebinding != "":
		if k != KEY_ESCAPE:
			bindings[rebinding][0] = k
			_save_settings()
		rebinding = ""
		return
	if state == "menu":
		_menu_key(k)
		return
	if k == KEY_ESCAPE:
		_open_menu()
		return
	if state == "dead" or state == "won":
		if k == KEY_R:
			_reset()
		return
	if _bound(k, "missile"):
		_fire_missile()


# ================================================================ options menu

func _open_menu() -> void:
	menu_prev = state
	state = "menu"
	menu_idx = 0
	dim.visible = true
	menu_lbl.visible = true
	_apply_mouse()


func _close_menu() -> void:
	state = menu_prev
	dim.visible = false
	menu_lbl.visible = false
	rebinding = ""
	mouse_dx = 0.0
	mouse_dy = 0.0
	_apply_mouse()


func _onoff(b: bool) -> String:
	return "ON" if b else "OFF"


func _kname(k: int) -> String:
	if k == 0:
		return "-"
	return OS.get_keycode_string(k)


func _menu_items() -> Array:
	var it: Array = []
	it.append(["resume", "Resume"])
	it.append(["fullscreen", "Fullscreen: " + _onoff(fullscreen) + "   (F11)"])
	it.append(["mouse", "Mouse flight: " + _onoff(mouse_flight) + "   (left=fire, right=missile, wheel=speed)"])
	it.append(["invert", "Invert mouse pitch: " + _onoff(invert_y)])
	it.append(["sens", "Mouse sensitivity: %d" % sens_level])
	it.append(["volume", "Volume: %d%%" % int(volume * 100.0)])
	for a in ACTION_IDS:
		var ks: Array = bindings[a]
		it.append(["key:" + a, "%s: %s  /  %s" % [ACTION_NAMES[a], _kname(ks[0]), _kname(ks[1])]])
	it.append(["defaults", "Reset keys to default"])
	it.append(["restart", "Restart game"])
	it.append(["quit", "Quit"])
	return it


func _menu_key(k: int) -> void:
	var items: Array = _menu_items()
	match k:
		KEY_ESCAPE:
			_close_menu()
		KEY_UP:
			menu_idx = (menu_idx - 1 + items.size()) % items.size()
		KEY_DOWN:
			menu_idx = (menu_idx + 1) % items.size()
		KEY_LEFT:
			_menu_adjust(items[menu_idx][0], -1)
		KEY_RIGHT:
			_menu_adjust(items[menu_idx][0], 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_menu_activate(items[menu_idx][0])


func _menu_adjust(id: String, d: int) -> void:
	match id:
		"fullscreen":
			fullscreen = not fullscreen
			_apply_window()
		"mouse":
			mouse_flight = not mouse_flight
		"invert":
			invert_y = not invert_y
		"sens":
			sens_level = clampi(sens_level + d, 1, 10)
		"volume":
			volume = clampf(volume + 0.1 * d, 0.0, 1.0)
			synth.volume = volume
			synth.sfx("laser")
		_:
			return
	_save_settings()


func _menu_activate(id: String) -> void:
	if id.begins_with("key:"):
		rebinding = id.substr(4)
		return
	match id:
		"resume":
			_close_menu()
		"defaults":
			_default_keys()
			_save_settings()
		"restart":
			_reset()
		"quit":
			get_tree().quit()
		_:
			_menu_adjust(id, 1)


func _update_menu() -> void:
	var items: Array = _menu_items()
	var t := "===  STARGLIDER  OPTIONS  ===\n"
	t += "Up/Down: select    Left/Right: change    Enter: choose    Esc: resume\n\n"
	for i in items.size():
		t += ("> " if i == menu_idx else "   ") + String(items[i][1]) + "\n"
	if rebinding != "":
		t += "\n>>> Press a new key for: %s   (Esc cancels) <<<" % ACTION_NAMES[rebinding]
	else:
		t += "\nSelect a key row and press Enter to rebind its first key."
	menu_lbl.text = t


# ================================================================ main loop

func _process(dt: float) -> void:
	synth.engine_on = state == "play" or state == "tunnel"
	synth.engine_freq = 38.0 + (tunnel_speed if state == "tunnel" else speed) * 0.35
	missile_cd -= dt

	if state == "menu":
		_update_menu()
		return
	if state == "dead" or state == "won":
		_update_fx(dt)
		return
	if state == "play":
		_update_player(dt)
		_update_spawning(dt)
		_update_enemies(dt)
		_update_bases()
		_update_pylon_collisions()
	else:
		_update_tunnel(dt)
	_update_shots(dt)
	_update_rockets(dt)
	_update_enemy_shots(dt)
	_update_fx(dt)
	if state == "dead" or state == "won":
		return      # _end() just ran: keep its message instead of letting the HUD overwrite it
	_update_hud(dt)


func _handle_fire(dt: float) -> void:
	fire_cd -= dt
	var want: bool = _held("fire") or (mouse_flight and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if want and fire_cd <= 0.0:
		_fire()
		fire_cd = 0.18


func _update_player(dt: float) -> void:
	var turn := 0.0
	var climb := 0.0
	if _held("turn_left"):
		turn += 1.0
	if _held("turn_right"):
		turn -= 1.0
	if _held("climb"):
		climb += 1.0
	if _held("dive"):
		climb -= 1.0
	if _held("faster"):
		speed += 60.0 * dt
	if _held("slower"):
		speed -= 60.0 * dt
	speed = clampf(speed, 30.0, 220.0)

	yaw += turn * 1.3 * dt
	pitch += climb * 1.0 * dt
	if mouse_flight:
		var sens: float = sens_level * 0.0007
		yaw -= mouse_dx * sens
		pitch -= mouse_dy * sens * (-1.0 if invert_y else 1.0)
		turn += clampf(-mouse_dx * 0.05, -1.0, 1.0)
	mouse_dx = 0.0
	mouse_dy = 0.0
	pitch = clampf(pitch, -1.2, 1.2)
	roll = lerpf(roll, turn * 0.5, 4.0 * dt)
	cam.rotation = Vector3(pitch, yaw, roll)

	var fwd: Vector3 = -cam.global_transform.basis.z
	cam.position += fwd * speed * dt
	cam.position.x = clampf(cam.position.x, -WORLD_LIMIT, WORLD_LIMIT)
	cam.position.z = clampf(cam.position.z, -WORLD_LIMIT, WORLD_LIMIT)
	cam.position.y = minf(cam.position.y, 200.0)
	if cam.position.y < 3.0:
		cam.position.y = 3.0
		shields -= 10.0 * dt     # scraping the ground hurts

	grid.position = Vector3(snappedf(cam.position.x, SPACING), 0, snappedf(cam.position.z, SPACING))
	_handle_fire(dt)
	if shields <= 0.0:
		_end("dead")


# ================================================================ weapons

func _fire() -> void:
	var b: Basis = cam.global_transform.basis
	var fwd: Vector3 = -b.z
	var aim_point: Vector3 = cam.position + fwd * 300.0
	for side in [-1.0, 1.0]:
		var pos: Vector3 = cam.position + b * Vector3(side * 2.5, -1.5, -3.0)
		var dir: Vector3 = (aim_point - pos).normalized()
		var bolt := make_wire([[Vector3(0, 0, 0), Vector3(0, 0, -8)]], Color(1, 1, 0))
		add_child(bolt)
		bolt.position = pos
		bolt.look_at(pos + dir, b.y)
		# Inside a base lasers have a short range, so you must fly towards the core.
		shots.append({"node": bolt, "vel": dir * 600.0, "life": 0.55 if state == "tunnel" else 1.8})
	synth.sfx("laser")


func _fire_missile() -> void:
	if state != "play" or missile_cd > 0.0:
		return
	if missiles <= 0:
		_say("OUT OF MISSILES - find a base!", 2.0)
		return
	missiles -= 1
	missile_cd = 0.6
	var b: Basis = cam.global_transform.basis
	var dir: Vector3 = -b.z
	var pos: Vector3 = cam.position + b * Vector3(0, -2.0, -3.0)
	var node := make_wire(missile_segs(), Color(0.4, 1.0, 1.0))
	add_child(node)
	node.position = pos
	node.look_at(pos + dir, b.y)
	rockets.append({"node": node, "dir": dir, "target": lock, "life": 6.0})
	synth.sfx("missile")


func _alive(e) -> bool:
	if e == null:
		return false
	var n = e["node"]
	return is_instance_valid(n) and not n.is_queued_for_deletion()


func _find_lock():
	var best = null
	var best_cos := 0.93
	var inv: Transform3D = cam.global_transform.affine_inverse()
	for e in enemies:
		var en: Node3D = e["node"]
		var rel: Vector3 = inv * (en.position + e["off"])
		var d: float = rel.length()
		if rel.z >= 0.0 or d > 1500.0:
			continue
		var c: float = -rel.z / d
		if c > best_cos:
			best_cos = c
			best = e
	return best


func _update_rockets(dt: float) -> void:
	for i in range(rockets.size() - 1, -1, -1):
		var rk: Dictionary = rockets[i]
		var n: Node3D = rk["node"]
		var dir: Vector3 = rk["dir"]
		var tgt = rk["target"]
		if _alive(tgt):
			var tn: Node3D = tgt["node"]
			var want: Vector3 = ((tn.position + tgt["off"]) - n.position).normalized()
			var ang: float = dir.angle_to(want)
			if ang > 0.0001:
				dir = dir.slerp(want, minf(1.0, 2.4 * dt / ang)).normalized()
		n.position += dir * 240.0 * dt
		rk["dir"] = dir
		if absf(dir.y) < 0.98:
			n.look_at(n.position + dir, Vector3.UP)
		rk["life"] -= dt
		var boom: bool = rk["life"] <= 0.0 or n.position.y < 0.5
		if not boom:
			for e in enemies:
				var en: Node3D = e["node"]
				if n.position.distance_to(en.position + e["off"]) < e["radius"] + 4.0:
					boom = true
					break
		if not boom:
			for p in pylons:
				var pn: Node3D = p["node"]
				if n.position.distance_to(pn.position + p["off"]) < p["radius"] + 3.0:
					boom = true
					break
		if boom:
			_missile_blast(n.position)
			n.queue_free()
			rockets.remove_at(i)


func _missile_blast(pos: Vector3) -> void:
	_explode(pos, 22.0)
	synth.sfx("boom", _dist_gain(pos))
	for e in enemies.duplicate():
		var en: Node3D = e["node"]
		if pos.distance_to(en.position + e["off"]) < 28.0 + e["radius"]:
			_hit_enemy(e, 4)
	for p in pylons.duplicate():
		var pn: Node3D = p["node"]
		if pos.distance_to(pn.position + p["off"]) < 28.0 + p["radius"]:
			_hit_pylon(p)


func _dist_gain(pos: Vector3) -> float:
	return clampf(1.0 - cam.position.distance_to(pos) / 1500.0, 0.15, 1.0)


func _update_shots(dt: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var n: Node3D = s["node"]
		var old: Vector3 = n.position
		var vel: Vector3 = s["vel"]
		n.position = old + vel * dt
		s["life"] -= dt
		var hit := false
		for e in enemies:
			var en: Node3D = e["node"]
			var c: Vector3 = en.position + e["off"]
			var q: Vector3 = Geometry3D.get_closest_point_to_segment(c, old, n.position)
			if q.distance_to(c) < e["radius"]:
				_hit_enemy(e, 1)
				hit = true
				break
		if not hit:
			for p in pylons:
				var pn: Node3D = p["node"]
				var pc: Vector3 = pn.position + p["off"]
				var pq: Vector3 = Geometry3D.get_closest_point_to_segment(pc, old, n.position)
				if pq.distance_to(pc) < p["radius"]:
					_hit_pylon(p)
					hit = true
					break
		if not hit and state == "tunnel":
			# Barriers are solid: bolts only get through the yellow gap.
			for o in obstacles:
				var oz: float = o["z"]
				if (old.z > oz) != (n.position.z > oz):
					var tt: float = (oz - old.z) / (n.position.z - old.z)
					var cp: Vector3 = old.lerp(n.position, tt)
					if absf(cp.x - TUNNEL_ORIGIN.x - o["gx"]) > o["gw"] or absf(cp.y - o["gy"]) > o["gh"]:
						_explode(cp, 3.0)
						synth.sfx("blip", 0.6)
						hit = true
						break
		if not hit and state == "tunnel" and not core.is_empty():
			var cn: Node3D = core["node"]
			var cc: Vector3 = cn.global_position
			var cq: Vector3 = Geometry3D.get_closest_point_to_segment(cc, old, n.position)
			if cq.distance_to(cc) < core["radius"]:
				_hit_core()
				hit = true
		if hit or s["life"] <= 0.0:
			n.queue_free()
			shots.remove_at(i)


func _hit_enemy(e: Dictionary, dmg: int) -> void:
	e["hp"] -= dmg
	var n: Node3D = e["node"]
	if e["hp"] > 0:
		synth.sfx("blip", _dist_gain(n.position))
		return
	_explode(n.position + e["off"], e["radius"])
	synth.sfx("boom", _dist_gain(n.position))
	score += e["value"]
	n.queue_free()
	enemies.erase(e)
	if e["kind"] == "boss":
		_end("won")
	else:
		kills += 1


func _hit_pylon(p: Dictionary) -> void:
	var n: Node3D = p["node"]
	_explode(n.position + p["off"], p["radius"])
	synth.sfx("small_boom", _dist_gain(n.position))
	score += 25
	n.queue_free()
	pylons.erase(p)
	_spawn_pylon(true)


func _hit_core() -> void:
	core["hp"] -= 1
	synth.sfx("blip")
	if core["hp"] > 0:
		return
	var cn: Node3D = core["node"]
	_explode(cn.global_position, 30.0)
	synth.sfx("boom")
	cn.queue_free()
	core = {}
	score += 1000
	tunnel_exit_t = 1.0
	_say("REACTOR DESTROYED!", 2.0)


func _explode(pos: Vector3, r: float) -> void:
	var segs: Array = []
	for i in 24:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		segs.append([d * r * 0.3, d * r * 0.9])
	var n := make_wire(segs, Color(1, 0.8, 0.1))
	add_child(n)
	n.position = pos
	fx.append({"node": n, "t": 0.0})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		var n: Node3D = f["node"]
		f["t"] += dt
		n.scale = Vector3.ONE * (1.0 + f["t"] * 4.0)
		if f["t"] > 0.7:
			n.queue_free()
			fx.remove_at(i)


# ================================================================ world objects

func _spawn_pylon(avoid_player: bool) -> void:
	var h: float = rng.randf_range(10.0, 32.0)
	var palette := [Color(0.0, 0.8, 0.8), Color(0.2, 0.9, 0.3), Color(0.8, 0.8, 0.2)]
	var node := make_wire(pyramid_segs(h * 0.6, h), palette[rng.randi() % 3])
	add_child(node)
	var p := Vector3.ZERO
	for attempt in 6:
		p = Vector3(rng.randf_range(-WORLD_LIMIT, WORLD_LIMIT), 0, rng.randf_range(-WORLD_LIMIT, WORLD_LIMIT))
		if not avoid_player or p.distance_to(cam.position) > 300.0:
			break
	node.position = p
	pylons.append({"node": node, "radius": h * 0.55, "off": Vector3(0, h * 0.35, 0)})


func _spawn_base() -> void:
	var p := Vector3.ZERO
	for attempt in 8:
		p = Vector3(rng.randf_range(-1100, 1100), 0, rng.randf_range(-1100, 1100))
		if Vector2(p.x, p.z).length() > 350.0:
			break
	var node := make_wire(base_segs(), Color(0.3, 0.55, 1.0))
	add_child(node)
	node.position = p
	var ry: float = rng.randf() * TAU
	node.rotation.y = ry
	bases.append({"node": node, "ry": ry})


func _update_pylon_collisions() -> void:
	for p in pylons.duplicate():
		var pn: Node3D = p["node"]
		if cam.position.distance_to(pn.position + p["off"]) < p["radius"] * 0.8:
			shields -= 15.0
			synth.sfx("hit")
			_say("PYLON COLLISION!", 1.0)
			_hit_pylon(p)


func _update_spawning(dt: float) -> void:
	spawn_cd -= dt
	if kills >= BOSS_KILLS and not boss_spawned:
		boss_spawned = true
		_spawn("boss")
		_say("STARGLIDER ONE APPROACHING!", 5.0)
		return
	if spawn_cd <= 0.0 and enemies.size() < 5 and not boss_spawned:
		spawn_cd = rng.randf_range(2.0, 4.0)
		var r: float = rng.randf()
		if r < 0.3:
			_spawn("walker")
		elif r < 0.65:
			_spawn("tank")
		else:
			_spawn("flyer")


func _spawn(kind: String) -> void:
	var ang: float = rng.randf() * TAU
	var dist: float = rng.randf_range(700.0, 1000.0)
	var p: Vector3 = cam.position + Vector3(cos(ang), 0, sin(ang)) * dist
	p.x = clampf(p.x, -WORLD_LIMIT, WORLD_LIMIT)
	p.z = clampf(p.z, -WORLD_LIMIT, WORLD_LIMIT)
	var e := {"kind": kind, "cd": rng.randf_range(1.0, 3.0), "mode": 0, "t": 0.0}
	var node: Node3D
	match kind:
		"walker":
			node = make_wire(walker_segs(), Color(1, 0.2, 0.2))
			e["hp"] = 3
			e["radius"] = 9.0
			e["off"] = Vector3(0, 7, 0)
			e["value"] = 100
			p.y = 0.0
		"tank":
			node = make_wire(tank_segs(), Color(1, 0.6, 0.1))
			e["hp"] = 2
			e["radius"] = 7.0
			e["off"] = Vector3(0, 2.5, 0)
			e["value"] = 75
			p.y = 0.0
		"flyer":
			node = make_wire(flyer_segs(), Color(1, 0, 1))
			e["hp"] = 1
			e["radius"] = 8.0
			e["off"] = Vector3.ZERO
			e["value"] = 150
			p.y = rng.randf_range(25.0, 80.0)
		_:
			node = make_wire(boss_segs(), Color(1, 1, 0.2))
			e["hp"] = 30
			e["radius"] = 30.0
			e["off"] = Vector3.ZERO
			e["value"] = 2000
			p.y = 70.0
	add_child(node)
	node.position = p
	e["node"] = node
	enemies.append(e)


func _update_enemies(dt: float) -> void:
	var p: Vector3 = cam.position
	for e in enemies:
		var n: Node3D = e["node"]
		var to_p: Vector3 = p - n.position
		var dist: float = to_p.length()
		e["cd"] -= dt
		match e["kind"]:
			"walker":
				var flat := Vector3(to_p.x, 0, to_p.z)
				if flat.length() > 1.0:
					n.look_at(Vector3(p.x, n.position.y, p.z), Vector3.UP)
					if dist > 300.0:
						n.position += flat.normalized() * 14.0 * dt
				if e["cd"] <= 0.0 and dist < 700.0:
					e["cd"] = 2.2
					_enemy_shoot(n.position + Vector3(0, 9.5, 0))
			"tank":
				var tflat := Vector3(to_p.x, 0, to_p.z)
				if tflat.length() > 1.0:
					n.look_at(Vector3(p.x, n.position.y, p.z), Vector3.UP)
					if dist > 220.0:
						n.position += tflat.normalized() * 22.0 * dt
				if e["cd"] <= 0.0 and dist < 600.0:
					e["cd"] = 1.8
					_enemy_shoot(n.position + Vector3(0, 4.5, 0))
			"flyer":
				var mv := Vector3.ZERO
				if e["mode"] == 0:
					mv = to_p.normalized() * 110.0
					if dist < 130.0:
						e["mode"] = 1
						e["t"] = 0.0
						e["evade"] = (-to_p.normalized() + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 0.8), rng.randf_range(-1, 1))).normalized()
					elif dist < 550.0 and e["cd"] <= 0.0:
						e["cd"] = 1.5
						_enemy_shoot(n.position)
				else:
					e["t"] += dt
					var ev: Vector3 = e["evade"]
					mv = ev * 120.0
					if e["t"] > 3.0:
						e["mode"] = 0
				n.position += mv * dt
				n.position.y = clampf(n.position.y, 10.0, 160.0)
				if mv.length() > 1.0:
					var look_dir: Vector3 = mv.normalized()
					if absf(look_dir.y) < 0.95:
						n.look_at(n.position + look_dir, Vector3.UP)
			_:
				var dirb: Vector3 = to_p.normalized()
				if dist > 350.0:
					n.position += dirb * 45.0 * dt
				else:
					n.position += dirb.cross(Vector3.UP).normalized() * 30.0 * dt
				n.position.y = clampf(n.position.y, 45.0, 110.0)
				if absf(dirb.y) < 0.95:
					n.look_at(p, Vector3.UP)
				if e["cd"] <= 0.0 and dist < 900.0:
					e["cd"] = 0.9
					for sx in [-1.0, 1.0]:
						_enemy_shoot(n.global_transform * Vector3(sx * 30.0, 4, 20))


func _enemy_shoot(from: Vector3) -> void:
	var to_p: Vector3 = cam.position - from
	var fwd: Vector3 = -cam.global_transform.basis.z
	var t: float = to_p.length() / 130.0
	# Lead the target a little, with some jitter so it can be dodged.
	var target: Vector3 = cam.position + fwd * speed * t * 0.8
	target += Vector3(rng.randf_range(-10, 10), rng.randf_range(-10, 10), rng.randf_range(-10, 10))
	var vel: Vector3 = (target - from).normalized() * 130.0
	var bolt := make_wire(cross_segs(2.0), Color(1, 0.4, 0.2))
	add_child(bolt)
	bolt.position = from
	enemy_shots.append({"node": bolt, "vel": vel, "life": 6.0})
	synth.sfx("enemy_shot", _dist_gain(from))


func _update_enemy_shots(dt: float) -> void:
	for i in range(enemy_shots.size() - 1, -1, -1):
		var s: Dictionary = enemy_shots[i]
		var n: Node3D = s["node"]
		var vel: Vector3 = s["vel"]
		n.position += vel * dt
		n.rotation += Vector3(5, 7, 3) * dt
		s["life"] -= dt
		var remove := false
		if n.position.distance_to(cam.position) < 6.0:
			shields -= 10.0
			_explode(n.position, 4.0)
			synth.sfx("hit")
			remove = true
		elif s["life"] <= 0.0 or n.position.y < 0.0:
			remove = true
		if remove:
			n.queue_free()
			enemy_shots.remove_at(i)


# ================================================================ bases and reactor tunnel

func _update_bases() -> void:
	for b in bases:
		var bn: Node3D = b["node"]
		var gate: Vector3 = bn.global_transform * Vector3(0, 9, -30)
		if cam.position.distance_to(gate) < 15.0:
			_enter_tunnel(b)
			return


func _enter_tunnel(b: Dictionary) -> void:
	active_base = b
	state = "tunnel"
	synth.sfx("pickup")
	for arr in [enemy_shots, rockets, shots]:
		for d in arr:
			d["node"].queue_free()
		arr.clear()
	lock = null
	grid.visible = false
	_build_tunnel()
	cam.position = TUNNEL_ORIGIN + Vector3(0, 20, 0)
	yaw = 0.0
	pitch = 0.0
	roll = 0.0
	cam.rotation = Vector3.ZERO
	mouse_dx = 0.0
	mouse_dy = 0.0
	tunnel_exit_t = 0.0
	tunnel_speed = 130.0
	_say("INSIDE THE BASE!  Dodge the barriers (fly through the yellow gaps)\nand destroy the reactor core at the end!", 5.0)


func _build_tunnel() -> void:
	if tunnel_node != null:
		tunnel_node.queue_free()
	tunnel_node = Node3D.new()
	add_child(tunnel_node)
	tunnel_node.position = TUNNEL_ORIGIN
	var hx := 18.0
	var y0 := 6.0
	var y1 := 34.0

	var segs: Array = []
	var z := 0.0
	while z >= -TUNNEL_LEN:
		segs.append_array(rect_segs(z, -hx, hx, y0, y1))
		z -= 20.0
	for cx in [-hx, hx]:
		for cy in [y0, y1]:
			segs.append([Vector3(cx, cy, 0), Vector3(cx, cy, -TUNNEL_LEN)])
	tunnel_node.add_child(make_wire(segs, Color(0.0, 0.7, 0.9)))

	obstacles.clear()
	var oz := -90.0
	while oz > -TUNNEL_LEN + 60.0:
		var gx: float = rng.randf_range(-9.0, 9.0)
		var gy: float = rng.randf_range(15.0, 25.0)
		var gw := 7.0
		var gh := 6.0
		obstacles.append({"z": oz, "gx": gx, "gy": gy, "gw": gw, "gh": gh, "done": false})
		var wall: Array = rect_segs(oz, -hx, hx, y0, y1)
		wall.append([Vector3(-hx, y0, oz), Vector3(gx - gw, gy - gh, oz)])
		wall.append([Vector3(hx, y0, oz), Vector3(gx + gw, gy - gh, oz)])
		wall.append([Vector3(hx, y1, oz), Vector3(gx + gw, gy + gh, oz)])
		wall.append([Vector3(-hx, y1, oz), Vector3(gx - gw, gy + gh, oz)])
		tunnel_node.add_child(make_wire(wall, Color(1, 0.3, 0.3)))
		tunnel_node.add_child(make_wire(rect_segs(oz, gx - gw, gx + gw, gy - gh, gy + gh), Color(1, 1, 0)))
		oz -= 90.0

	var cz := -TUNNEL_LEN + 15.0
	var core_node := make_wire(core_segs(), Color(1, 0.2, 1))
	tunnel_node.add_child(core_node)
	core_node.position = Vector3(0, 20, cz)
	core = {"node": core_node, "hp": 8, "radius": 10.0, "z": cz}


func _update_tunnel(dt: float) -> void:
	var lx := 0.0
	var ly := 0.0
	if _held("turn_left"):
		lx -= 1.0
	if _held("turn_right"):
		lx += 1.0
	if _held("climb"):
		ly += 1.0
	if _held("dive"):
		ly -= 1.0
	if mouse_flight:
		lx += clampf(mouse_dx * 0.08, -2.0, 2.0)
		ly -= clampf(mouse_dy * 0.08 * (-1.0 if invert_y else 1.0), -2.0, 2.0)
	mouse_dx = 0.0
	mouse_dy = 0.0

	if _held("faster"):
		tunnel_speed += 80.0 * dt
	if _held("slower"):
		tunnel_speed -= 80.0 * dt
	tunnel_speed = clampf(tunnel_speed, 60.0, 260.0)

	var rel_x: float = cam.position.x - TUNNEL_ORIGIN.x
	rel_x = clampf(rel_x + lx * 50.0 * dt, -15.5, 15.5)
	cam.position.x = TUNNEL_ORIGIN.x + rel_x
	cam.position.y = clampf(cam.position.y + ly * 50.0 * dt, 9.0, 31.0)
	cam.position.z -= tunnel_speed * dt
	roll = lerpf(roll, -lx * 0.35, 5.0 * dt)
	cam.rotation = Vector3(0, 0, roll)
	_handle_fire(dt)

	if not core.is_empty():
		var cn: Node3D = core["node"]
		cn.rotation += Vector3(0.7, 1.1, 0.3) * dt

	var rz: float = cam.position.z
	for o in obstacles:
		if not o["done"] and rz < o["z"]:
			o["done"] = true
			var dx: float = absf(rel_x - o["gx"])
			var dy: float = absf(cam.position.y - o["gy"])
			if dx > o["gw"] - 1.0 or dy > o["gh"] - 1.0:
				shields -= 20.0
				synth.sfx("hit")
				_say("BARRIER HIT!", 1.0)

	if shields <= 0.0:
		_end("dead")
		return
	if not core.is_empty():
		if rz < float(core["z"]) + 12.0:
			shields -= 30.0
			synth.sfx("hit")
			_say("MISSED THE CORE - EJECTING!", 2.5)
			_exit_tunnel(false)
	else:
		tunnel_exit_t -= dt
		if tunnel_exit_t <= 0.0 or rz < -TUNNEL_LEN - 20.0:
			_exit_tunnel(true)


func _exit_tunnel(success: bool) -> void:
	if success:
		shields = 100.0
		missiles = mini(MAX_MISSILES, missiles + 4)
		score += 500
		synth.sfx("pickup")
		_say("BASE DESTROYED!  SHIELDS RESTORED  +4 MISSILES", 4.0)
	var b: Dictionary = active_base
	var node: Node3D = b["node"]
	var gate: Vector3 = node.global_transform * Vector3(0, 9, -30)
	var out: Vector3 = node.global_transform.basis * Vector3(0, 0, -1)
	cam.position = gate + out * 70.0 + Vector3(0, 16, 0)
	yaw = b["ry"]
	pitch = 0.0
	roll = 0.0
	state = "play"
	grid.visible = true
	for d in shots:
		d["node"].queue_free()
	shots.clear()
	if tunnel_node != null:
		tunnel_node.queue_free()
		tunnel_node = null
	core = {}
	obstacles.clear()
	if success:
		node.queue_free()
		bases.erase(b)
		_spawn_base()
	active_base = {}
	_apply_mouse()


# ================================================================ end of game and HUD

func _end(result: String) -> void:
	state = result
	cross.visible = false
	radar.visible = false
	lock_lbl.visible = false
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if result == "won":
		msg.text = "STARGLIDER ONE DESTROYED!\nNOVENIA IS SAVED\n\nSCORE %06d\n\nPress R to play again" % score
	else:
		msg.text = "SHIELDS DOWN\n\nSCORE %06d\n\nPress R to try again" % score
	_apply_mouse()


func _dir_text(rel: Vector3, dist: float) -> String:
	if rel.z > 0.0:
		return "BEHIND"
	if absf(rel.x) < dist * 0.15 and absf(rel.y) < dist * 0.15:
		return "AHEAD"
	return ("RIGHT" if rel.x > 0.0 else "LEFT") + ("/UP" if rel.y > 0.0 else "/DOWN")


func _update_hud(dt: float) -> void:
	var t: String
	if state == "tunnel":
		var cd := 0.0
		if not core.is_empty():
			cd = maxf(0.0, cam.position.z - float(core["z"]))
		t = "REACTOR RUN\nSHIELDS %3d%%   SCORE %06d\nSPEED %3d   CORE DISTANCE %4dm" % [int(shields), score, int(tunnel_speed), int(cd)]
		radar.visible = false
		lock_lbl.visible = false
	else:
		t = "SHIELDS %3d%%   SCORE %06d\nSPEED %3d   ALT %3d\nMISSILES %d   KILLS %d / %d" % [int(shields), score, int(speed), int(cam.position.y), missiles, kills, BOSS_KILLS]
		radar.visible = true
		var inv: Transform3D = cam.global_transform.affine_inverse()

		var best := 1.0e9
		var rel_best := Vector3.ZERO
		for e in enemies:
			var en: Node3D = e["node"]
			var rel: Vector3 = inv * (en.position + e["off"])
			if rel.length() < best:
				best = rel.length()
				rel_best = rel
		if best < 1.0e8:
			t += "\nNEAREST EGRON %4dm  %s" % [int(best), _dir_text(rel_best, best)]

		var bbest := 1.0e9
		var brel := Vector3.ZERO
		for b in bases:
			var bn: Node3D = b["node"]
			var r2: Vector3 = inv * bn.position
			if r2.length() < bbest:
				bbest = r2.length()
				brel = r2
		if bbest < 1.0e8:
			t += "\nNEAREST BASE  %4dm  %s" % [int(bbest), _dir_text(brel, bbest)]

		lock = _find_lock()
		if lock != null:
			var ln: Node3D = lock["node"]
			var wp: Vector3 = ln.position + lock["off"]
			if cam.is_position_behind(wp):
				lock_lbl.visible = false
			else:
				lock_lbl.position = cam.unproject_position(wp) - Vector2(26, 20)
				lock_lbl.visible = true
		else:
			lock_lbl.visible = false

		radar.position = get_viewport().get_visible_rect().size - Vector2(206, 206)
		radar.queue_redraw()
	hud.text = t

	if shields < 25.0:
		alarm_t -= dt
		if alarm_t <= 0.0:
			synth.sfx("alarm")
			alarm_t = 0.8

	msg_t -= dt
	msg.text = banner if msg_t > 0.0 else ""
