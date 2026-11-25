extends Node
## 原型占位音效：全部用代码合成，不引入音频文件（白盒阶段不加素材）。
## 音效算手感不算美术，所以现在就要有；但只求"能响、能分辨"，不求好听。
## 四个音：swing 挥击、hit 命中、windup 敌人起手（3D 定位）、hurt 玩家受击。

const MIX_RATE: int = 22050
const POOL_SIZE: int = 6

## 各音效音量（分贝）
var volumes: Dictionary = {
    &"swing": -8.0,
    &"hit": -2.0,
    &"windup": -4.0,
    &"hurt": -3.0,
}

var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0


func _ready() -> void:
    _streams[&"swing"] = _to_wav(_synth_swing())
    _streams[&"hit"] = _to_wav(_synth_hit())
    _streams[&"windup"] = _to_wav(_synth_windup())
    _streams[&"hurt"] = _to_wav(_synth_hurt())
    for i: int in POOL_SIZE:
        var p2 := AudioStreamPlayer.new()
        add_child(p2)
        _players_2d.append(p2)
        var p3 := AudioStreamPlayer3D.new()
        # 竞技场半径 20，单位距离设大一些，远处的敌人起手也听得见，只是更轻
        p3.unit_size = 8.0
        add_child(p3)
        _players_3d.append(p3)


## 不带位置的音效（玩家自己的动作）。pitch 用来区分轻重：重击更低沉
func play(sound: StringName, pitch: float = 1.0) -> void:
    var stream: AudioStreamWAV = _streams.get(sound)
    if stream == null:
        return
    var p: AudioStreamPlayer = _players_2d[_next_2d]
    _next_2d = (_next_2d + 1) % POOL_SIZE
    p.stream = stream
    p.pitch_scale = maxf(pitch, 0.05)
    p.volume_db = volumes.get(sound, 0.0)
    p.play()


## 带位置的音效。fit_duration > 0 时改变播放速度，让声音正好在这么多秒后结束
## （敌人起手音结束的那一刻就是它冲出来的那一刻）
func play_at(sound: StringName, world_position: Vector3, fit_duration: float = 0.0) -> void:
    var stream: AudioStreamWAV = _streams.get(sound)
    if stream == null:
        return
    var p: AudioStreamPlayer3D = _players_3d[_next_3d]
    _next_3d = (_next_3d + 1) % POOL_SIZE
    p.stream = stream
    p.global_position = world_position
    p.pitch_scale = stream.get_length() / fit_duration if fit_duration > 0.0 else 1.0
    p.volume_db = volumes.get(sound, 0.0)
    p.play()


# ---------------------------------------------------------------- 合成

## 呼的一声：噪声经过越来越低的低通，模拟甩过空气
func _synth_swing() -> PackedFloat32Array:
    var n: int = int(0.18 * MIX_RATE)
    var out := PackedFloat32Array()
    out.resize(n)
    var lp: float = 0.0
    for i: int in n:
        var t: float = float(i) / n
        lp += lerpf(0.5, 0.05, t) * (randf_range(-1.0, 1.0) - lp)
        var env: float = minf(t / 0.1, 1.0) * (1.0 - t)
        out[i] = lp * env * 2.5
    return out


## 闷响：快速下滑的低频正弦 + 开头一点噪声做"咔"
func _synth_hit() -> PackedFloat32Array:
    var n: int = int(0.16 * MIX_RATE)
    var out := PackedFloat32Array()
    out.resize(n)
    var phase: float = 0.0
    for i: int in n:
        var t: float = float(i) / n
        phase += TAU * (45.0 + 115.0 * exp(-t * 6.0)) / MIX_RATE
        var s: float = sin(phase) * exp(-t * 5.0)
        if float(i) / MIX_RATE < 0.008:
            s += randf_range(-1.0, 1.0) * 0.6
        out[i] = s
    return out


## 上升的嗡声：越来越尖、越来越响，听着像"要来了"
func _synth_windup() -> PackedFloat32Array:
    var n: int = int(0.6 * MIX_RATE)
    var out := PackedFloat32Array()
    out.resize(n)
    var phase: float = 0.0
    for i: int in n:
        var t: float = float(i) / n
        phase += TAU * lerpf(220.0, 660.0, t * t) / MIX_RATE
        var tone: float = sin(phase) * 0.6 + signf(sin(phase)) * 0.25
        var env: float = minf(t / 0.05, 1.0) * (0.35 + 0.65 * t) * minf((1.0 - t) / 0.03, 1.0)
        out[i] = tone * env
    return out


## 低沉的嗡+噪声：和挥击、命中都区分得开
func _synth_hurt() -> PackedFloat32Array:
    var n: int = int(0.22 * MIX_RATE)
    var out := PackedFloat32Array()
    out.resize(n)
    var phase: float = 0.0
    for i: int in n:
        var t: float = float(i) / n
        phase += TAU * (110.0 - 40.0 * t) / MIX_RATE
        out[i] = (signf(sin(phase)) * 0.5 + randf_range(-1.0, 1.0) * 0.3) * exp(-t * 4.0)
    return out


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
    var data := PackedByteArray()
    data.resize(samples.size() * 2)
    for i: int in samples.size():
        data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = MIX_RATE
    wav.stereo = false
    wav.data = data
    return wav
