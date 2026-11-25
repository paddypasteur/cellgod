extends Node
## 命中定格（hitstop）。
## 原型阶段直接冻结全局时间：实现最简单，效果最明显，便于先判断"有没有打击感"。
## 以后如果需要"只冻攻击者和受击者、其余照常"，再换成局部冻结。
##
## 时长由调用方决定（主角脚本里按蓄力程度插值，那边有 @export 可调）。

## 定格期间的时间流速。0 = 完全静止；稍大于 0 会有"慢动作"的味道
var frozen_time_scale: float = 0.0

var _end_usec: int = 0
var _active: bool = false


func _ready() -> void:
    # 时间被冻住时自己也必须继续跑，否则永远解不开
    process_mode = Node.PROCESS_MODE_ALWAYS


## 连续命中时取较晚的结束时间，而不是叠加，避免多段命中把画面冻得太久
func trigger(duration: float) -> void:
    if duration <= 0.0:
        return
    var end_usec: int = Time.get_ticks_usec() + int(duration * 1_000_000.0)
    _end_usec = maxi(_end_usec, end_usec)
    if not _active:
        _active = true
        Engine.time_scale = frozen_time_scale


func is_active() -> bool:
    return _active


func _process(_delta: float) -> void:
    # 用真实时间判断，因为冻结期间引擎给的 delta 是 0
    if _active and Time.get_ticks_usec() >= _end_usec:
        _active = false
        Engine.time_scale = 1.0
