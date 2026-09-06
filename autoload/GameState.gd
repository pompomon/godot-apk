extends Node
## Single source of truth for the Company. No new-game content is seeded yet.
## Roster becomes Array[HeroData] in Milestone 2; inventory becomes
## Array[ItemResource] in Milestone 6.

var roster: Array = []
var gold: int = 0
var inventory: Array = []
var unlocked_regions: Array[StringName] = []
