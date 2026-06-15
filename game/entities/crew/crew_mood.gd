class_name CrewMood
extends RefCounted
## 由連續狀態軸（CrewNeeds）推導離散情緒，再給出表現：emoji／效率倍率／loc key／口頭禪。
## 純函式・優先序：危機 ＞ 生理 ＞ 情緒負向 ＞ 情緒正向 ＞ 平靜。

enum Mood {
	NEUTRAL,     # 平靜 🙂
	HAPPY,       # 高興 🎵（唱歌）
	INSPIRED,    # 幹勁 💪
	TIRED,       # 疲累 😩
	HUNGRY,      # 飢餓 🍖
	LONELY,      # 寂寞 😔
	DISGRUNTLED, # 不滿 😠
	BORED,       # 無聊 😪
	HURT,        # 受傷 🤕
	AFRAID,      # 害怕 😱
}

# 閾值（與 CrewMember 決策共用）。
const FEAR_PANIC := 60.0
const HEALTH_HURT := 35.0
const ENERGY_TIRED := 40.0       # 疲累情緒（仍能工作但效率降）
const SATIATION_HUNGRY := 25.0
const SOCIAL_LONELY := 20.0
const MORALE_LOW := 25.0
const MORALE_HIGH := 75.0
const INSPIRED_ENERGY := 60.0    # 士氣高且精力足 → 幹勁，否則高興
const BORED_IDLE_SEC := 30.0

static func derive(n: CrewNeeds, idle_time: float = 0.0) -> Mood:
	if n.fear >= FEAR_PANIC: return Mood.AFRAID
	if n.health <= HEALTH_HURT: return Mood.HURT
	if n.energy <= ENERGY_TIRED: return Mood.TIRED
	if n.satiation <= SATIATION_HUNGRY: return Mood.HUNGRY
	if n.morale <= MORALE_LOW: return Mood.DISGRUNTLED
	if n.social <= SOCIAL_LONELY: return Mood.LONELY
	if n.morale >= MORALE_HIGH:
		return Mood.INSPIRED if n.energy >= INSPIRED_ENERGY else Mood.HAPPY
	if idle_time >= BORED_IDLE_SEC: return Mood.BORED
	return Mood.NEUTRAL

static func emoji(m: Mood) -> String:
	match m:
		Mood.HAPPY: return "🎵"
		Mood.INSPIRED: return "💪"
		Mood.TIRED: return "😩"
		Mood.HUNGRY: return "🍖"
		Mood.LONELY: return "😔"
		Mood.DISGRUNTLED: return "😠"
		Mood.BORED: return "😪"
		Mood.HURT: return "🤕"
		Mood.AFRAID: return "😱"
		_: return "🙂"

## 情緒 → 工作效率倍率。v1 僅供查詢/面板，未接生產系統。
static func efficiency_mult(m: Mood) -> float:
	match m:
		Mood.INSPIRED: return 1.25
		Mood.HAPPY: return 1.1
		Mood.TIRED: return 0.5
		Mood.HUNGRY: return 0.7
		Mood.DISGRUNTLED: return 0.6
		Mood.LONELY: return 0.85
		Mood.BORED: return 0.8
		Mood.HURT: return 0.4
		Mood.AFRAID: return 0.0
		_: return 1.0

static func loc_key(m: Mood) -> StringName:
	match m:
		Mood.HAPPY: return &"crew.mood.happy"
		Mood.INSPIRED: return &"crew.mood.inspired"
		Mood.TIRED: return &"crew.mood.tired"
		Mood.HUNGRY: return &"crew.mood.hungry"
		Mood.LONELY: return &"crew.mood.lonely"
		Mood.DISGRUNTLED: return &"crew.mood.disgruntled"
		Mood.BORED: return &"crew.mood.bored"
		Mood.HURT: return &"crew.mood.hurt"
		Mood.AFRAID: return &"crew.mood.afraid"
		_: return &"crew.mood.neutral"

## 情緒切換時的共用台詞/口頭禪 loc key（crew_spoke 廣播給氣泡）。
static func quip_key(m: Mood) -> StringName:
	match m:
		Mood.HAPPY: return &"crew.quip.happy"
		Mood.INSPIRED: return &"crew.quip.inspired"
		Mood.TIRED: return &"crew.quip.tired"
		Mood.HUNGRY: return &"crew.quip.hungry"
		Mood.LONELY: return &"crew.quip.lonely"
		Mood.DISGRUNTLED: return &"crew.quip.disgruntled"
		Mood.BORED: return &"crew.quip.bored"
		Mood.HURT: return &"crew.quip.hurt"
		Mood.AFRAID: return &"crew.quip.afraid"
		_: return &"crew.quip.neutral"
