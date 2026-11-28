class_name ImpactConfig
extends Resource
## 冲击系统的基准（DESIGN《冲击系统》，2026-11-28）。
## 开发者："后面不同的招式带来的后坐、粒子、细菌的反应幅度都可能有变化……后面只需要改它强度就好了。"
## 每一档打击（HitTier）只填一个主强度 impact，所有通道都从它算出来：
##     通道的值 = 基准 × impact ^ 指数 × 该档自己的通道倍率（默认 1）
## 轻击 impact = 1 —— 下面的"基准"就是普通轻击的值；指数决定越往上的档这一项长得多快。
## 指数是用 2026-11-27 定下的轻击 / 重击两档实际值反推的（重击 impact = 2.5），所以换系统前后手感不变；
## 后坐和击退按 11-28 开发者"太小"整体上调了 1.5 倍（改的是基准，所以所有档一起变）

@export_group("定格")
## 秒。轻击 0.04 ≈ 2–3 帧
@export var hitstop_base: float = 0.04
@export var hitstop_exp: float = 1.2

@export_group("镜头抖")
## 强度 0..1（镜头按平方换算位移）
@export var shake_base: float = 0.06
@export var shake_exp: float = 1.76

@export_group("后坐（打中时自己被推回去，米/秒）")
@export var recoil_base: float = 3.0
@export var recoil_exp: float = 1.0

@export_group("击退（敌人被推开，米/秒）")
@export var knockback_base: float = 4.5
@export var knockback_exp: float = 1.3

@export_group("受击形变（敌人弯腰的幅度，倍率）")
@export var wobble_base: float = 0.6
@export var wobble_exp: float = 0.55

@export_group("命中粒子")
## 数量、初速（米/秒）、直径（米）、存活（秒，含减速、漂浮、淡出）
@export var particle_count_base: float = 10.0
@export var particle_count_exp: float = 1.0
@export var particle_speed_base: float = 7.0
@export var particle_speed_exp: float = 0.5
@export var particle_size_base: float = 0.14
@export var particle_size_exp: float = 0.3
@export var particle_life_base: float = 1.4
@export var particle_life_exp: float = 0.3

static var _default: ImpactConfig = null


## 没在检查器里指定时用的那一份（所有档共享）
static func get_default() -> ImpactConfig:
    if _default == null:
        _default = ImpactConfig.new()
    return _default


static func curve(base: float, impact: float, exponent: float) -> float:
    return base * pow(maxf(impact, 0.0), exponent)
