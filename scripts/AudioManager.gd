extends Node
class_name MikrozzAudio

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var music_volume := 0.32
var sfx_volume := 0.75
var enabled := true

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.stream = _make_music()
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "SfxPlayer"
	add_child(sfx_player)
	_apply_volumes()
	music_player.play()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()

func set_enabled(value: bool) -> void:
	enabled = value
	_apply_volumes()

func _apply_volumes() -> void:
	if is_instance_valid(music_player):
		music_player.volume_db = linear_to_db(maxf(music_volume, 0.0001))
		music_player.stream_paused = not enabled or music_volume <= 0.001
	if is_instance_valid(sfx_player):
		sfx_player.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))

func play_coin() -> void:
	_play_tone(880.0, 0.12)

func play_win() -> void:
	_play_tone(660.0, 0.32)

func play_hit() -> void:
	_play_tone(180.0, 0.22)

func play_ui() -> void:
	_play_tone(520.0, 0.07)

func _play_tone(frequency: float, duration: float) -> void:
	if not enabled or sfx_volume <= 0.001:
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var count := int(22050.0 * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t := float(i) / 22050.0
		var envelope := minf(1.0, t * 35.0) * pow(maxf(0.0, 1.0 - t / duration), 1.8)
		var sample := sin(TAU * frequency * t) * envelope * 0.22
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	wav.data = bytes
	sfx_player.stream = wav
	sfx_player.play()

func _make_music() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var rate := 22050
	var beat := 0.5
	var notes := [261.63, 329.63, 392.00, 329.63, 293.66, 349.23, 440.00, 349.23, 261.63, 329.63, 392.00, 523.25, 440.00, 392.00, 349.23, 293.66]
	var count := int(rate * beat * notes.size())
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t := float(i) / rate
		var beat_index := mini(notes.size() - 1, int(t / beat))
		var local_t := fmod(t, beat)
		var envelope := minf(1.0, local_t * 12.0) * (0.72 + 0.28 * cos(PI * local_t / beat))
		var f := notes[beat_index]
		var tone := sin(TAU * f * t) * 0.55 + sin(TAU * f * 0.5 * t) * 0.18
		var pad := sin(TAU * (f * 1.5) * t) * 0.12
		var sample := (tone + pad) * envelope * 0.13
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav
