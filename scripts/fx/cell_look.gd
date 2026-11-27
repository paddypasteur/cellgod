class_name CellLook
extends Resource
## 一种细胞的观感参数：半透明膜（共用 cell_membrane 着色器）+ 里面的实核。
## 主角和敌人各用一份，用配色和膜的质感分族（DESIGN：免疫族 vs 细菌族要一眼分得开）。
## 全部是材质参数，没有贴图、没有建模，仍然是白盒。

const MEMBRANE_SHADER: Shader = preload("res://shaders/cell_membrane.gdshader")

@export_group("膜")
@export var membrane_color: Color = Color(0.55, 0.85, 0.8)
## 膜的不透明度。太高看不见核，太低和背景糊在一起
@export_range(0.0, 1.0) var membrane_alpha: float = 0.4
@export var rim_color: Color = Color(0.85, 1.0, 1.0)
@export_range(0.0, 6.0) var rim_strength: float = 2.0
## 边缘线宽（屏幕像素）。按像素定宽，掠射角下不会铺满整个表面
@export_range(0.5, 12.0) var rim_pixels: float = 2.5
## 边缘带的上限（菲涅尔值），防止远处的小物体整个被描满
@export_range(0.01, 1.0) var rim_max_band: float = 0.3
## 膜流动的速度 / 起伏幅度（米）/ 疏密。细菌族更快更碎，模拟粗糙带毛的表面
@export var flow_speed: float = 0.6
@export var flow_amplitude: float = 0.03
@export var flow_scale: float = 3.0

@export_group("核")
@export var core_color: Color = Color(0.2, 0.2, 0.55)
## 核的大小（相对膜的尺寸）
@export_range(0.05, 0.95) var core_scale: float = 0.42
## 核偏离中心多少（相对膜的尺寸）。真实细胞的核不在正中，偏一点更像活的
@export var core_offset: Vector3 = Vector3(0.08, 0.05, 0.0)


func make_membrane_material() -> ShaderMaterial:
    var m := ShaderMaterial.new()
    m.shader = MEMBRANE_SHADER
    m.set_shader_parameter(&"base_color", membrane_color)
    m.set_shader_parameter(&"body_alpha", membrane_alpha)
    m.set_shader_parameter(&"rim_color", rim_color)
    m.set_shader_parameter(&"rim_strength", rim_strength)
    m.set_shader_parameter(&"rim_pixels", rim_pixels)
    m.set_shader_parameter(&"rim_max_band", rim_max_band)
    m.set_shader_parameter(&"flow_speed", flow_speed)
    m.set_shader_parameter(&"flow_amplitude", flow_amplitude)
    m.set_shader_parameter(&"flow_scale", flow_scale)
    m.set_shader_parameter(&"hardness", 0.0)
    return m


func make_core_material() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = core_color
    m.roughness = 0.4
    return m


## 免疫族（主角）：冷色，淡青膜、深蓝紫核、近白的青色边缘
static func immune_default() -> CellLook:
    return CellLook.new()


## 细菌族（敌人）：暖色、带病态感，橄榄黄绿膜、暗红褐核、黄色边缘；膜起伏更快更碎
static func bacteria_default() -> CellLook:
    var l := CellLook.new()
    l.membrane_color = Color(0.55, 0.62, 0.22)
    l.membrane_alpha = 0.5
    # 普通敌人的描边要低调：所有敌人都顶着醒目的黄边等于没有重点。
    # 被准星选中 / 被锁定时由 Enemy 调亮、换色（三档）
    l.rim_color = Color(0.85, 0.75, 0.35)
    l.rim_strength = 0.9
    l.rim_pixels = 1.8
    l.flow_speed = 1.4
    l.flow_amplitude = 0.04
    l.flow_scale = 7.0
    l.core_color = Color(0.4, 0.12, 0.08)
    l.core_scale = 0.5
    l.core_offset = Vector3.ZERO
    return l
