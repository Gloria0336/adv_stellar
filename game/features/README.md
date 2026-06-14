# features/ — 系統層（by-feature）

每個系統一個資料夾，內含其 **scene ＋ script ＋ 專屬 resource**。
改某系統＝只動該資料夾（架構決策 5：不改錯東西）。

## 規範
- 每系統一個 **autoload service**，暴露窄 API（唯讀查詢）。
- 跨系統溝通**只走 `EventBus` signal**，不直接持有彼此引用（決策 1）。
- 依賴只能向下：表現 → 系統 → 實體 → 資料。

## 系統 ↔ 設計文件對照（GD = GAME_DESIGN_STEAM.md）

| 資料夾 | 系統 | GD |
|---|---|---|
| build | 拼圖建造/修復 | §5.1-5.3 |
| power | 電力網/Flux | §5.4 |
| combo | 相鄰/組合/互斥 | §5.5/§5.8 |
| resource | 資源經濟/庫存 | §5.6/§13-2 |
| research | 科技樹（核心I-V）| §9.2/§13-2 |
| skilltree | 技能星網 | §9.1/§13-5 |
| diplomacy | 外交/船員 | §10.2/§13-6/§13-12 |
| shipmovement | 軌道地形/自航 | §6.5/§13-11 |
| narrative | KNOWN/HIDDEN 旗標 | §10.3/§13-3 |
| extraction | 遠征 run/撤離 | §7/§7.4 |
| levelgen | 手作地標＋隨機拼接 | §13-4.2 |
| oxygen | 氧氣倒數 | §7.4/§13-2.C |
| inventory | 背包/撤離倉/重量 | §7.4/§13-2.D/§13-8 |
| combat | 武器＋異能戰鬥 | §7.2/§13-5 |
| outpost | 前哨產出/維護/波及 | §7.1/§13-8 |
| wavedefense | 裂潮防衛戰 | §8/§13-7 |
