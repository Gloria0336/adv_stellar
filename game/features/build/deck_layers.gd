class_name DeckLayers
extends RefCounted
## 甲板分層（任務）：Y 方向分 8 層，高度 2/2/3/3/3/2/2/2（合計 19 列）；X 維持 100。

const HEIGHTS := [2, 2, 3, 3, 3, 2, 2, 2]   # 合計 = 19 = 總列數

static func total_rows() -> int:
	var s := 0
	for h in HEIGHTS:
		s += h
	return s

## 某列屬於第幾層
static func layer_of(row: int) -> int:
	var acc := 0
	for i in HEIGHTS.size():
		acc += HEIGHTS[i]
		if row < acc:
			return i
	return HEIGHTS.size() - 1

## 某層的起始列
static func layer_start(layer: int) -> int:
	var acc := 0
	for i in layer:
		acc += HEIGHTS[i]
	return acc
