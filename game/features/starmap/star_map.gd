extends Control
## 星系圖（GD §13-9.E）：星空軌道佈局・樞紐式選星（Hades 式，§6）。
## 母船居中、星球依軌道散佈；點選顯示相容性/危險/特產；達門檻才可登陸出航。
## 切片：登陸出航＝emit planet_selected（遠征切片未實作，僅回母船提示）。
## debug：[ / ] 調整相容性，即時看解鎖狀態變化。

const DEFAULT_COMPAT := 15        # 世界層無值時的起始相容性（P1 開・P2/P3 鎖）
const COMPAT_STEP := 10

var _planets: Array[PlanetData] = []
var _stars: Array[Vector2] = []          # 星空背景點（0..1 正規座標）
var _hover_id: StringName = &""
var _selected_id: StringName = &""
var _depart_btn: Button
var _back_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_planets()
	_make_stars()
	_build_buttons()
	queue_redraw()

func _load_planets() -> void:
	DataRegistry.load_category("planets")
	var table := DataRegistry.get_table("planets")
	for id in table:
		_planets.append(table[id])
	_planets.sort_custom(func(a, b): return a.order < b.order)

func _make_stars() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 20260614                     # 固定種子 → 星空穩定不閃爍
	for i in 140:
		_stars.append(Vector2(r.randf(), r.randf()))

func _compat() -> int:
	if not Save.world.has("compatibility"):
		Save.world["compatibility"] = DEFAULT_COMPAT
	return int(Save.world["compatibility"])

func _set_compat(v: int) -> void:
	Save.world["compatibility"] = maxi(0, v)
	Save.save_layer("world", Save.world)

func _is_unlocked(p: PlanetData) -> bool:
	return _compat() >= p.unlock_compat

func _center() -> Vector2:
	return get_viewport_rect().size * Vector2(0.40, 0.52)

func _planet_pos(p: PlanetData) -> Vector2:
	return _center() + Vector2.from_angle(deg_to_rad(p.orbit_angle_deg)) * p.orbit_radius

func _planet_at(point: Vector2) -> PlanetData:
	for p in _planets:
		if point.distance_to(_planet_pos(p)) <= p.display_radius + 6.0:
			return p
	return null

func _find(id: StringName) -> PlanetData:
	for p in _planets:
		if p.id == id:
			return p
	return null

# --- 按鈕 ---

func _build_buttons() -> void:
	var vp := get_viewport_rect().size
	_back_btn = Button.new()
	_back_btn.text = Localization.t("ui.common.back")
	_back_btn.position = Vector2(24, 24)
	_back_btn.pressed.connect(_close)
	add_child(_back_btn)

	_depart_btn = Button.new()
	_depart_btn.text = Localization.t("ui.starmap.depart")
	_depart_btn.size = Vector2(220, 44)
	_depart_btn.position = Vector2(vp.x - 244, vp.y - 64)
	_depart_btn.disabled = true
	_depart_btn.pressed.connect(_depart)
	add_child(_depart_btn)

func _refresh_depart() -> void:
	var p := _find(_selected_id)
	_depart_btn.disabled = p == null or not _is_unlocked(p)

# --- 輸入 ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p := _planet_at(event.position)
		var new_hover: StringName = p.id if p else &""
		if new_hover != _hover_id:
			_hover_id = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _planet_at(event.position)
		if p:
			_selected_id = p.id
			_refresh_depart()
			queue_redraw()
			accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_close()
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				_set_compat(_compat() - COMPAT_STEP)
				_refresh_depart()
				queue_redraw()
			KEY_BRACKETRIGHT:
				_set_compat(_compat() + COMPAT_STEP)
				_refresh_depart()
				queue_redraw()

func _depart() -> void:
	var p := _find(_selected_id)
	if p == null or not _is_unlocked(p):
		return
	# 先收掉星系圖＋解暫停（此時本節點仍在場景樹內），再 emit。
	# 順序很重要：base._on_planet_selected 會 change_scene_to_file，
	# 在 4.6 會「同步」拆掉當前場景（含本星系圖），若 emit 在前則 _close()
	# 取到的 get_tree() 會是 null → "paused on null instance" 崩潰。
	_close()
	EventBus.planet_selected.emit(p.id)

func _close() -> void:
	var tree := get_tree()
	if tree:                            # 場景切換已把本節點移出樹時，tree 為 null
		tree.paused = false
	get_parent().queue_free()           # 整個 StarMap 實例（CanvasLayer 根）

# --- 渲染 ---

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.04, 0.08, 0.96), true)
	for s in _stars:
		var pt := Vector2(s.x * vp.x, s.y * vp.y)
		draw_circle(pt, 1.0 + fmod(s.x * 7.0, 1.2), Color(1, 1, 1, 0.25 + fmod(s.y * 5.0, 0.5)))

	var font := ThemeDB.fallback_font
	var center := _center()

	# 軌道環
	for p in _planets:
		draw_arc(center, p.orbit_radius, 0, TAU, 96, Color(0.3, 0.4, 0.55, 0.20), 1.5, true)

	# 母船（中心）
	draw_circle(center, 16, Color(0.55, 0.75, 1.0))
	draw_circle(center, 16, Color(0.85, 0.95, 1.0))
	draw_string(font, center + Vector2(-28, 36), Localization.t("ui.starmap.mothership"),
		HORIZONTAL_ALIGNMENT_CENTER, 56, 14, Color(0.7, 0.85, 1.0))

	# 星球
	for p in _planets:
		var pos := _planet_pos(p)
		var unlocked := _is_unlocked(p)
		var col: Color = p.color if unlocked else p.color.darkened(0.6)
		# 連線（母船→星）
		draw_line(center, pos, Color(0.35, 0.45, 0.6, 0.25 if unlocked else 0.12), 1.5)
		draw_circle(pos, p.display_radius, col)
		# 選中/hover 外框
		if p.id == _selected_id:
			draw_arc(pos, p.display_radius + 6, 0, TAU, 48, Color(0.4, 1.0, 0.6), 3.0, true)
		elif p.id == _hover_id:
			draw_arc(pos, p.display_radius + 5, 0, TAU, 48, Color(1, 1, 1, 0.7), 2.0, true)
		# 鎖
		if not unlocked:
			draw_string(font, pos + Vector2(-7, 6), "🔒", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		# 星名
		draw_string(font, pos + Vector2(-60, p.display_radius + 22),
			Localization.t(p.name_key), HORIZONTAL_ALIGNMENT_CENTER, 120, 15,
			Color.WHITE if unlocked else Color(0.6, 0.6, 0.65))

	_draw_topbar(font, vp)
	_draw_info_panel(font, vp)

func _draw_topbar(font: Font, vp: Vector2) -> void:
	draw_string(font, Vector2(24, 90), Localization.t("ui.starmap.title"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.85, 0.92, 1.0))
	var c := _compat()
	draw_string(font, Vector2(24, 122),
		"%s：%d" % [Localization.t("ui.starmap.compat"), c],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.85, 1.0))
	draw_string(font, Vector2(24, 146), "[ / ] debug ±%d" % COMPAT_STEP,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.55, 0.62))

func _draw_info_panel(font: Font, vp: Vector2) -> void:
	var p := _find(_hover_id)
	if p == null:
		p = _find(_selected_id)
	var x := vp.x - 360.0
	var y := 96.0
	var w := 320.0
	var h := vp.y - 200.0
	draw_rect(Rect2(x, y, w, h), Color(0.06, 0.09, 0.14, 0.92), true)
	draw_rect(Rect2(x, y, w, h), Color(0.3, 0.4, 0.55, 0.5), false, 1.5)
	if p == null:
		draw_string(font, Vector2(x + 20, y + 40), Localization.t("ui.starmap.select_planet"),
			HORIZONTAL_ALIGNMENT_LEFT, w - 40, 16, Color(0.6, 0.65, 0.72))
		return

	var unlocked := _is_unlocked(p)
	var tx := x + 20.0
	var ty := y + 44.0
	var line := 30.0
	draw_string(font, Vector2(tx, ty), Localization.t(p.name_key),
		HORIZONTAL_ALIGNMENT_LEFT, w - 40, 22, p.color)
	ty += line + 6

	if not unlocked:
		var gap := p.unlock_compat - _compat()
		draw_string(font, Vector2(tx, ty),
			"🔒 " + Localization.t("ui.starmap.need_compat") % [p.unlock_compat, gap],
			HORIZONTAL_ALIGNMENT_LEFT, w - 40, 16, Color(1.0, 0.55, 0.5))
		ty += line

	_info_line(font, tx, ty, w, Localization.t("ui.starmap.biome"), Localization.t(p.biome_key)); ty += line
	_info_line(font, tx, ty, w, Localization.t("ui.starmap.danger"),
		"%s  (Lv%d)" % [Localization.t(p.danger_key), p.danger_level]); ty += line
	_info_line(font, tx, ty, w, Localization.t("ui.starmap.layers"), str(p.region_layers)); ty += line
	_info_line(font, tx, ty, w, Localization.t("ui.starmap.anomaly_zone"),
		Localization.t("ui.starmap.has_anomaly") if p.has_anomaly else Localization.t("ui.starmap.no_anomaly")); ty += line + 6

	draw_string(font, Vector2(tx, ty), Localization.t("ui.starmap.specialty"),
		HORIZONTAL_ALIGNMENT_LEFT, w - 40, 16, Color(0.7, 0.78, 0.85)); ty += line - 6
	for key in p.specialty_keys:
		draw_string(font, Vector2(tx + 12, ty), "• " + Localization.t(key),
			HORIZONTAL_ALIGNMENT_LEFT, w - 52, 15, Color(0.9, 0.85, 0.55)); ty += line - 4

func _info_line(font: Font, x: float, y: float, w: float, label: String, value: String) -> void:
	draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, 120, 15, Color(0.6, 0.68, 0.78))
	draw_string(font, Vector2(x + 96, y), value, HORIZONTAL_ALIGNMENT_LEFT, w - 116, 15, Color(0.92, 0.94, 0.98))
