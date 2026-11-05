extends Node
## Tiny retro synthesiser built on AudioStreamGenerator.
## Call sfx("laser") etc. from the game; the engine hum is driven by engine_on / engine_freq.

const MIX_RATE := 22050.0


class Voice:
	var kind := 0       # 0 square, 1 noise, 2 saw, 3 sine
	var t := 0.0
	var dur := 0.2
	var f0 := 440.0
	var f1 := 440.0
	var vol := 0.3
	var delay := 0.0
	var phase := 0.0
	var lp := 0.0


var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var voices: Array = []
var volume := 0.7
var engine_on := false
var engine_freq := 50.0
var engine_phase := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.25
	player = AudioStreamPlayer.new()
	player.stream = gen
	add_child(player)
	player.play()
	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


func play(kind: int, f0: float, f1: float, dur: float, vol: float, delay: float = 0.0) -> void:
	if voices.size() > 28:
		voices.pop_front()
	var v := Voice.new()
	v.kind = kind
	v.f0 = f0
	v.f1 = f1
	v.dur = dur
	v.vol = vol
	v.delay = delay
	voices.append(v)


func sfx(sound: String, gain: float = 1.0) -> void:
	match sound:
		"laser":
			play(0, 1500.0, 300.0, 0.16, 0.16 * gain)
		"enemy_shot":
			play(2, 520.0, 150.0, 0.22, 0.12 * gain)
		"missile":
			play(1, 0.0, 0.0, 0.7, 0.22 * gain)
			play(2, 90.0, 280.0, 0.7, 0.12 * gain)
		"boom":
			play(1, 0.0, 0.0, 0.9, 0.55 * gain)
			play(3, 90.0, 30.0, 0.6, 0.35 * gain)
		"small_boom":
			play(1, 0.0, 0.0, 0.35, 0.3 * gain)
		"blip":
			play(0, 900.0, 600.0, 0.05, 0.12 * gain)
		"hit":
			play(2, 220.0, 60.0, 0.3, 0.35 * gain)
			play(1, 0.0, 0.0, 0.25, 0.3 * gain)
		"alarm":
			play(0, 880.0, 880.0, 0.12, 0.12 * gain)
		"pickup":
			play(0, 523.0, 523.0, 0.09, 0.18 * gain, 0.0)
			play(0, 659.0, 659.0, 0.09, 0.18 * gain, 0.09)
			play(0, 784.0, 784.0, 0.09, 0.18 * gain, 0.18)
			play(0, 1046.0, 1046.0, 0.18, 0.18 * gain, 0.27)


func _process(_dt: float) -> void:
	if playback == null:
		return
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / MIX_RATE
	for i in frames:
		var s := 0.0
		if engine_on:
			engine_phase = fmod(engine_phase + engine_freq * dt, 1.0)
			s += (engine_phase * 2.0 - 1.0) * 0.05
		for v in voices:
			if v.delay > 0.0:
				v.delay -= dt
				continue
			v.t += dt
			var u: float = v.t / v.dur
			if u >= 1.0:
				continue
			var env: float = (1.0 - u) * (1.0 - u)
			v.phase = fmod(v.phase + lerpf(v.f0, v.f1, u) * dt, 1.0)
			var w := 0.0
			match v.kind:
				0:
					w = 1.0 if v.phase < 0.5 else -1.0
				1:
					v.lp += (randf() * 2.0 - 1.0 - v.lp) * 0.2
					w = v.lp * 2.0
				2:
					w = v.phase * 2.0 - 1.0
				_:
					w = sin(v.phase * TAU)
			s += w * env * v.vol
		s = clampf(s * volume, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	playback.push_buffer(buf)
	for i in range(voices.size() - 1, -1, -1):
		var v = voices[i]
		if v.delay <= 0.0 and v.t >= v.dur:
			voices.remove_at(i)
