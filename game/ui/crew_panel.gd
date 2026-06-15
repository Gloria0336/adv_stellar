class_name CrewPanel
extends PanelContainer
## 船員個性面板（表現層）。顯示身份/個性/口頭禪 ＋ 6 狀態軸 ＋ 目前情緒/活動。
## 純顯示，讀 CrewMember；不寫狀態。文字一律 tr()。
## 注意：_draw 在 headless 不跑，視覺需 F5 看（見 godot-validation-workflow）。

const AXES := [
	[&"energy", "crew.axis.energy", Color(0.4, 0.8, 0.4)],
	[&"satiation", "crew.axis.satiation", Color(0.9, 0.7, 0.3)],
	[&"social", "crew.axis.social", Color(0.4, 0.7, 0.95)],
	[&"morale", "crew.axis.morale", Color(0.85, 0.5, 0.9)],
	[&"fear", "crew.axis.fear", Color(0.9, 0.35, 0.35)],
	[&"health", "crew.axis.health", Color(0.95, 0.45, 0.5)],
]

var _crew: CrewMember
var _swatch: ColorRect
var _name_lbl: Label
var _prof_lbl: Label
var _bio_lbl: Label
var _phrase_lbl: Label
var _mood_lbl: Label
var _activity_lbl: Label
var _bars: Dictionary = {}   # field(StringName) -> ProgressBar

func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 頭部：色塊 + 姓名 + 職業
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(44, 44)
	head.add_child(_swatch)
	var name_box := VBoxContainer.new()
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 18)
	_prof_lbl = Label.new()
	_prof_lbl.modulate = Color(0.7, 0.7, 0.7)
	name_box.add_child(_name_lbl)
	name_box.add_child(_prof_lbl)
	head.add_child(name_box)
	root.add_child(head)

	# 個性簡介 + 口頭禪
	_bio_lbl = Label.new()
	_bio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phrase_lbl = Label.new()
	_phrase_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phrase_lbl.modulate = Color(0.8, 0.8, 0.55)
	root.add_child(_bio_lbl)
	root.add_child(_phrase_lbl)

	root.add_child(HSeparator.new())

	# 目前情緒/活動
	_mood_lbl = Label.new()
	_mood_lbl.add_theme_font_size_override("font_size", 16)
	_activity_lbl = Label.new()
	_activity_lbl.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(_mood_lbl)
	root.add_child(_activity_lbl)

	# 6 軸 bar
	for axis in AXES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = tr(axis[1])
		lbl.custom_minimum_size = Vector2(64, 0)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(180, 16)
		bar.min_value = 0
		bar.max_value = 100
		bar.show_percentage = false
		bar.add_theme_color_override("font_color", axis[2])
		row.add_child(lbl)
		row.add_child(bar)
		root.add_child(row)
		_bars[axis[0]] = bar

## 目前綁定的船員（base 判斷是否切換/關閉用）。
func get_bound() -> CrewMember:
	return _crew

## 綁定要顯示的船員。
func bind(crew: CrewMember) -> void:
	_crew = crew
	if crew == null or crew.data == null:
		return
	var d := crew.data
	_name_lbl.text = tr(d.name_key)
	_prof_lbl.text = tr(StringName("crew.profession." + String(d.profession)))
	_bio_lbl.text = tr(d.bio_key)
	_phrase_lbl.text = "「" + tr(d.catchphrase_key) + "」"
	_swatch.color = d.portrait_color

func _process(_delta: float) -> void:
	if _crew == null:
		return
	for field: StringName in _bars:
		(_bars[field] as ProgressBar).value = _crew.needs.get(field)
	_mood_lbl.text = CrewMood.emoji(_crew.mood) + "  " + tr(CrewMood.loc_key(_crew.mood))
	_activity_lbl.text = tr(&"crew.panel.activity") + tr(StringName("crew.activity." + String(_crew.fsm.current)))
