class_name DeckLayout
extends RefCounted
## 七層母艦俯視布局（手建自 Drawing2.dxf・GD §5.1）。單層俯視＋電梯切換呈現用。
## 由上(船首)而下(船尾)垂直堆疊七層；每層一張俯視平面圖，水滴形紡錘（刻意左右不對稱：
## 船首尖、船尾鈍、中段滿寬）。字元編碼（每格一字）：
##   c / m / o ＝ 核心區 / 中間區 / 外圍區（可建造）          ← 三地形區（§5.2 地形判定）
##   C / M / O ＝ 同上三區、但屬「起始固定模塊」（不可編輯・預佔）  ← Drawing2 斜線填充 ANSI31
##   X         ＝ 垂直動線 / 電梯（不可編輯・可走・跨層通道）        ← Drawing2 網格填充 ANSI37
##   .         ＝ 無格（艙外）
## 行序＝由上而下（map[0] 為該層最上一列）。各層寬高不同（紡錘）。

const DECKS := [
	{
		"type": &"hull", "name": "外殼層", "note": "船首・最尖",
		"map": [
			"mmmm",
			"mccm",
			"mccm",
			"mccm",
			"mXXm",
			"mccm",
			"mccm",
			"mccm",
			"mccm",
			"mccm",
			"mccm",
			"mccm",
			"mmmm",
		],
	},
	{
		"type": &"equipment", "name": "設備層", "note": "船首段",
		"map": [
			".oooo.",
			"ommmmo",
			"omccmo",
			"omccmo",
			"omXXXo",
			"omccmo",
			"omccmo",
			"omccmo",
			"omccmo",
			"omXXmo",
			"oMCCMO",
			"oMMMMO",
			".OOOO.",
			"..OO..",
		],
	},
	{
		"type": &"habitation", "name": "居住層", "note": "船首段",
		"map": [
			"...OO...",
			"..oooo..",
			".ommmmo.",
			"oomccmoo",
			"oomccmoo",
			"oomXXmoo",
			"oOMCcmoo",
			"oOMCcmoo",
			"oOMCcmoo",
			"oOMCcmoo",
			"ooXXcmoo",
			"oOMCCMoo",
			"oOMMMMoo",
			"..OOOO..",
			"...OO...",
		],
	},
	{
		"type": &"core", "name": "核心層", "note": "中央・最大",
		"map": [
			"...OO...",
			"..oOOO..",
			".ommmmo.",
			"oomCCMoo",
			"oomCCMoo",
			"oomcXXoo",
			"oomccmoo",
			"oomcCMOo",
			"oomcCMOo",
			"oomccmoo",
			"oomXXmoo",
			"ooMCCMOo",
			"ooMMMMOo",
			"..OOOO..",
			"...OO...",
		],
	},
	{
		"type": &"habitation", "name": "居住層", "note": "船尾段",
		"map": [
			"...OO...",
			"..oOOO..",
			".ommmmo.",
			"oomccmoo",
			"oomccmoo",
			"oomcXXoo",
			"oomccmoo",
			"oomcCMoo",
			"oomccmoo",
			"oomccmoo",
			"oomXXmoo",
			"oomccmoo",
			"oommmmoo",
			"..oooo..",
			"...OO...",
		],
	},
	{
		"type": &"equipment", "name": "設備層", "note": "船尾段",
		"map": [
			"...OO...",
			"..oooo..",
			".ommmmo.",
			"oomccmoo",
			"oomccmoo",
			"oomXXmoo",
			"oomccmoo",
			"oomccmoo",
			"oomccmoo",
			"oomccmoo",
			"ooXXcmoo",
			"oomccmoo",
			"oommmmoo",
			"..oooo..",
			"...OO...",
		],
	},
	{
		"type": &"hull", "name": "外殼層", "note": "船尾・較鈍",
		"map": [
			".oooo.",
			"ommmmo",
			"omccmo",
			"omccmo",
			"omcXmo",
			"omccmo",
			"omccmo",
			"omccmo",
			"omccmo",
			"omXcmo",
			"omccmo",
			"ommmmo",
			".oooo.",
			"..OO..",
		],
	},
]

const TYPE_NAMES := {
	&"hull": "外殼層", &"equipment": "設備層", &"habitation": "居住層", &"core": "核心層",
}

static func deck_count() -> int:
	return DECKS.size()

static func deck_map(d: int) -> Array:
	return DECKS[d]["map"]

static func deck_rows(d: int) -> int:
	return (DECKS[d]["map"] as Array).size()

static func deck_cols(d: int) -> int:
	var w := 0
	for row in DECKS[d]["map"]:
		w = maxi(w, (row as String).length())
	return w

static func deck_name(d: int) -> String:
	return DECKS[d]["name"]

static func deck_type(d: int) -> StringName:
	return DECKS[d]["type"]

## 取某格字元（越界回 '.'）。
static func cell_char(d: int, col: int, row: int) -> String:
	var m: Array = DECKS[d]["map"]
	if row < 0 or row >= m.size():
		return "."
	var s: String = m[row]
	if col < 0 or col >= s.length():
		return "."
	return s[col]

static func is_cell(d: int, col: int, row: int) -> bool:
	return cell_char(d, col, row) != "."

## 地形區（§5.2）：core / middle / outer；無格回 &""。電梯(X) 歸核心區。
static func zone_at(d: int, col: int, row: int) -> StringName:
	match cell_char(d, col, row).to_lower():
		"c", "x": return &"core"
		"m": return &"middle"
		"o": return &"outer"
		_: return &""

## 起始固定模塊（不可編輯・預佔）＝大寫 C/M/O。
static func is_fixed(d: int, col: int, row: int) -> bool:
	var ch := cell_char(d, col, row)
	return ch in ["C", "M", "O"]

## 垂直動線 / 電梯（不可編輯・可走・跨層通道）＝ X。
static func is_elevator(d: int, col: int, row: int) -> bool:
	return cell_char(d, col, row) == "X"

## 可建造格（小寫 c/m/o；非固定、非電梯、非空）。
static func is_buildable(d: int, col: int, row: int) -> bool:
	return cell_char(d, col, row) in ["c", "m", "o"]
