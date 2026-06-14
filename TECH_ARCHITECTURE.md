# 技術架構文件 — 《星際漂流》Steam EA

> **文件狀態：v0.1 — EA 技術架構骨架**
> 引擎：**Godot 4**（§11）。本文件定義資料/系統/模組的分工與規範。
> **原則**：定的是**架構骨架＋規範（conventions）**，隨原型增量長出實作，不一次鍍金。邊界先行。
> 設計依據：`GAME_DESIGN_STEAM.md`（以下簡稱 GD）。

---

## 0. 八項已定架構決策

| # | 決策 | 選定 |
|---|---|---|
| 1 | 解耦機制 | **EventBus（signal）＋ autoload service** |
| 2 | 內容資料格式 | **Godot Resource (.tres)**；存檔用 JSON（GD §13-10）|
| 3 | 移動實體 | **每類各自獨立系統 ＋ 共用底層原語** |
| 4 | 語言包深度 | **UI ＋ 全內容都 keyed** |
| 5 | 目錄結構 | **依功能分（by-feature）** |
| 6 | 場景切換 | **大情境 change_scene ＋ autoload 系統常駐** |
| 7 | 隨機性 | **中央 RNG ＋ run seed** |
| 8 | 實體粒度 | 各類獨立控制器，**共用移動/尋路/感知原語** |

---

## 1. 分層架構（依賴只向下流）

```
┌─ 表現層 Presentation ─────────────────────────────┐
│  場景 Scene · UI · Sprite/動畫 · VFX · 音效        │
│  本地化 tr()（語言包）                              │
│  規則：只透過 signal 讀系統狀態，絕不被系統反向依賴 │
└───────────────┬───────────────────────────────────┘
                │ signal（EventBus）
┌─ 系統層 Systems（autoload service ＋ EventBus）─────┐
│  Build · PowerGrid · Combo · Resource · Research ·  │
│  SkillTree · Diplomacy · ShipMovement · Narrative · │
│  Extraction · LevelGen · Oxygen · Inventory ·       │
│  Combat · Outpost · WaveDefense                     │
└───────────────┬───────────────────────────────────┘
                │ 讀
┌─ 實體層 Actor（決策3）────────────────────────────┐
│  共用原語 _core：Movement · Navigation · Perception │
│              · Stats                                │
│  各類控制器：Crew · Animal · Rift · NPC · Drone     │
│  （各自獨立行為 FSM/BT，組合共用原語）              │
└───────────────┬───────────────────────────────────┘
                │ 讀（唯讀）
┌─ 資料層 Data（.tres 內容，唯讀）──────────────────┐
│  Module · SkillNode · TechNode · Species · Item ·  │
│  EnemyArchetype · BiomeRule · LocKey               │
│  原則：數值(code無關) ≠ 字串(loc key)              │
└────────────────────────────────────────────────────┘
```

**鐵律**：上層可依賴下層，下層**永不**依賴上層；跨系統溝通一律走 EventBus，不直接持有彼此引用。這是「想法②：系統清楚分割、避免改錯東西」的結構保證。

---

## 2. 解耦機制（決策 1）

- **EventBus（autoload，全域 signal 樞紐）**：系統間通知一律 `EventBus.emit_signal(...)`，訂閱方 `connect`。系統**不互相持有引用**。
- **autoload service**：每個系統一個 autoload 單例，暴露**窄 API**（查詢類方法），跨場景常駐。
- **規範**：
  - **事件（會影響別系統）走 signal**；**唯讀查詢走 service 方法**。
  - signal 命名：`<名詞>_<過去式動詞>`，例：`module_placed`、`resource_changed`、`wave_started`、`extraction_completed`、`flag_unlocked`、`crew_recruited`。
  - 一個系統只 emit 自己領域的 signal；不 emit 別系統的。

---

## 3. 目錄結構（決策 5・by-feature）

```
res://
  core/                 # 基礎服務（autoload）
    event_bus.gd
    rng_service.gd      # 中央 RNG ＋ run seed（決策7）
    save_system.gd      # 三層存檔（GD §13-10）
    data_registry.gd    # 載入 .tres 內容資料
    localization.gd     # 語言包載入
  features/             # 每系統一資料夾（scene＋script＋專屬resource）
    build/  power/  combo/  resource/  research/  skilltree/
    diplomacy/  shipmovement/  narrative/
    extraction/  levelgen/  oxygen/  inventory/  combat/  outpost/
    wavedefense/
  entities/
    _core/              # 共用原語（決策3/8）
      movement_core.gd  navigation_core.gd
      perception_core.gd  stats_core.gd  behavior_fsm.gd
    crew/  animal/  rift/  npc/  drone/   # 各類獨立控制器
  data/                 # 跨feature的內容資料表（.tres）
    modules/  skillnodes/  technodes/  species/  items/
    enemies/  biomes/
  loc/                  # 語言包（決策4）
    strings.zh_TW.csv  strings.en.csv ...
  ui/                   # 共用UI元件（表現層）
  scenes/               # 大情境根場景（決策6）
    hub.tscn  run.tscn  starmap.tscn  wavedefense.tscn
```

> 改某系統＝只動 `features/<該系統>/`＋其 `data/`，落實「不改錯東西」。

---

## 4. 系統清單・職責・邊界（對照 GD）

> 每系統＝一個 autoload service ＋ `features/<name>/`。「擁有狀態」欄標明它在三層存檔（§6）中負責的切片。

### META 層系統

| 系統 | 職責 | 對照 GD | 擁有狀態 |
|---|---|---|---|
| **Build** | 拼圖網格建造/修復、格子解鎖 | §5.1-5.3 | meta |
| **PowerGrid** | 電力網佈線、Flux 即時收支 | §5.4/§13-2.E | meta |
| **Combo** | 相鄰/組合/互斥計算 | §5.5/§5.8 | （衍生，不存）|
| **Resource** | 資源經濟、母船庫存 | §5.6/§13-2 | meta |
| **Research** | 科技樹（核心I-V tier gate＋功能線）| §9.2/§13-2 | meta |
| **SkillTree** | 技能星網節點、技能槽 | §9.1/§13-5 | meta |
| **Diplomacy** | 外交好感、船員招募/派駐 | §10.2/§13-6/§13-12 | world |
| **ShipMovement** | 軌道地形、自航 | §6.5/§13-11 | world |
| **Narrative** | KNOWN/HIDDEN 旗標、揭露 | §10.3/§13-3 | world |

### RUN 層系統

| 系統 | 職責 | 對照 GD | 擁有狀態 |
|---|---|---|---|
| **Extraction** | 遠征 run 流程、撤離結算 | §7/§7.4 | run |
| **LevelGen** | 手作地標＋隨機拼接 | §13-4.2 | run（seed）|
| **Oxygen** | 氧氣倒數 | §7.4/§13-2.C | run |
| **Inventory** | 背包/撤離倉/重量 | §7.4/§13-2.D/§13-8 | run |
| **Combat** | 武器＋異能戰鬥 | §7.2/§13-5 | run |
| **Outpost** | 前哨產出/維護/波及 | §7.1/§13-8 | world（前哨）|

### 偶發/基礎

| 系統 | 職責 | 對照 GD |
|---|---|---|
| **WaveDefense** | 裂潮防衛戰（波次/登艦/失守）| §8/§13-7 |
| **Save** | 三層存檔序列化 | §13-10 |
| **RNG** | 中央 RNG＋run seed | （決策7）|
| **Localization** | 語言包載入、tr() | （決策4）|
| **DataRegistry** | 載入 .tres 內容 | （決策2）|

---

## 5. 實體層（決策 3/8・各自獨立＋共用原語）

**共用原語（`entities/_core/`，所有移動實體共用，不重複造輪）：**

| 原語 | 職責 |
|---|---|
| `MovementCore` | 速度/轉向/基礎位移 |
| `NavigationCore` | 尋路（封裝 NavigationAgent2D）|
| `PerceptionCore` | 視野/偵測（Area2D 感知）|
| `StatsCore` | HP/狀態值容器 |
| `BehaviorFSM` | 狀態機基類（行為掛載點）|

**各類獨立控制器（`entities/<type>/`，各自的行為 FSM/BT＋決策邏輯，組合上述原語）：**

| 控制器 | 行為 | 對照 GD |
|---|---|---|
| `CrewController` | 母船閒晃/派駐/防衛戰跑動 | §10/§13-12 |
| `AnimalController` | 掠食/逃逸/群獵 | §13-4（P1 等）|
| `RiftController` | 衝鋒群體/破壞者/投射體 | §13-7.C |
| `NPCController` | 物種/商隊/使者互動 | §13-6 |
| `DroneController` | 採集/防禦/修補無人機 | §5.7/§13-8 |

> 「獨立」＝每類有自己的行為與決策系統（你要的分割）；「共用原語」＝移動/尋路/感知不重複寫（避免 solo 重複陷阱）。

---

## 6. 狀態與存檔（GD §13-10・決策 7）

- **三層 state container**，各系統只擁有自己那一塊（見 §4「擁有狀態」欄）：
  - **meta**：Build/PowerGrid/Resource/Research/SkillTree
  - **world**：Diplomacy/ShipMovement/Narrative/Outpost
  - **run**：Extraction/Oxygen/Inventory/Combat（＋run seed）
- **SaveSystem**：序列化為 **JSON**（明文、原子寫入＋雙備份、版本號＋遷移腳本，GD §13-10）。
- **損失邊界**＝層邊界：死亡清 run 層、保 meta/world（GD §13-2.G/§13-10.D）。
- **RNGService**：中央 RNG，每 run 一個 seed（存 run 層）→ 可重現、好 debug、未來可做每日挑戰。

---

## 7. 資料層（決策 2/4）

- **內容＝Godot Resource（.tres）自訂類別**：`ModuleData`、`SkillNodeData`、`TechNodeData`、`SpeciesData`、`ItemData`、`EnemyArchetypeData`、`BiomeRuleData`。編輯器可視編、型別安全。GD 的設計表（§5.7/§9.2/§13-5/§13-6…）直接對應。
- **數值 ≠ 字串**：資料檔只存**數值＋loc key**，不存顯示文字。
- **存檔**仍用 JSON（與內容資料格式分流，GD §13-10）。

---

## 8. 本地化（決策 4）

- **全 keyed**：UI、模塊/技能/物種名與描述、對話/事件文本，**全部走 `tr("key")`**。
- 語言包：`loc/strings.<locale>.csv`（Godot i18n）。
- 資料層只引用 loc key；表現層負責 `tr()`。一開始就能多語上架。

---

## 9. 場景切換（決策 6）

- **大情境各一根場景**：`hub`（母船）/`run`（遠征）/`starmap`（星系圖）/`wavedefense`（防衛戰）。
- 切換用 `change_scene_to_file`（卸載前一個，記憶體低）。
- **系統層 service 在 autoload 常駐**，跨場景存活，狀態不因切場景丟失。

---

## 10. 待長出的細節（隨原型增量）

- [ ] 各 .tres 資料類別的具體欄位 schema
- [ ] EventBus 完整 signal 清單與 payload 規格
- [ ] 行為 FSM/BT 的具體狀態圖（各 Controller）
- [ ] LevelGen 的手作地標拼接演算法（GD §13-4.2）
- [ ] 存檔 JSON 的三層 schema 與遷移腳本（GD §13-10）
- [ ] UI 與系統的 signal 綁定清單（GD §13-9）

---

*文件結束 — v0.1 骨架。實作隨原型推進逐步補完。*
