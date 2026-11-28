extends Node
## 白盒期背景音乐（策划 2026-11-28 自合成的占位曲 audio/body_theme_loop.ogg，版权干净）。
## 目的只有一个：让空场不那么死，给战斗一个脉搏。最终配乐由开发者本人来做，不在它上面做任何系统。
## 放在 autoload：波次测试台重开一局会重新加载场景，音乐不该跟着从头开始；暂停（结果画面）时也继续放

const MUSIC: AudioStream = preload("res://audio/body_theme_loop.ogg")
const BUS_NAME: StringName = &"Music"

## 音乐总线的音量（分贝）。默认偏小，垫在底下，不抢命中音效。音效走 Master，不受这个影响
@export var volume_db: float = -14.0:
    set(value):
        volume_db = value
        _apply_volume()
## 是否播放（调试时可以关掉）
@export var enabled: bool = true

var _player: AudioStreamPlayer


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # 单独的总线：音乐的音量和音效分开调
    if AudioServer.get_bus_index(BUS_NAME) < 0:
        AudioServer.add_bus()
        var idx: int = AudioServer.bus_count - 1
        AudioServer.set_bus_name(idx, BUS_NAME)
        AudioServer.set_bus_send(idx, &"Master")
    _apply_volume()
    if not enabled or DisplayServer.get_name() == "headless":
        return
    _player = AudioStreamPlayer.new()
    # 无缝循环靠音频本身（102.4 秒正好 32 小节）+ 导入时打开 Loop，不用淡入淡出接
    var stream: AudioStream = MUSIC
    if stream is AudioStreamOggVorbis:
        (stream as AudioStreamOggVorbis).loop = true
    _player.stream = stream
    _player.bus = BUS_NAME
    add_child(_player)
    _player.play()


func _apply_volume() -> void:
    var idx: int = AudioServer.get_bus_index(BUS_NAME)
    if idx >= 0:
        AudioServer.set_bus_volume_db(idx, volume_db)
