extends Node
## 全域事件樞紐（架構決策 1）。
## 跨系統溝通一律 emit/connect 這裡的 signal——系統不互相持有引用。
## 命名規範：<名詞>_<過去式動詞>；一個系統只 emit 自己領域的 signal。
## 此清單隨系統實作增量補完（TECH_ARCHITECTURE §2/§10）。

# --- META：Build / PowerGrid / Resource ---
signal module_placed(module_id: StringName, cell: Vector2i)
signal module_removed(module_id: StringName, cell: Vector2i)
signal cell_unlocked(cell: Vector2i)
signal power_grid_changed(net_flux: int)
signal resource_changed(resource_id: StringName, amount: int)
signal module_destroyed(module_id: StringName, cell: Vector2i)   # 防衛戰模塊被毀（§13-7.E）

# --- META：Research / SkillTree ---
signal ship_core_repaired(tier: int)        # 核心 I-V tier gate（GD §9.2）
signal tech_unlocked(node_id: StringName)
signal skill_node_unlocked(node_id: StringName)

# --- META：Diplomacy / ShipMovement / Narrative ---
signal favor_changed(species_id: StringName, tier: int)   # 五階 -2~+2（GD §13-6）
signal crew_recruited(crew_id: StringName)
signal orbit_terrain_rolled(terrain_id: StringName)        # 軌道地形（GD §13-11）
signal flag_unlocked(flag_id: StringName)                  # KNOWN/HIDDEN（GD §13-3）

# --- 基礎：ShipClock 全域時鐘 ---
signal ship_hour_changed(hour: int)
signal ship_day_changed(day: int)

# --- META：Crew AI 情緒/日程（GD §10/§13-12）---
signal crew_mood_changed(crew_id: StringName, mood: int)         # CrewMood.Mood
signal crew_activity_changed(crew_id: StringName, activity: StringName)  # CrewMember 行為 key
signal crew_spoke(crew_id: StringName, line_key: StringName)     # 口頭禪/台詞氣泡

# --- META→RUN 橋接：StarMap 選星（GD §13-9.E）---
signal planet_selected(planet_id: StringName)              # 星系圖登陸出航 → 之後接 run_started

# --- RUN：Extraction / Oxygen / Inventory / Combat ---
signal run_started(seed_value: int, planet_id: StringName)
signal oxygen_changed(current: int, max_value: int)        # GD §13-2.C
signal inventory_changed()
signal extraction_completed(success: bool)                 # GD §7.4
signal player_died()

# --- 偶發：WaveDefense（GD §13-7）---
signal wave_started(wave_index: int)
signal wave_cleared(wave_index: int)
signal defense_failed()
