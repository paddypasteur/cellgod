class_name HitTier
extends Resource
## 打击感的一档。策划 2026-11-27 定的五档阶梯（轻击 < 重击 < 弹反 < 受击 < Boss/剧情）。
## 核心约束：**普通轻击永远在最低档**——打击感需要动态范围，普通攻击要是已经做满，后面所有东西都没地方往上走。
##
## 2026-11-28 起是"冲击系统"（DESIGN《冲击系统》）：每档只填一个主强度 impact，
## 定格、镜头抖、后坐、击退、敌人形变、命中粒子全部由它按 ImpactConfig 的曲线算出来。
## 加新招式 = 建一档 + 填一个数。某一项想单独偏一点（比如定格久但不想击退远），改该项的倍率

## 档位名，只用于检查器里辨认
@export var label: String = ""
## 主强度。普通轻击 = 1，重击 = 2.5
@export_range(0.0, 10.0) var impact: float = 1.0

@export_group("单项倍率（默认 1，只在想让某一项偏离主强度时改）")
@export var hitstop_mult: float = 1.0
@export var shake_mult: float = 1.0
@export var recoil_mult: float = 1.0
@export var knockback_mult: float = 1.0
@export var wobble_mult: float = 1.0
@export var particle_mult: float = 1.0

## 用哪份基准。为空时用全局默认那份
@export var config: ImpactConfig


func _cfg() -> ImpactConfig:
    return config if config != null else ImpactConfig.get_default()


## 命中定格（秒）
func get_hitstop() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.hitstop_base, impact, c.hitstop_exp) * hitstop_mult


## 镜头抖（0..1）
func get_shake() -> float:
    var c := _cfg()
    return clampf(ImpactConfig.curve(c.shake_base, impact, c.shake_exp) * shake_mult, 0.0, 1.0)


## 后坐（米/秒）
func get_recoil() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.recoil_base, impact, c.recoil_exp) * recoil_mult


## 击退（米/秒）
func get_knockback() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.knockback_base, impact, c.knockback_exp) * knockback_mult


## 受击形变倍率（乘到 HitWobble 的弯曲和凹陷上）
func get_wobble() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.wobble_base, impact, c.wobble_exp) * wobble_mult


func get_particle_count() -> int:
    var c := _cfg()
    return roundi(ImpactConfig.curve(c.particle_count_base, impact, c.particle_count_exp) * particle_mult)


func get_particle_speed() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.particle_speed_base, impact, c.particle_speed_exp)


func get_particle_size() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.particle_size_base, impact, c.particle_size_exp)


func get_particle_life() -> float:
    var c := _cfg()
    return ImpactConfig.curve(c.particle_life_base, impact, c.particle_life_exp)


static func make(p_label: String, p_impact: float) -> HitTier:
    var t := HitTier.new()
    t.label = p_label
    t.impact = p_impact
    return t
