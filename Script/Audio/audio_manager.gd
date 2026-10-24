extends Node

# ---------------------------------------------------------------------------
# 音频管理器（Autoload: Audio）
# 所有音效与 BGM 都在运行时用 PCM 合成，不依赖任何外部音频素材，
# 所以导出/换素材都不会因为缺失文件报错。以后想换成真实素材：
# 把 _build_streams() 里的合成结果替换成 load("res://...wav") 即可。
# ---------------------------------------------------------------------------

const RATE := 16000          # 采样率：音色走复古风，同时降低启动合成耗时
const MAX_VOICES := 8        # 同时播放的音效数量
const SFX_COOLDOWN_MS := 40  # 同名音效最小间隔，防止同帧刷屏

# 放了真实 BGM 就优先用它（导入后 load 得到），否则退回运行时合成
const BGM_CANDIDATES := [
	"res://GameResource/Audio/bgm.ogg",
	"res://GameResource/Audio/bgm.mp3",
	"res://GameResource/Audio/bgm.wav",
]

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played: Dictionary = {}
var _bgm_player: AudioStreamPlayer
var _muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	for i in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		player.volume_db = -8.0
		add_child(player)
		_players.append(player)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.volume_db = -20.0
	add_child(_bgm_player)
	# BGM 合成稍重，延后一帧，避免拖慢首屏
	_build_bgm.call_deferred()


func play(sound: String, volume_db: float = -8.0) -> void:
	if _muted:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -10000)) < SFX_COOLDOWN_MS:
		return
	_last_played[sound] = now
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func set_muted(value: bool) -> void:
	_muted = value
	if _bgm_player != null:
		_bgm_player.stream_paused = value


func is_muted() -> bool:
	return _muted


func _build_streams() -> void:
	_streams["shoot"] = _tone(880.0, 0.06, 1, 0.22, 2.0, -600.0)
	_streams["hit"] = _noise(0.05, 0.20, 1200.0, 3.0)
	_streams["magic"] = _tone(520.0, 0.12, 0, 0.22, 1.4, 420.0)
	_streams["thunder"] = _mix([_noise(0.35, 0.28, 700.0, 1.6), _tone(90.0, 0.35, 0, 0.25, 1.2, -40.0)])
	_streams["ice"] = _mix([_tone(1320.0, 0.18, 0, 0.16, 1.6, -500.0), _noise(0.18, 0.10, 5000.0, 2.0)])
	_streams["wind"] = _noise(0.30, 0.16, 2400.0, 1.2)
	_streams["hurt"] = _tone(220.0, 0.28, 1, 0.28, 1.3, -140.0)
	_streams["heal"] = _mix([_tone(520.0, 0.10, 0, 0.18, 1.6, 0.0), _tone(780.0, 0.16, 0, 0.16, 1.6, 0.0)])
	_streams["levelup"] = _arpeggio([523.0, 659.0, 784.0, 1046.0], 0.07, 0.22)
	_streams["reward"] = _arpeggio([784.0, 1046.0], 0.08, 0.22)
	_streams["click"] = _tone(1200.0, 0.03, 1, 0.14, 3.0, 0.0)
	_streams["wave"] = _arpeggio([392.0, 523.0, 659.0], 0.12, 0.22)
	_streams["gameover"] = _mix([
		_tone(392.0, 0.9, 0, 0.26, 0.8, -240.0),
		_tone(196.0, 0.9, 0, 0.18, 0.8, -90.0),
	])


func _build_bgm() -> void:
	var music := _load_bgm_file()
	if music != null:
		_bgm_player.stream = music
		_bgm_player.volume_db = -14.0
	else:
		_bgm_player.stream = _make_bgm()
		_bgm_player.volume_db = -20.0
	_bgm_player.play()


func _load_bgm_file() -> AudioStream:
	for path in BGM_CANDIDATES:
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = floori(wav.data.size() / 2.0)
		return stream
	return null


# --- 合成工具 ---------------------------------------------------------------

func _wav(data: PackedByteArray, loop: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = floori(data.size() / 2.0)
	return stream


func _tone(freq: float, duration: float, wave: int = 0, volume: float = 0.25,
		decay: float = 1.5, sweep: float = 0.0) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var k := float(i) / float(maxi(count - 1, 1))
		var f := freq + sweep * k
		phase += TAU * f / float(RATE)
		var s := sin(phase)
		if wave == 1:
			s = 1.0 if s >= 0.0 else -1.0
		elif wave == 2:
			s = sin(phase) + 0.33 * sin(phase * 3.0)
		var envelope := pow(clampf(1.0 - t / duration, 0.0, 1.0), decay)
		data.encode_s16(i * 2, clampi(int(s * envelope * volume * 32000.0), -32768, 32767))
	return _wav(data)


func _noise(duration: float, volume: float = 0.2, cutoff: float = 2000.0,
		decay: float = 2.0) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261024
	var prev := 0.0
	var smooth := clampf(cutoff / float(RATE), 0.02, 0.9)
	for i in count:
		var t := float(i) / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, smooth)
		var envelope := pow(clampf(1.0 - t / duration, 0.0, 1.0), decay)
		data.encode_s16(i * 2, clampi(int(prev * envelope * volume * 32000.0), -32768, 32767))
	return _wav(data)


func _arpeggio(freqs: Array, note_duration: float, volume: float) -> AudioStreamWAV:
	var total := int(RATE * note_duration * freqs.size())
	var data := PackedByteArray()
	data.resize(total * 2)
	var index := 0
	for freq in freqs:
		var count := int(RATE * note_duration)
		for i in count:
			var t := float(i) / float(RATE)
			var s := sin(TAU * float(freq) * t) + 0.25 * sin(TAU * float(freq) * 2.0 * t)
			var envelope := pow(clampf(1.0 - t / note_duration, 0.0, 1.0), 1.2)
			if index * 2 + 1 < data.size():
				data.encode_s16(index * 2, clampi(int(s * envelope * volume * 32000.0), -32768, 32767))
			index += 1
	return _wav(data)


func _mix(streams: Array) -> AudioStreamWAV:
	var length := 0
	for stream in streams:
		length = maxi(length, stream.data.size())
	var out := PackedByteArray()
	out.resize(length)
	for stream in streams:
		var src: PackedByteArray = stream.data
		for i in range(0, src.size(), 2):
			if i + 1 < out.size():
				var sum := out.decode_s16(i) + src.decode_s16(i)
				out.encode_s16(i, clampi(sum, -32768, 32767))
	return _wav(out)


func _make_bgm() -> AudioStreamWAV:
	# 8 秒循环：C - Am - F - G 的简单琶音 + 低音，够当背景垫乐
	var duration := 8.0
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var chords := [
		[262.0, 330.0, 392.0, 523.0],
		[220.0, 262.0, 330.0, 440.0],
		[175.0, 220.0, 262.0, 349.0],
		[196.0, 247.0, 294.0, 392.0],
	]
	var bass := [131.0, 110.0, 87.0, 98.0]
	var beat := 0.25
	for i in count:
		var t := float(i) / float(RATE)
		var bar := int(t / 2.0) % 4
		var step := int(fmod(t, 2.0) / beat) % 4
		var note: float = chords[bar][step]
		var arp := sin(TAU * note * t) * 0.16 + sin(TAU * note * 2.0 * t) * 0.05
		var bass_note: float = bass[bar]
		var bass_wave := sin(TAU * bass_note * t) * 0.20
		var tremolo := 0.75 + 0.25 * sin(TAU * t / 2.0)
		var value := (arp + bass_wave) * tremolo
		data.encode_s16(i * 2, clampi(int(value * 32000.0), -32768, 32767))
	return _wav(data, true)
