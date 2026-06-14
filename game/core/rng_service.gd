extends Node
## 中央 RNG ＋ run seed（架構決策 7）。
## 每趟 run 一個 seed（存 run 層）→ 可重現、好 debug、未來可做每日挑戰。

var run_seed: int = 0
var _rng := RandomNumberGenerator.new()

## 開新 run：seed_value < 0 則隨機產生並記錄；否則用指定 seed。回傳實際 seed。
func new_run(seed_value: int = -1) -> int:
	if seed_value < 0:
		_rng.randomize()
		run_seed = _rng.seed
	else:
		run_seed = seed_value
		_rng.seed = seed_value
	return run_seed

func get_run_seed() -> int:
	return run_seed

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

# TODO: 具名子串流（per-system stream），隔離各系統的隨機序列以利重現
