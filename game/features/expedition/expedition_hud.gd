extends Control
## 遠征 HUD（GD §13-9.F・角色集中式動作佈局）：
## 氧氣顯眼置頂 ＋ 低氧變紅；左下 HP/PSI 條；底部異能槽＋冷卻；右下背包/撤離倉。
## 純表現層：讀 expedition 狀態繪製，不持有遊戲邏輯。

var exp: Node                          # Expedition 節點（讀狀態）

const SLOT := 64.0
const SLOT_GAP := 12.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _bar(pos: Vector2, sz: Vector2, ratio: float, fill: Color, label: String) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(pos, sz), Color(0.12, 0.13, 0.16), true)
	draw_rect(Rect2(pos, Vector2(sz.x * clampf(ratio, 0.0, 1.0), sz.y)), fill, true)
	draw_rect(Rect2(pos, sz), Color(0, 0, 0, 0.5), false, 1.0)
	draw_string(font, pos + Vector2(8, sz.y - 5), label, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 12, 13, Color.WHITE)

func _draw() -> void:
	if exp == null:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size   # 用視窗實際大小（CanvasLayer 下 Control 的 size 可能為 0）

	# 標題 ＋ 層次
	if exp._planet:
		draw_string(font, Vector2(24, 26), "%s — %s" % [
			Localization.t("ui.exp.region"), Localization.t(exp._planet.name_key)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.88, 0.95))
	draw_string(font, Vector2(vp.x - 150, 26), "%s %d / %d" % [
		Localization.t("ui.exp.layer"), exp._layer, exp._max_layer],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.7, 1.0))

	# 氧氣（顯眼置頂置中・§7.4 核心張力）
	var oxy_w := 440.0
	var oxy_x := (vp.x - oxy_w) * 0.5
	var oratio: float = exp._oxygen / exp._oxy_max
	var ocol := Color(1.0, 0.35, 0.35) if oratio < 0.28 else Color(0.4, 0.85, 1.0)
	_bar(Vector2(oxy_x, 22), Vector2(oxy_w, 26), oratio, ocol, "")
	draw_string(font, Vector2(oxy_x, 42), "%s   %d s" % [Localization.t("ui.exp.oxygen"), int(exp._oxygen)],
		HORIZONTAL_ALIGNMENT_CENTER, oxy_w, 16, Color.WHITE)

	# 左下：HP / PSI（§13-9.F）
	var ch: CharacterState = exp._char
	_bar(Vector2(28, vp.y - 88), Vector2(240, 20), float(ch.hp) / float(ch.hp_max),
		Color(0.85, 0.30, 0.32), "%s  %d / %d" % [Localization.t("ui.exp.hp"), ch.hp, ch.hp_max])
	_bar(Vector2(28, vp.y - 60), Vector2(240, 20), ch.psi / ch.psi_max,
		Color(0.40, 0.55, 0.95), "%s  %d / %d" % [Localization.t("ui.exp.psi"), int(ch.psi), int(ch.psi_max)])

	# 底部置中：當前武器 ＋ 主動異能（Q）
	var box := 72.0
	var bgap := 20.0
	var bx0 := (vp.x - (box * 2 + bgap)) * 0.5
	var by := vp.y - 104.0
	# 武器框（滾輪/1·2 切換）
	draw_rect(Rect2(bx0, by, box, box), Color(0.14, 0.16, 0.20), true)
	draw_rect(Rect2(bx0, by, box, box), Color(0.7, 0.8, 0.95), false, 2.0)
	draw_string(font, Vector2(bx0 + 5, by + 15), Localization.t("ui.exp.weapon"),
		HORIZONTAL_ALIGNMENT_LEFT, box - 8, 11, Color(0.75, 0.82, 0.95))
	if not exp._weapons.is_empty():
		var w: WeaponData = exp._weapons[exp._weapon_idx]
		draw_string(font, Vector2(bx0, by + box * 0.5 + 8), Localization.t(w.name_key),
			HORIZONTAL_ALIGNMENT_CENTER, box, 13, w.color)
	draw_string(font, Vector2(bx0, by + box + 13), Localization.t("ui.exp.weap_keys"),
		HORIZONTAL_ALIGNMENT_CENTER, box, 11, Color(0.6, 0.65, 0.72))
	# 異能框（Q 施放・Tab 換）
	var ax := bx0 + box + bgap
	var a: Dictionary = ch.abilities[exp._ability_active]
	var ready: bool = a.cd_left <= 0.0 and ch.psi >= float(a.cost)
	draw_rect(Rect2(ax, by, box, box), Color(0.14, 0.16, 0.20) if ready else Color(0.10, 0.10, 0.12), true)
	draw_rect(Rect2(ax, by, box, box), Color(0.5, 0.7, 0.9) if ready else Color(0.3, 0.3, 0.35), false, 2.0)
	if a.cd_left > 0.0:
		var frac: float = a.cd_left / float(a.cd)
		draw_rect(Rect2(ax, by, box, box * frac), Color(0, 0, 0, 0.6), true)
		draw_string(font, Vector2(ax, by + box * 0.5 + 8), "%.1f" % a.cd_left,
			HORIZONTAL_ALIGNMENT_CENTER, box, 18, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(ax + 5, by + 15), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 0.7))
	draw_string(font, Vector2(ax, by + box - 6), "PSI %d" % int(a.cost),
		HORIZONTAL_ALIGNMENT_CENTER, box, 10, Color(0.7, 0.78, 0.95))
	draw_string(font, Vector2(ax, by + box + 13), Localization.t(a.name_key),
		HORIZONTAL_ALIGNMENT_CENTER, box, 11, Color.WHITE if ready else Color(0.6, 0.6, 0.65))

	# 右下：背包 / 撤離倉（§13-2.D）
	var rx := vp.x - 320.0
	draw_string(font, Vector2(rx, vp.y - 72), "%s  %d / %d  %s" % [Localization.t("ui.exp.backpack"),
		exp._backpack.weight(), exp._backpack.cap, exp._inv_brief(exp._backpack)],
		HORIZONTAL_ALIGNMENT_LEFT, 300, 14, Color(0.9, 0.92, 0.98))
	draw_string(font, Vector2(rx, vp.y - 50), "%s  %d / %d  %s" % [Localization.t("ui.exp.pod"),
		exp._pod.weight(), exp._pod.cap, exp._inv_brief(exp._pod)],
		HORIZONTAL_ALIGNMENT_LEFT, 300, 14, Color(0.8, 0.95, 0.85))

	# 撤離點 / 下行點 動作提示
	if exp._on_pad() and exp._state == 0:
		draw_string(font, Vector2(0, vp.y - 120), "[E] %s    [F] %s" % [
			Localization.t("ui.exp.load"), Localization.t("ui.exp.extract")],
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, Color(0.5, 1.0, 0.6))
	elif exp._near_descent() and exp._state == 0:
		draw_string(font, Vector2(0, vp.y - 120), "[G] %s" % Localization.t("ui.exp.descend"),
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, Color(0.85, 0.7, 1.0))

	# 操作提示（置頂・避免與底部狀態列重疊）
	draw_string(font, Vector2(24, 54), Localization.t("ui.exp.hint"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.72))

	# 異能輪盤（按住 Tab・滾輪切選）
	if exp._wheel_open:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.45), true)
		var wc := vp * 0.5
		var rad := 120.0
		var na := ch.abilities.size()
		for i in na:
			var ang := -PI / 2.0 + TAU * float(i) / float(na)
			var pc := wc + Vector2.from_angle(ang) * rad
			var seld: bool = i == exp._ability_sel
			var rr := 44.0 if seld else 34.0
			draw_circle(pc, rr, Color(0.2, 0.45, 0.3) if seld else Color(0.15, 0.16, 0.2))
			draw_arc(pc, rr, 0, TAU, 32, Color(0.5, 1.0, 0.7) if seld else Color(0.4, 0.5, 0.6), 2.0, true)
			draw_string(font, pc + Vector2(-44, 5), Localization.t(ch.abilities[i].name_key),
				HORIZONTAL_ALIGNMENT_CENTER, 88, 13, Color.WHITE)
		draw_string(font, Vector2(0, wc.y + rad + 64), Localization.t("ui.exp.wheel_hint"),
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, Color(0.82, 0.88, 0.95))

	# 閃示
	if exp._flash_t > 0.0:
		draw_string(font, Vector2(0, vp.y * 0.38), exp._flash_text,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, Color(1, 0.9, 0.5))

	# 結算橫幅
	if exp._banner_on:
		draw_string(font, Vector2(0, vp.y * 0.5), exp._banner_text,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 40, exp._banner_col)
