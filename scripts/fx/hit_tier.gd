class_name HitTier
extends Resource
## 打击感的一档。策划 2026-11-27 定的五档阶梯（轻击 < 重击 < 弹反 < 受击 < Boss/剧情），
## 每档一组独立参数。核心约束：**普通轻击永远在最低档**——打击感需要动态范围，
## 普通攻击要是已经做满，后面所有东西都没地方往上走，打两分钟玩家就麻了（开发者原话大意）。

## 档位名，只用于检查器里辨认
@export var label: String = ""
## 命中定格（秒，全局冻结）。60 帧下 0.033 ≈ 2 帧
@export var hitstop: float = 0.04
## 镜头抖动强度（0..1）。镜头按强度平方换算位移，所以 0.1 以下几乎看不出
@export_range(0.0, 1.0) var camera_shake: float = 0.05
## 命中粒子（胞质飞溅）数量。0 = 不出粒子
@export var particle_amount: int = 5
## 粒子初速度（米/秒）
@export var particle_speed: float = 3.0
## 粒子存活时间（秒）
@export var particle_lifetime: float = 0.25
## 粒子直径（米）。镜头离交战点约 7–9 米，太小在 1080p 下只有一两个像素（2026-11-27 截图确认）
@export var particle_size: float = 0.1
## 膜口（命中处的环）回缩时长（秒）。0 = 不显示
@export var membrane_time: float = 0.15


static func make(p_label: String, p_hitstop: float, p_shake: float, p_amount: int,
        p_speed: float, p_lifetime: float, p_membrane: float, p_size: float = 0.1) -> HitTier:
    var t := HitTier.new()
    t.particle_size = p_size
    t.label = p_label
    t.hitstop = p_hitstop
    t.camera_shake = p_shake
    t.particle_amount = p_amount
    t.particle_speed = p_speed
    t.particle_lifetime = p_lifetime
    t.membrane_time = p_membrane
    return t
