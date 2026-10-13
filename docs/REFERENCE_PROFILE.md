# Reference Instance list

A real-world Instance list (what to turn off for Mythic+ and raids), drawn from a
201-addon install (2026-10-08). Used as the test fixture for the switch plan, as the
first list entered during in-game QA, and as the model for the suggested lists
(`Suggest.lua`). Not shipped as a default: every install differs, and Suggest on the
Lists page is the generic path.

## Instance list

**Professions and auction house:** TradeSkillMaster, TradeSkillMaster_AppHelper,
Auctionator, Collectionator, BestCraft, ShoppingConverter, CraftSim,
ProfessionShoppingList, PublicOrdersReagentsColumn, TradeSkillFluxCapacitor,
WeeklyKnowledge, MoxieTracker, BuyEmAll, AutoMailer, Currency Transfer Helper,
WarbandMiser

**Alt tracking:** Altoholic and `Altoholic_*` (8), DataStore and `DataStore_*` (17),
AddonFactory, AccountWideStats

**Collections, pets, housing:** Rematch, tdBattlePetScript, BattlePetBattleUITweaks,
PepeCollection, CanIMogIt, MountJournalEnhanced, ManuscriptsJournal, DecorSpendwatch,
QoLify_Decor, QoLify_DecorSpendwatch

**Open world and navigation:** HandyNotes, HandyNotes_MapNotes, TomTom, MapPinEnhanced,
WaypointUI, WorldQuestsList, Leatrix_Maps, QoLify_CompassBar, CoyFlightline,
DragonRider, BetterFishing, ReputationWatcher, LarlenCacheOpener, +Wowhead_Looter

**DBM:** all `DBM-Raids-*`; world bosses (Azeroth, BfA, BrokenIsles, Cataclysm,
Draenor, Outlands, Pandaria, Shadowlands, Midnight); Delves-Midnight,
Delves-WarWithin, Lairs-Midnight, Brawlers, PvP, WorldEvents, Scenario-MoP,
LegionFishing, DBM-Test, DBM-Test-Dungeons, DBM-Test-Vanilla; `DBM-Party-*` for
expansions with no dungeon in the current season

**Raider.IO:** RaiderIO_DB_US_R, RaiderIO_DB_US_F, and every non-US region database

**Details!:** Details_Streamer, Details_Compare2, Details_Vanguard, Details_RaidCheck

**Titan Panel plugins:** TitanAlts, TitanAmmo, TitanClassic, TitanBag,
TitanCurrenciesMulti, TitanLocation, TitanLootType, TitanPost, TitanRegen, TitanUI,
TitanVolume, TitanXP

**Developer and miscellaneous:** BlizzMove_Debug, TooltipID, PasteNG, Simulationcraft,
QoLify_SoundScaper, Leatrix_Sounds

## Undecided

GearSweep, RecklessAbandon, Preydator, Plumber, SlackersTweakSuite.

## Why these

The largest SavedVariables files on that install were CraftSim (10.1 MB),
TradeSkillMaster (8.4 MB), Auctionator (6.8 MB) and ProfessionShoppingList (4.2 MB) --
about 30 MB parsed at every login that does nothing in a dungeon.
