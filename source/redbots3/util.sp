#include <stocklib_officerspy/tf/tf_bot>
#include <stocklib_officerspy/tf/tf_player>
#include <stocklib_officerspy/tf/tf_obj>
#include <stocklib_officerspy/tf/tf_objective_resource>
#include <stocklib_officerspy/tf/stocklib_extra_vscript>
#include <stocklib_officerspy/econ_item_view>
#include <stocklib_officerspy/tf/tf_weaponbase>
#include <stocklib_officerspy/tf/entity_capture_flag>
#include <stocklib_officerspy/shared/util_shared>
#include <stocklib_officerspy/mathlib/vector>

#define SENTRY_MAX_RANGE 1100.0

//WeaponData > Range in file tf_weapon_medigun.txt
#define WEAPON_MEDIGUN_RANGE	450.0

//CTFWeaponBuilder::InternalGetEffectBarRechargeTime
#define SAPPER_RECHARGE_TIME	15.0

//Raw value found in CBaseObject::FindBuildPointOnPlayer
#define SAPPER_PLAYER_BUILD_ON_RANGE	160.0

//ConVar cl_sidespeed
#define PLAYER_SIDESPEED	450.0

//Raw value found in CTFBotMainAction::FireWeaponAtEnemy
#define TFBOT_MELEE_ATTACK_RANGE	250.0

//PlayerLocomotion::GetStepHeight
#define TFBOT_STEP_HEIGHT	18.0

#define SNIPER_REACTION_TIME	0.5

enum //medigun_resist_types_t
{
	MEDIGUN_BULLET_RESIST = 0,
	MEDIGUN_BLAST_RESIST,
	MEDIGUN_FIRE_RESIST,
	MEDIGUN_NUM_RESISTS
}

enum //medigun_weapontypes_t
{
	MEDIGUN_STANDARD = 0,
	MEDIGUN_UBER,
	MEDIGUN_QUICKFIX,
	MEDIGUN_RESIST
}

enum struct BombInfo_t
{
	float vPosition[3];
	float flMinBattleFront;
	float flMaxBattleFront
}

enum
{
	TF_LOADOUT_SLOT_PRIMARY   =  0,
	TF_LOADOUT_SLOT_SECONDARY =  1,
	TF_LOADOUT_SLOT_MELEE     =  2,
	TF_LOADOUT_SLOT_UTILITY   =  3,
	TF_LOADOUT_SLOT_BUILDING  =  4,
	TF_LOADOUT_SLOT_PDA       =  5,
	TF_LOADOUT_SLOT_PDA2      =  6,
	TF_LOADOUT_SLOT_HEAD      =  7,
	TF_LOADOUT_SLOT_MISC      =  8,
	TF_LOADOUT_SLOT_ACTION    =  9,
	TF_LOADOUT_SLOT_MISC2     = 10,
	TF_LOADOUT_SLOT_TAUNT     = 11,
	TF_LOADOUT_SLOT_TAUNT2    = 12,
	TF_LOADOUT_SLOT_TAUNT3    = 13,
	TF_LOADOUT_SLOT_TAUNT4    = 14,
	TF_LOADOUT_SLOT_TAUNT5    = 15,
	TF_LOADOUT_SLOT_TAUNT6    = 16,
	TF_LOADOUT_SLOT_TAUNT7    = 17,
	TF_LOADOUT_SLOT_TAUNT8    = 18,
}

enum eMissionDifficulty
{
	MISSION_UNKNOWN = 0,
	MISSION_NORMAL,
	MISSION_INTERMEDIATE,
	MISSION_ADVANCED,
	MISSION_EXPERT,
	MISSION_NIGHTMARE,
	MISSION_MAX_COUNT
}

enum
{
	STATS_CREDITS_DROPPED = 0,
	STATS_CREDITS_ACQUIRED,
	STATS_CREDITS_BONUS,
	STATS_PLAYER_DEATHS,
	STATS_BUYBACKS
}

char g_sPlayerUseMyNameResponse[][] =
{
	"You're very funny for using my name.",
	"You totally stole my name."
};

//NOTE: Make sure this matches with the eMissionDifficulty enum size
char g_sMissionDifficultyFilePaths[][] =
{
	"",
	"configs/defenderbots/mission/mission_normal.txt",
	"configs/defenderbots/mission/mission_intermediate.txt",
	"configs/defenderbots/mission/mission_advanced.txt",
	"configs/defenderbots/mission/mission_expert.txt",
	"configs/defenderbots/mission/mission_nightmare.txt"
};

char g_sBotTeamCompositions[][][] =
{
	{"scout", "soldier", "demoman", "heavyweapons", "engineer", "medic"},
	{"scout", "heavyweapons", "heavyweapons", "heavyweapons", "engineer", "sniper"},
	{"scout", "heavyweapons", "heavyweapons", "pyro", "engineer", "demoman"}
};

char g_sRawPlayerClassNames[][] =
{
	"undefined",
	"scout",
	"sniper",
	"soldier",
	"demoman",
	"medic",
	"heavyweapons",
	"pyro",
	"spy",
	"engineer",
	"civilian",
	"",
	"random"
};

static bool TraceFilter_TFBot(int entity, int contentsMask, StringMap data)
{
	//NextBotTraceFilterIgnoreActors
	if (CBaseEntity(entity).IsCombatCharacter())
		return false;
	
	//CTraceFilterIgnoreFriendlyCombatItems
	int iPassEnt = -1;
	data.GetValue("m_pPassEnt", iPassEnt);
	
	int iCollisionGroup;
	data.GetValue("m_collisionGroup", iCollisionGroup);
	
	int iIgnoreTeam;
	data.GetValue("m_iIgnoreTeam", iIgnoreTeam);
	
	if (BaseEntity_IsCombatItem(entity))
	{
		if (BaseEntity_GetTeamNumber(entity) == iIgnoreTeam)
			return false;
		
		//m_bCallerIsProjectile is false here
	}
	
	//CTraceFilterSimple as BaseClass of CTraceFilterIgnoreFriendlyCombatItems
	if (!StandardFilterRules(entity, contentsMask))
		return false;
	
	if (iPassEnt != -1)
	{
		if (!PassServerEntityFilter(entity, iPassEnt))
			return false;
	}
	
	if (!ShouldCollide(entity, iCollisionGroup, contentsMask))
		return false;
	
	if (!TFGameRules_ShouldCollide(iCollisionGroup, BaseEntity_GetCollisionGroup(entity)))
		return false;
	
	//CTraceFilterChain checks if both filters are true
	return true;
}

//CNavArea::GetRandomPoint
void CNavArea_GetRandomPoint(CNavArea area, float buffer[3])
{
	float eLo[3], eHi[3];
	area.GetExtent(eLo, eHi);
	
	float spot[3];
	spot[0] = GetRandomFloat(eLo[0], eHi[0]);
	spot[1] = GetRandomFloat(eLo[1], eHi[1]);
	spot[2] = area.GetZ(spot[0], spot[1]);
	
	buffer = spot;
}

bool IsTFBotPlayer(int client)
{
	//TODO: change this, as it's not entirely reliable
	return IsFakeClient(client);
}

bool IsFinalWave()
{
	int rsrc = FindEntityByClassname(MaxClients + 1, "tf_objective_resource");
	
	if (rsrc != -1)
	{
		if (TF2_GetMannVsMachineWaveCount(rsrc) == TF2_GetMannVsMachineMaxWaveCount(rsrc))
			return true;
	}
	else
	{
		LogError("IsFinalWave: Could find entity tf_objective_resource!");
	}
	
	return false;
}

//Set up an entity for item creation
int EconItemCreateNoSpawn(char[] classname, int itemDefIndex, int level, int quality)
{
	int item = CreateEntityByName(classname);
	
	if (item != -1)
	{
		SetEntProp(item, Prop_Send, "m_iItemDefinitionIndex", itemDefIndex);
		SetEntProp(item, Prop_Send, "m_bInitialized", 1);
		
		//SetEntProp doesn't work here...
		static int iOffsetEntityQuality = -1;
		
		if (iOffsetEntityQuality == -1)
			iOffsetEntityQuality = FindSendPropInfo("CEconEntity", "m_iEntityQuality");
		
		static int iOffsetEntityLevel = -1;
		
		if (iOffsetEntityLevel == -1)
			iOffsetEntityLevel = FindSendPropInfo("CEconEntity", "m_iEntityLevel");
		
		SetEntData(item, iOffsetEntityQuality, quality);
		SetEntData(item, iOffsetEntityLevel, level);
		
		if (StrEqual(classname, "tf_weapon_builder", false))
		{
			/* NOTE: After the 2023-10-09 update, not setting netprop m_iObjectType
			will crash all client games (but the server will remain fine)
			I suspect the client's game code change and not setting it cause it to read garbage */
			SetEntProp(item, Prop_Send, "m_iObjectType", 3); //Set to OBJ_ATTACHMENT_SAPPER?
			
			bool isSapper = IsItemDefIndexSapper(itemDefIndex);
			
			if (isSapper)
				SetEntProp(item, Prop_Data, "m_iSubType", 3);
			
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", isSapper ? 0 : 1, _, 0); //OBJ_DISPENSER
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", isSapper ? 0 : 1, _, 1); //OBJ_TELEPORTER
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", isSapper ? 0 : 1, _, 2); //OBJ_SENTRYGUN
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", isSapper ? 1 : 0, _, 3); //OBJ_ATTACHMENT_SAPPER
		}
		else if (StrEqual(classname, "tf_weapon_sapper", false))
		{
			SetEntProp(item, Prop_Send, "m_iObjectType", 3);
			SetEntProp(item, Prop_Data, "m_iSubType", 3);
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 0, _, 0);
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 0, _, 1);
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 0, _, 2);
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 1, _, 3);
		}
	}
	else
	{
		LogError("EconItemCreateNoSpawn: Failed to create entity.");
	}
	
	return item;
}

//Call this when you're ready to spawn it
void EconItemSpawnGiveTo(int item, int client)
{
	DispatchSpawn(item);
	
	if (TF2Util_IsEntityWearable(item))
	{
		TF2Util_EquipPlayerWearable(client, item);
	}
	else
	{
		EquipPlayerWeapon(client, item);
		// TF2Util_SetPlayerActiveWeapon(client, item);
	}
	
	//NOTE: Bot players always have their items visible in PvE modes
	// SetEntProp(item, Prop_Send, "m_bValidatedAttachedEntity", 1);
}

int GiveItemToPlayer(int client, char[] classname, int itemDefIndex, int level, int quality)
{
	int item = EconItemCreateNoSpawn(classname, itemDefIndex, level, quality);
	
	if (item != -1)
	{
		EconItemView_SetItemID(item, GetRandomInt(1, 2048));
		EconItemSpawnGiveTo(item, client);
	}
	
	return item;
}

bool EquipWeaponSlot(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);
	
	if (weapon != -1)
		return TF2Util_SetPlayerActiveWeapon(client, weapon);
	
	return false;
}

float GetTimeSinceWeaponFired(int client)
{
	int iWeapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (iWeapon == -1)
		return 9999.0;
		
	float flLastFireTime = GetEntPropFloat(iWeapon, Prop_Send, "m_flLastFireTime");
	
	if (flLastFireTime <= 0.0)
		return 9999.0;
		
	return GetGameTime() - flLastFireTime;
}

//CWeaponMedigun::GetMedigunType
int GetMedigunType(int weapon)
{
	return TF2Attrib_HookValueInt(0, "set_weapon_mode", weapon);
}

int GetResistType(int weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_nChargeResistType");
}

float[] WorldSpaceCenter(int entity)
{
	float vec[3];
	CBaseEntity(entity).WorldSpaceCenter(vec);
	return vec;
}

bool HasSniperRifle(int client)
{
	int iWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	
	if (iWeapon == -1)
		return false;
	
	return WeaponID_IsSniperRifle(TF2Util_GetWeaponID(iWeapon));
}

void DetonateObjectOfType(int client, TFObjectType iType, TFObjectMode iMode = TFObjectMode_None, bool bIgnoreSapperState = false)
{
	int iObj = GetObjectOfType(client, iType, iMode);
	
	if (iObj == -1)
		return;
	
	if (!bIgnoreSapperState && (TF2_HasSapper(iObj) || TF2_IsPlasmaDisabled(iObj)))
		return;
	
	Event hEvent = CreateEvent("object_removed");
	
	if (hEvent)
	{
		hEvent.SetInt("userid", GetClientUserId(client));
		hEvent.SetInt("objecttype", iType);
		hEvent.SetInt("index", iObj);
		hEvent.Fire();
	}
	
	TF2_DetonateObject(iObj);
}

int GetObjectOfType(int client, TFObjectType iObjectType, TFObjectMode iObjectMode = TFObjectMode_None)
{
	int iNumObjects = TF2Util_GetPlayerObjectCount(client);
	
	for (int i = 0; i < iNumObjects; i++)
	{
		int iObj = TF2Util_GetPlayerObject(client, i);
		
		if (TF2_GetObjectType(iObj) != iObjectType)
			continue;
		
		if (iObjectType == TFObject_Teleporter && TF2_GetObjectMode(iObj) != iObjectMode)
			continue;
		
		if (TF2_IsDisposableBuilding(iObj))
			continue;
		
		return iObj;
	}
	
	return -1;
}

float[] GetAbsOrigin(int entity)
{
	float vec[3]; CBaseEntity(entity).GetAbsOrigin(vec);
	
	return vec;
}

bool IsWeapon(int client, int iWeaponID)
{
	int iWeapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (iWeapon > 0)
		return TF2Util_GetWeaponID(iWeapon) == iWeaponID;
	
	return false;
}

bool IsSentryBusterRobot(int client)
{
	if (IsTFBotPlayer(client))
		return GetTFBotMission(client) == CTFBot_MISSION_DESTROY_SENTRIES;
	
	char model[PLATFORM_MAX_PATH]; GetClientModel(client, model, PLATFORM_MAX_PATH);
	
	return StrEqual(model, "models/bots/demo/bot_sentry_buster.mdl");
}

int FindBotNearestToBombNearestToHatch(int client)
{
	int iBomb = FindBombNearestToHatch();
	
	if (iBomb <= 0)
		return -1;
	
	float flOrigin[3]; flOrigin = WorldSpaceCenter(iBomb);
	
	float flBestDistance = 999999.0;
	int iBestEntity = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != GetPlayerEnemyTeam(client))
			continue;
		
		if (TF2Util_IsPointInRespawnRoom(WorldSpaceCenter(i)))
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		float flDistance = GetVectorDistance(WorldSpaceCenter(i), flOrigin);
		
		if (flDistance <= flBestDistance)
		{
			flBestDistance = flDistance;
			iBestEntity = i;
		}
	}
	
	return iBestEntity;
}

int FindBombNearestToHatch()
{
	float flOrigin[3]; flOrigin = GetBombHatchPosition();
	
	float flBestDistance = 999999.0;
	int iBestEntity = -1;
	
	int iEnt = -1;
	
	while ((iEnt = FindEntityByClassname(iEnt, "item_teamflag")) != -1)
	{
		if (CaptureFlag_IsHome(iEnt))
			continue;
		
		float flDistance = GetVectorDistance(flOrigin, WorldSpaceCenter(iEnt));
		
		if (flDistance <= flBestDistance)
		{
			flBestDistance = flDistance;
			iBestEntity = iEnt;
		}
	}
	
	return iBestEntity;
}

int SelectRandomReachableEnemy(int actor)
{
	TFTeam opposingTFTeam = GetPlayerEnemyTeam(actor);
	
	int playerarray[MAXPLAYERS + 1];
	int playercount;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == actor)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != opposingTFTeam)
			continue;
		
		if (TF2Util_IsPointInRespawnRoom(WorldSpaceCenter(i)))
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		playerarray[playercount] = i;
		playercount++;
	}
	
	if (playercount > 0)
		return playerarray[GetRandomInt(0, playercount-1)];
	
	return -1;
}

bool IsHealedByMedic(int client)
{
	for (int i = 0; i < TF2_GetNumHealers(client); i++)
	{
		int iHealerIndex = TF2Util_GetPlayerHealer(client, i);
		
		//Not a player.
		if (!BaseEntity_IsPlayer(iHealerIndex))
			continue;
		
		return true;
	}
	
	return false;
}

float[] GetBombHatchPosition(bool bUseAbsOrigin = false)
{
	float vOrigin[3];

	int iHole = FindEntityByClassname(-1, "func_capturezone");
	
	if (iHole != -1)
		vOrigin = bUseAbsOrigin ? GetAbsOrigin(iHole) : WorldSpaceCenter(iHole);
	
	return vOrigin;
}

TFTeam GetPlayerEnemyTeam(int client)
{
	return TF2_GetEnemyTeam(TF2_GetClientTeam(client));
}

int GetAcquiredCreditsOfAllWaves(bool withBonus = true)
{
	int ent = FindEntityByClassname(MaxClients + 1, "tf_mann_vs_machine_stats");
	
	if (ent == -1)
	{
		LogError("GetAcquiredCreditsOfAllWaves: Could not find entity tf_mann_vs_machine_stats!");
		return 0;
	}
	
	int total = GetEntProp(ent, Prop_Send, "m_runningTotalWaveStats", _, STATS_CREDITS_ACQUIRED);
	total += GetEntProp(ent, Prop_Send, "m_previousWaveStats", _, STATS_CREDITS_ACQUIRED);
	total += GetEntProp(ent, Prop_Send, "m_currentWaveStats", _, STATS_CREDITS_ACQUIRED);
	
	if (withBonus)
	{
		total += GetEntProp(ent, Prop_Send, "m_runningTotalWaveStats", _, STATS_CREDITS_BONUS);
		total += GetEntProp(ent, Prop_Send, "m_previousWaveStats", _, STATS_CREDITS_BONUS);
		total += GetEntProp(ent, Prop_Send, "m_currentWaveStats", _, STATS_CREDITS_BONUS);
	}
	
	return total;
}

int GerNearestTeammate(int client, const float max_distance)
{
	float origin[3]; origin = WorldSpaceCenter(client);
	
	float bestDistance = 999999.0;
	int bestEntity = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (GetClientTeam(i) != GetClientTeam(client))
			continue;
		
		float distance = GetVectorDistance(WorldSpaceCenter(i), origin);
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = i;
		}
	}
	
	return bestEntity;
}

int GetNearestReviveMarker(int client, const float max_distance)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	float bestDistance = 999999.0;
	int bestEntity = -1;
	
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "entity_revive_marker")) != -1)
	{
		if (BaseEntity_GetTeamNumber(iEnt) != GetClientTeam(client))
			continue;
		
		float distance = GetVectorDistance(origin, GetAbsOrigin(iEnt));
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = iEnt;
		}
	}
	
	return bestEntity;
}

/* void PowerupBottle_Reset(int bottle)
{
	SetEntProp(bottle, Prop_Send, "m_bActive", false);
} */

//CTFPowerupBottle::GetPowerupType
int PowerupBottle_GetType(int bottle)
{
	if (TF2Attrib_HookValueInt(0, "critboost", bottle))
		return POWERUP_BOTTLE_CRITBOOST;
	
	if (TF2Attrib_HookValueInt(0, "ubercharge", bottle))
		return POWERUP_BOTTLE_UBERCHARGE;
	
	if (TF2Attrib_HookValueInt(0, "recall", bottle))
		return POWERUP_BOTTLE_RECALL;
	
	if (TF2Attrib_HookValueInt(0, "refill_ammo", bottle))
		return POWERUP_BOTTLE_REFILL_AMMO;
	
	if (TF2Attrib_HookValueInt(0, "building_instant_upgrade", bottle))
		return POWERUP_BOTTLE_BUILDINGS_INSTANT_UPGRADE;
	
	return POWERUP_BOTTLE_NONE;
}

/* void PowerupBottle_SetNumCharges(int bottle, int numCharges)
{
	SetEntProp(bottle, Prop_Send, "m_usNumCharges", numCharges);
	
	TF2Attrib_SetByName(bottle, "powerup charges", float(numCharges));
} */

int PowerupBottle_GetNumCharges(int bottle)
{
	return GetEntProp(bottle, Prop_Send, "m_usNumCharges");
}

//CTFPowerupBottle::GetMaxNumCharges
int PowerupBottle_GetMaxNumCharges(int bottle)
{
	return TF2Attrib_HookValueInt(0, "powerup_max_charges", bottle);
}

/* int GetCostOfCanteenType(PowerupBottleType_t type)
{
	switch (type)
	{
		case POWERUP_BOTTLE_CRITBOOST:	return 100;
		case POWERUP_BOTTLE_UBERCHARGE:	return 75;
		case POWERUP_BOTTLE_RECALL:	return 10;
		case POWERUP_BOTTLE_REFILL_AMMO:	return 25;
		case POWERUP_BOTTLE_BUILDINGS_INSTANT_UPGRADE:	return 50;
	}
} */

int GetPowerupBottle(int client)
{
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "tf_powerup_bottle")) != -1)
		if (BaseEntity_GetOwnerEntity(ent) == client)
			break;
	
	return ent;
}

//CTFFlameThrower::CanAirBlast
bool CanWeaponAirblast(int weapon)
{
	return TF2Attrib_HookValueInt(0, "airblast_disabled", weapon) == 0;
}

int FindEnemyNearestToMe(int client, const float max_distance, bool bGiantsOnly = false, bool bIgnoreUber = false, bool bStunnedOnly = false, TFClassType class = TFClass_Unknown)
{
	float origin[3]; origin = WorldSpaceCenter(client);
	
	float bestDistance = 999999.0;
	int bestEntity = -1;
	TFTeam enemyTeam = GetPlayerEnemyTeam(client);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != enemyTeam)
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		if (bGiantsOnly && !TF2_IsMiniBoss(i))
			continue;
		
		if (bIgnoreUber && TF2_IsInvulnerable(i))
			continue;
		
		if (bStunnedOnly && !TF2_IsPlayerInCondition(i, TFCond_Dazed))
			continue;
		
		if (class > TFClass_Unknown && TF2_GetPlayerClass(i) != class)
			continue;
		
		if (TF2_IsStealthed(i) && !IsCloakedPlayerExposed(i))
			continue;
		
		float distance = GetVectorDistance(WorldSpaceCenter(i), origin);
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = i;
		}
	}
	
	return bestEntity;
}

int GetBestTargetForSpy(int client, const float max_distance)
{
	int target = -1;
	
	//Find the nearest enemy engineer
	target = FindEnemyNearestToMe(client, max_distance, false, true, false, TFClass_Engineer);
	
	//Find the nearest stunned enemy
	if (target == -1)
		target = FindEnemyNearestToMe(client, max_distance, false, true, true);
	
	//Find the nearest enemy giant
	if (target == -1)
		target = FindEnemyNearestToMe(client, max_distance, true, true);
	
	//Find the nearest enemy
	if (target == -1)
		target = FindEnemyNearestToMe(client, max_distance, false, true);
	
	//Target their healer first, if they have one
	if (target != -1)
	{
		int myTeam = GetClientTeam(client);
		
		for (int i = 0; i < TF2_GetNumHealers(target); i++)
		{
			int healer = TF2Util_GetPlayerHealer(target, i);
			
			if (healer != -1 && BaseEntity_IsPlayer(healer) && GetClientTeam(healer) != myTeam)
			{
				target = healer;
				break;
			}
		}
	}
	
	return target;
}

/* To trigger the robo sapper, you need to do several things
- set a builder
- set the object mode to MODE_SAPPER_ANTI_ROBOT or MODE_SAPPER_ANTI_ROBOT_RADIUS
- parent the sapper to some entity
- set the entity the sapper is being built on
- then fire input Enable to call CObjectSapper::OnGoActive */
int SpawnSapper(int owner, int entity, int weapon = -1)
{
	int sapper = CreateEntityByName("obj_attachment_sapper");
	
	if (sapper != -1)
	{
		AcceptEntityInput(sapper, "SetBuilder", owner);
		
		if (weapon > 0)
			TF2_SetObjectMode(sapper, GetEntProp(weapon, Prop_Send, "m_iObjectMode"));
		
		ParentEntity(entity, sapper, BaseEntity_IsPlayer(entity) ? "head" : "weapon_bone");
		SetEntPropEnt(sapper, Prop_Send, "m_hBuiltOnEntity", entity);
		SetEntProp(sapper, Prop_Send, "m_bBuilding", 1);
		DispatchSpawn(sapper);
		RemoveEffects(sapper, EF_NODRAW);
	}
	
	return sapper;
}

void RemoveEffects(int entity, int nEffects)
{
	SetEntProp(entity, Prop_Send, "m_fEffects", GetEntProp(entity, Prop_Send, "m_fEffects") & ~nEffects);
	
	if (nEffects & EF_NODRAW)
		CBaseEntity(entity).DispatchUpdateTransmitState();
}

//Based on CTFKnife::CanPerformBackstabAgainstTarget
bool HasBackstabPotential(int client)
{
	//These are MvM-specific conditions, where stunned bots are usually allowed to be backstabbed
	if (TF2_GetClientTeam(client) == TFTeam_Blue)
	{
		if (TF2_IsPlayerInCondition(client, TFCond_MVMBotRadiowave))
			return true;
		
		if (TF2_IsPlayerInCondition(client, TFCond_Sapped) && !TF2_IsMiniBoss(client))
			return true;
	}
	
	return false;
}

int GetNearestSappableObject(int client, const float max_distance = 1000.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	int myTeam = GetClientTeam(client);
	
	float bestDistance = 999999.0;
	int bestEnt = -1;
	
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "obj_*")) != -1)
	{
		if (TF2_GetObjectType(ent) == TFObject_Sapper)
			continue;
		
		if (BaseEntity_GetTeamNumber(ent) == myTeam)
			continue;
		
		if (TF2_IsPlacing(ent))
			continue;
		
		if (TF2_IsCarried(ent))
			continue;
		
		if (TF2_HasSapper(ent))
			continue;
		
		float distance = GetVectorDistance(origin, GetAbsOrigin(ent));
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEnt = ent;
		}
	}
	
	return bestEnt;
}

int GetNearestEnemyTeleporter(int client, const float max_distance = 999999.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	int myTeam = GetClientTeam(client);
	
	float bestDistance = 999999.0;
	int bestEnt = -1;
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "obj_teleporter")) != -1)
	{
		if (BaseEntity_GetTeamNumber(ent) == myTeam)
			continue;
		
		if (TF2_IsPlacing(ent))
			continue;
		
		if (TF2_IsCarried(ent))
			continue;
		
		if (TF2_HasSapper(ent))
			continue;
		
		float distance = GetVectorDistance(origin, GetAbsOrigin(ent));
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEnt = ent;
		}
	}
	
	return bestEnt;
}

int GetNearestEnemyCount(int client, const float max_distance, bool bIgnoreUber = false)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	int myTeam = GetClientTeam(client);
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (GetClientTeam(i) == myTeam)
			continue;
		
		//Usually not a threat
		if (IsSentryBusterRobot(i))
			continue;
		
		if (bIgnoreUber && TF2_IsInvulnerable(i))
			continue;
		
		if (TF2_IsStealthed(i) && !IsCloakedPlayerExposed(i))
			continue;
		
		if (GetVectorDistance(WorldSpaceCenter(i), origin) <= max_distance)
			count++;
	}
	
	return count;
}

//CBaseObject::FindBuildPointOnPlayer
bool IsPlayerSappable(int client)
{
	if (TF2_IsPlayerInCondition(client, TFCond_Sapped))
		return false;
	
	if (TF2_IsInvulnerable(client))
		return false;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Bonked))
		return false;
	
	return true;
}

int GetNearestSappablePlayer(int client, const float max_distance, bool bGiantsOnly = false, TFClassType class = TFClass_Unknown, float speedCheck = 0.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	TFTeam enemyTeam = GetPlayerEnemyTeam(client);
	float bestDistance = 999999.0;
	int bestEntity = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != enemyTeam)
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		if (bGiantsOnly && !TF2_IsMiniBoss(i))
			continue;
		
		if (class > TFClass_Unknown && TF2_GetPlayerClass(i) != class)
			continue;
		
		//Not fast enough
		if (speedCheck > 0.0 && GetEntPropFloat(i, Prop_Send, "m_flMaxspeed") < speedCheck)
			continue;
		
		if (!IsPlayerSappable(i))
			continue;
		
		float distance = GetVectorDistance(WorldSpaceCenter(i), origin);
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = i;
		}
	}
	
	return bestEntity;
}

int GetFarthestSappablePlayer(int client, const float max_distance, bool bGiantsOnly = false, TFClassType class = TFClass_Unknown, float speedCheck = 0.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	TFTeam enemyTeam = GetPlayerEnemyTeam(client);
	float bestDistance = 0.0;
	int bestEntity = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != enemyTeam)
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		if (bGiantsOnly && !TF2_IsMiniBoss(i))
			continue;
		
		if (class > TFClass_Unknown && TF2_GetPlayerClass(i) != class)
			continue;
		
		if (speedCheck > 0.0 && GetEntPropFloat(i, Prop_Send, "m_flMaxspeed") < speedCheck)
			continue;
		
		if (!IsPlayerSappable(i))
			continue;
		
		float distance = GetVectorDistance(WorldSpaceCenter(i), origin);
		
		if (distance >= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = i;
		}
	}
	
	return bestEntity;
}

int GetEnemyPlayerNearestToPosition(int client, float position[3], const float max_distance)
{
	TFTeam enemyTeam = GetPlayerEnemyTeam(client);
	float bestDistance = 999999.0;
	int bestEntity = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != enemyTeam)
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		float distance = GetVectorDistance(WorldSpaceCenter(i), position);
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = i;
		}
	}
	
	return bestEntity;
}

int GetControlPointByID(int pointID)
{
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "team_control_point")) != -1)
		if (GetEntProp(ent, Prop_Data, "m_iPointIndex") == pointID)
			return ent;
	
	return -1;
}

//Return a capture area trigger associated with a control point that the team can capture
int GetCapturableAreaTrigger(TFTeam team)
{
	int trigger = -1;
	
	//Look for a capture area trigger associated with a control point
	while ((trigger = FindEntityByClassname(trigger, "trigger_*")) != -1)
	{
		//Only want capture areas
		if (!HasEntProp(trigger, Prop_Data, "CTriggerAreaCaptureCaptureThink"))
			continue;
		
		//Ignore disabled triggers
		if (GetEntProp(trigger, Prop_Data, "m_bDisabled"))
			continue;
		
		//Apparently some community maps don't disable the trigger when capped
		char sCapPointName[32]; GetEntPropString(trigger, Prop_Data, "m_iszCapPointName", sCapPointName, sizeof(sCapPointName));
		
		//Trigger has no point associated with it
		if (strlen(sCapPointName) < 3)
			continue;
		
		//Now find the matching control point
		int point = -1;
		
		while ((point = FindEntityByClassname(point, "team_control_point")) != -1)
		{
			int iPointIndex = GetEntProp(point, Prop_Data, "m_iPointIndex");
			
			if (!TFGameRules_TeamMayCapturePoint(team, iPointIndex))
				continue;
			
			char sName[32]; GetEntPropString(point, Prop_Data, "m_iName", sName, sizeof(sName));
			
			//Found the match?
			if (strcmp(sName, sCapPointName, false) == 0)
				return trigger;
		}
	}
	
	return -1;
}

int GetNearestSappablePlayerHealingSomeone(int client, const float max_distance, bool bGiantsOnly = false, TFClassType class = TFClass_Unknown, float speedCheck = 0.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	TFTeam enemyTeam = GetPlayerEnemyTeam(client);
	float bestDistance = 999999.0;
	int bestEntity = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_GetClientTeam(i) != enemyTeam)
			continue;
		
		if (IsSentryBusterRobot(i))
			continue;
		
		if (bGiantsOnly && !TF2_IsMiniBoss(i))
			continue;
		
		if (class > TFClass_Unknown && TF2_GetPlayerClass(i) != class)
			continue;
		
		if (speedCheck > 0.0 && GetEntPropFloat(i, Prop_Send, "m_flMaxspeed") < speedCheck)
			continue;
		
		if (!IsPlayerHealingSomething(i))
			continue;
		
		if (!IsPlayerSappable(i))
			continue;
		
		float distance = GetVectorDistance(WorldSpaceCenter(i), origin);
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEntity = i;
		}
	}
	
	return bestEntity;
}

bool IsPlayerHealingSomething(int client)
{
	int weapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (weapon == -1)
		return false;
	
	return TF2Util_GetWeaponID(weapon) == TF_WEAPON_MEDIGUN && GetEntPropEnt(weapon, Prop_Send, "m_hHealingTarget") != -1;
}

//CTFRevolver::CanHeadshot
bool CanRevolverHeadshot(int weapon)
{
	return TF2Attrib_HookValueInt(0, "set_weapon_mode", weapon) == 1;
}

bool IsPlayerMoving(int client)
{
	float vec[3]; CBaseEntity(client).GetAbsVelocity(vec);
	
	return !IsZeroVector(vec);
}

bool CanWeaponAddUberOnHit(int weapon)
{
	return TF2Attrib_HookValueFloat(0.0, "add_onhit_ubercharge", weapon) > 0.0;
}

bool IsCloakedPlayerExposed(int client)
{
	if (TF2_IsPlayerInCondition(client, TFCond_OnFire))
		return true;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Jarated))
		return true;
	
	if (TF2_IsPlayerInCondition(client, TFCond_CloakFlicker))
		return true;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Bleeding))
		return true;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Milked))
		return true;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Gas))
		return true;
	
	return false;
}

int GetHealerOfPlayer(int client, bool bPlayerOnly = false)
{
	for (int i = 0; i < TF2_GetNumHealers(client); i++)
	{
		int healer = TF2Util_GetPlayerHealer(client, i);
		
		if (healer != -1)
		{
			if (bPlayerOnly && !BaseEntity_IsPlayer(healer))
				continue;
			
			return healer;
		}
	}
	
	return -1;
}

bool IsHealedByObject(int client)
{
	for (int i = 0; i < TF2_GetNumHealers(client); i++)
	{
		int healer = TF2Util_GetPlayerHealer(client, i);
		
		if (!BaseEntity_IsBaseObject(healer))
			continue;
		
		return true;
	}
	
	return false;
}

//Return the only entity we can see, -2 if we can see them both
int FindOnlyOneVisibleEntity(int client, int ent1, int ent2)
{
	if (!IsLineOfFireClearEntity(client, GetEyePosition(client), ent1))
	{
		return ent2;
	}
	
	if (!IsLineOfFireClearEntity(client, GetEyePosition(client), ent2))
	{
		return ent1;
	}
	
	return -2;
}

int GetNearestCurrencyPack(int client, const float max_distance = 999999.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	float bestDistance = 999999.0;
	int bestEnt = -1;
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "item_currency*")) != -1)
	{
		//This pack has already been distributed to the team
		if (GetEntProp(ent, Prop_Send, "m_bDistributed") == 1)
			continue;
		
		//Wait for it to reach the ground the first
		if (!(GetEntityFlags(ent) & FL_ONGROUND))
			continue;
		
		float distance = GetVectorDistance(origin, GetAbsOrigin(ent));
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEnt = ent;
		}
	}
	
	return bestEnt;
}

bool CanUsePrimayWeapon(int client)
{
	if (TF2_IsPlayerInCondition(client, TFCond_MeleeOnly))
		return false;
	
	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	
	if (weapon == -1)
		return false;
	
	return true;
}

//bool CTFBot::IsLineOfFireClear( const Vector &from, const Vector &to ) const
bool IsLineOfFireClearPosition(int client, const float from[3], const float to[3])
{
	StringMap adtProperties = new StringMap();
	adtProperties.SetValue("m_pPassEnt", client);
	adtProperties.SetValue("m_collisionGroup", COLLISION_GROUP_NONE);
	adtProperties.SetValue("m_iIgnoreTeam", GetClientTeam(client));
	
	TR_TraceRayFilter(from, to, MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_TFBot, adtProperties);
	adtProperties.Close();
	
	return !TR_DidHit();
}

//bool CTFBot::IsLineOfFireClear( const Vector &from, CBaseEntity *who ) const
bool IsLineOfFireClearEntity(int client, const float from[3], int who)
{
	StringMap adtProperties = new StringMap();
	adtProperties.SetValue("m_pPassEnt", client);
	adtProperties.SetValue("m_collisionGroup", COLLISION_GROUP_NONE);
	adtProperties.SetValue("m_iIgnoreTeam", GetClientTeam(client));
	
	TR_TraceRayFilter(from, WorldSpaceCenter(who), MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_TFBot, adtProperties);
	adtProperties.Close();
	
	return !TR_DidHit() || TR_GetEntityIndex() == who;
}

bool GetBombInfo(BombInfo_t info)
{
	int iAreaCount = TheNavAreas.Count;

	//Check that this map has any nav areas
	if (iAreaCount <= 0)
		return false;

	float hatch_dist = 0.0;
	
	for (int i = 0; i < (iAreaCount - 1); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		//Skip spawn areas
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
		{
			//PrintToServer("Skip spawn area.. #%i", area.GetID());
			continue;
		}
		
		float m_flBombTargetDistance = GetTravelDistanceToBombTarget(area);
		
		hatch_dist = MaxFloat(MaxFloat(m_flBombTargetDistance, hatch_dist), 0.0);
	}
	
	int closest_flag = INVALID_ENT_REFERENCE;
	float closest_flag_pos[3];
	
	int flag = -1;
	while ((flag = FindEntityByClassname(flag, "item_teamflag")) != -1)
	{
		//Ignore bombs not in play
		if (GetEntProp(flag, Prop_Send, "m_nFlagStatus") == TF_FLAGINFO_HOME)
			continue;
		
		//Ignore bombs not on our team
		//if (GetEntProp(flag, Prop_Send, "m_iTeamNum") != view_as<int>(TFTeam_Blue))
			//continue;
			
		float flag_pos[3];
		
		int owner = BaseEntity_GetOwnerEntity(flag);
		
		if (IsValidClientIndex(owner))
		{
			flag_pos = GetAbsOrigin(owner);
		}
		else
		{
			flag_pos = WorldSpaceCenter(flag);
		}
		
		CTFNavArea area = view_as<CTFNavArea>(TheNavMesh.GetNearestNavArea(flag_pos));
		
		if (area == NULL_AREA)
			continue;
		
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		float m_flBombTargetDistance = GetTravelDistanceToBombTarget(area);
		
		if (m_flBombTargetDistance < hatch_dist) 
		{
			closest_flag = flag;
			hatch_dist = m_flBombTargetDistance;
			closest_flag_pos = flag_pos;
		}
	}
	
	//float range_back = FindConVar("tf_bot_engineer_mvm_sentry_hint_bomb_backward_range").FloatValue;
	//float range_fwd  = FindConVar("tf_bot_engineer_mvm_sentry_hint_bomb_forward_range").FloatValue;
	
	float range_fwd   = 2300.0;
	float range_back  = 1000.0;
	
	info.vPosition = closest_flag_pos;
	info.flMaxBattleFront = hatch_dist + range_back;
	info.flMinBattleFront = hatch_dist - range_fwd;
	
	return (closest_flag != INVALID_ENT_REFERENCE);
}

bool IsUpgradeStationEnabled(int station)
{
	static int iOffsetIsEnabled = -1;
	
	//m_bIsEnabled
	if (iOffsetIsEnabled == -1)
		iOffsetIsEnabled = FindDataMapInfo(station, "m_nStartDisabled") + 28;
	
	return GetEntData(station, iOffsetIsEnabled, 1);
}

float[] GetAbsAngles(int entity)
{
	float vec[3]; CBaseEntity(entity).GetAbsAngles(vec);
	
	return vec;
}

CNavArea PickBuildArea(int client, float SentryRange = 1300.0)
{
	int iAreaCount = TheNavAreas.Count;

	//Check that this map has any nav areas
	if (iAreaCount <= 0)
		return NULL_AREA;
	
	BombInfo_t bombinfo;
	
	if (!GetBombInfo(bombinfo)) 
	{	
		return PickBuildAreaPreRound(client);
	}
	
	float vecTargetPos[3];
	vecTargetPos[0] = bombinfo.vPosition[0];
	vecTargetPos[1] = bombinfo.vPosition[1];
	vecTargetPos[2] = bombinfo.vPosition[2] + 40.0;
	
	CTFNavArea bombArea = TheNavMesh.GetNearestNavArea(vecTargetPos, false, 90000.0, false, true, TEAM_ANY);
	
	if (bombArea == NULL_AREA)
	{
		return NULL_AREA;
	}
	
	if (bombArea.HasAttributeTF(BLUE_SPAWN_ROOM) || bombArea.HasAttributeTF(RED_SPAWN_ROOM))
	{
		return NULL_AREA;
	}

	//Areas forward of the bomb within some distance and visible to bomb.
	ArrayList ForwardVisibleAreas = new ArrayList();
	//Areas forward of the bomb but not necessarily visible.
	ArrayList ForwardAreas        = new ArrayList();
	//Areas visible to the bomb but not nescessarily forward of it.
	ArrayList VisibleAreasAround  = new ArrayList();
	
	//Loop all nav areas
	for (int i = 0; i < iAreaCount; i++)
	{	
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		if (area == NULL_AREA)
			continue;
		
		//Area in spawn
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		//TODO
		//Better solution because this will break on all non mvm maps.
		//Most likely areachable area
		if (!area.HasAttributeTF(BOMB_DROP))
			continue;
		
		float m_flBombTargetDistanceAtArea = GetTravelDistanceToBombTarget(area);
		float m_flBombTargetDistanceAtBomb = GetTravelDistanceToBombTarget(bombArea);
		
		if (m_flBombTargetDistanceAtArea < 180.0)
			continue;
		
		float areaCenter[3]; area.GetCenter(areaCenter);
		areaCenter[2] += 50.0;
		
		float flAreaDistanceToBomb = GetVectorDistance(areaCenter, vecTargetPos);
		
		if (flAreaDistanceToBomb >= SentryRange)
			continue;
		
		bool bAreaVisibleToBomb = area.IsEntirelyVisible(vecTargetPos);
		
		if (bAreaVisibleToBomb)
		{
			VisibleAreasAround.Push(area);
		}
		
		if (m_flBombTargetDistanceAtBomb > m_flBombTargetDistanceAtArea)
		{
			if (flAreaDistanceToBomb <= SentryRange * GetRandomFloat(0.8, 1.75) && bAreaVisibleToBomb)
			{
				ForwardVisibleAreas.Push(area);
			}
			
			ForwardAreas.Push(area);
		}
	}
	
	PrintToServer("PickBuildArea %i ForwardVisibleAreas | %i ForwardAreas | %i VisibleAreasAroundBomb", ForwardVisibleAreas.Length, ForwardAreas.Length, VisibleAreasAround.Length);
	
	CNavArea randomArea = NULL_AREA;
	
	if (ForwardVisibleAreas.Length     > 0) randomArea = ForwardVisibleAreas.Get(GetRandomInt(0, ForwardVisibleAreas.Length - 1));
	else if (ForwardAreas.Length       > 0) randomArea =        ForwardAreas.Get(GetRandomInt(0, ForwardAreas.Length        - 1));
	else if (VisibleAreasAround.Length > 0) randomArea =  VisibleAreasAround.Get(GetRandomInt(0, VisibleAreasAround.Length  - 1));
	
	ForwardVisibleAreas.Close();
	ForwardAreas.Close();
	VisibleAreasAround.Close();
	
	return randomArea;
}

CNavArea PickBuildAreaPreRound(int client, float SentryRange = 1300.0)
{
	int iAreaCount = TheNavAreas.Count;

	//Check that this map has any nav areas
	if (iAreaCount <= 0)
		return NULL_AREA;
	
	ArrayList EnemySpawnExits = new ArrayList();	

	//Collect enemy exit areas after spawn door.
	for (int i = 0; i < iAreaCount; i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		if (area == NULL_AREA)
			continue;
		
		//BLOCKED
		if (area.HasAttributeTF(BLOCKED))
			continue;
		
		//BLOCKED
		if (area.HasAttributeTF(BLOCKED_AFTER_POINT_CAPTURE))
			continue;
		
		//BLOCKED
		if (area.HasAttributeTF(BLOCKED_UNTIL_POINT_CAPTURE))
			continue;
		
		//Area in spawn but not an exit
		if (GetTravelDistanceToBombTarget(area) <= 0.0 && !area.HasAttributeTF(SPAWN_ROOM_EXIT))
			continue;
		
		//Area not an enemy spawn room exit
		if (GetPlayerEnemyTeam(client) == TFTeam_Blue && !area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		//Area not an enemy spawn room exit
		if (GetPlayerEnemyTeam(client) == TFTeam_Red && !area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		float flLowestBombTargetDistance = 999999.0;
		CNavArea bestConnection = NULL_AREA;
		
		//Check spawn exit connections 
		for (NavDirType dir = NORTH; dir < NUM_DIRECTIONS; dir++)
		{			
			//Only connections with BOMB_DROP attribute are considered good.
			for (int iConnection = 0; iConnection < area.GetAdjacentCount(dir); iConnection++)
			{			
				CTFNavArea adjArea = area.GetAdjacentArea(dir, iConnection);
				
				//Area still in spawn... BAD
				if (adjArea.HasAttributeTF(BLUE_SPAWN_ROOM) || adjArea.HasAttributeTF(RED_SPAWN_ROOM))
					continue;
				
				float flBombTargetDistance = GetTravelDistanceToBombTarget(adjArea);
				
				//Area most likely in spawn
				if (flBombTargetDistance <= 0.0)
					continue;
				
				if (flBombTargetDistance <= flLowestBombTargetDistance)
				{
					bestConnection = adjArea;
					flLowestBombTargetDistance = flBombTargetDistance;
				}
			}
		}
		
		if (bestConnection != NULL_AREA)
		{
			EnemySpawnExits.Push(bestConnection);
			//g_hAreasToDraw.Push(bestConnection);
		}
	}
	
	//We've failed men.
	if (EnemySpawnExits.Length <= 0)
	{
		EnemySpawnExits.Close();
		return NULL_AREA;
	}
	
	//Random valid exit point.
	CNavArea RandomEnemySpawnExit = EnemySpawnExits.Get(GetRandomInt(0, EnemySpawnExits.Length - 1));
	
	EnemySpawnExits.Close();
	
	//Search outward of the random exit untill we are some distance away.
	float vecExitCenter[3];
	RandomEnemySpawnExit.GetCenter(vecExitCenter);
	vecExitCenter[2] += 45.0;
	
	//PrintToServer("%f %f %f", vecExitCenter[0], vecExitCenter[1], vecExitCenter[2]);

	ArrayList AreasCloser                  = new ArrayList();	//Not necessarily visible but still <= 3000.0
	ArrayList VisibleAreas                 = new ArrayList();
	ArrayList VisibleAreasAfterSentryRange = new ArrayList();	//>= SentryRange
	
	for (int i = 0; i < iAreaCount; i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		if (area == NULL_AREA)
			continue;
		
		if (area.HasAttributeTF((BLUE_SPAWN_ROOM | RED_SPAWN_ROOM)))
			continue;
		
		//TODO
		//Better solution because this will break on all non mvm maps.
		if (!area.HasAttributeTF(BOMB_DROP))
			continue;
			
		float center[3]; area.GetCenter(center);
		
		float flDistance = GetVectorDistance(center, vecExitCenter);
		
		if (flDistance <= SentryRange)
			AreasCloser.Push(area);
		
		if (!area.IsEntirelyVisible(vecExitCenter))
			continue;
		
		if (flDistance > (SentryRange * 0.75) && flDistance <= SentryRange * 1.25)
		{
			VisibleAreasAfterSentryRange.Push(area);
			//g_hAreasToDraw.Push(area);
		}
		
		if (flDistance <= SentryRange)
			VisibleAreasAfterSentryRange.Push(area);
		
		VisibleAreas.Push(area);
	}
	
	//PrintToServer("PickBuildAreaPreRound %i VisibleAreas | %i VisibleAreasAfterSentryRange | %i AreasCloser", VisibleAreas.Length, VisibleAreasAfterSentryRange.Length, AreasCloser.Length);
	
	CNavArea bestArea = NULL_AREA;
	
	if (VisibleAreasAfterSentryRange.Length > 0) bestArea = VisibleAreasAfterSentryRange.Get(GetRandomInt(0, VisibleAreasAfterSentryRange.Length - 1));
	else if (VisibleAreas.Length > 0)            bestArea =                 VisibleAreas.Get(GetRandomInt(0, VisibleAreas.Length                 - 1));
	else if (AreasCloser.Length > 0)             bestArea =                  AreasCloser.Get(GetRandomInt(0, AreasCloser.Length                  - 1));
	
	AreasCloser.Close();
	VisibleAreas.Close();
	VisibleAreasAfterSentryRange.Close();
	
	//DrawArea(bestArea, false, 6.0);
	return bestArea;
}

stock bool DoesAnyPlayerUseThisName(const char[] name)
{
	char playerName[MAX_NAME_LENGTH];
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientConnected(i) && GetClientName(i, playerName, sizeof(playerName)) && StrEqual(playerName, name, false))
			return true;
	
	return false;
}

stock int ReadInt(Address pAddr)
{
	if (pAddr == Address_Null)
		return -1;
	
	return LoadFromAddress(pAddr, NumberType_Int32);
}

//Somewhat borrowed from [L4D2] Survivor Bot AI Improver
stock void SnapViewToPosition(int iClient, const float fPos[3])
{
	float clientEyePos[3]; GetClientEyePosition(iClient, clientEyePos);
	
	float fDesiredDir[3]; MakeVectorFromPoints(clientEyePos, fPos, fDesiredDir);
	GetVectorAngles(fDesiredDir, fDesiredDir);

	float clientEyeAng[3]; GetClientEyeAngles(iClient, clientEyeAng);
	
	float fEyeAngles[3];
	fEyeAngles[0] = (clientEyeAng[0] + NormalizeAngle(fDesiredDir[0] - clientEyeAng[0]));
	fEyeAngles[1] = (clientEyeAng[1] + NormalizeAngle(fDesiredDir[1] - clientEyeAng[1]));
	fEyeAngles[2] = 0.0;

	TeleportEntity(iClient, NULL_VECTOR, fEyeAngles, NULL_VECTOR);
}

stock float NormalizeAngle(float fAngle)
{
	fAngle = (fAngle - RoundToFloor(fAngle / 360.0) * 360.0);
	if (fAngle > 180.0)fAngle -= 360.0;
	else if (fAngle < -180.0)fAngle += 360.0;
	return fAngle;
}

stock bool IsValidClientIndex(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client);
}

stock bool IsBaseBoss(int entity)
{
	return HasEntProp(entity, Prop_Send, "m_lastHealthPercentage");
}

stock bool IsPlayerReady(int client)
{
	return view_as<bool>(GameRules_GetProp("m_bPlayerReady", 1, client));
}

stock bool IsMeleeWeapon(int entity)
{
	//THINKFUNC Smack
	return HasEntProp(entity, Prop_Data, "CTFWeaponBaseMeleeSmack");
}

stock bool IsZeroVector(float origin[3])
{
	return origin[0] == NULL_VECTOR[0] && origin[1] == NULL_VECTOR[1] && origin[2] == NULL_VECTOR[2];
}

stock void SetPlayerReady(int client, bool state)
{
	FakeClientCommand(client, "tournament_player_readystate %d", state);
}

stock bool IsPluginMvMCreditsLoaded()
{
	//tf_mvm_credits
	return FindConVar("sm_mvmcredits_version") != null;
}

stock bool IsPluginRTDLoaded()
{
	//rtd
	return FindConVar("sm_rtd2_version") != null;
}

stock void UseActionSlotItem(int client)
{
	KeyValues kv = new KeyValues("use_action_slot_item_server");
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

stock void PlayerBuyback(int client)
{
	FakeClientCommand(client, "td_buyback");
}

//From stocksoup/entity_tools.inc
stock bool ParentEntity(int parent, int attachment, const char[] attachPoint = "",
		bool maintainOffset = false) {
	SetVariantString("!activator");
	AcceptEntityInput(attachment, "SetParent", parent, attachment, 0);
	
	if (strlen(attachPoint) > 0) {
		SetVariantString(attachPoint);
		AcceptEntityInput(attachment,
				maintainOffset? "SetParentAttachmentMaintainOffset" : "SetParentAttachment",
				parent, parent);
	}
}

//TODO: should use an actual call to CBaseEntity::IsDeflectable
stock bool CanBeReflected(int projectile)
{
	char classname[32]; GetEntityClassname(projectile, classname, sizeof(classname));
	
	if (StrEqual(classname, "tf_projectile_arrow", false)
	|| StrEqual(classname, "tf_projectile_ball_ornament", false)
	|| StrEqual(classname, "tf_projectile_cleaver", false)
	|| StrEqual(classname, "tf_projectile_energy_ball", false)
	|| StrEqual(classname, "tf_projectile_flare", false)
	|| StrEqual(classname, "tf_projectile_healing_bolt", false)
	|| StrContains(classname, "tf_projectile_jar", false) != -1
	|| StrEqual(classname, "tf_projectile_pipe", false)
	|| StrEqual(classname, "tf_projectile_rocket", false)
	|| StrEqual(classname, "tf_projectile_sentryrocket", false)
	|| StrEqual(classname, "tf_projectile_stun_ball", false)
	|| StrEqual(classname, "tf_projectile_balloffire", false))
	{
		return true;
	}
	
	return false;
}

stock bool IsItemDefIndexSapper(int itemDefIndex)
{
	switch (itemDefIndex)
	{
		case 735, 736, 810, 831, 933, 1080, 1102:
		{
			return true;
		}
	}
	
	return false;
}

stock float AngleDiff( float destAngle, float srcAngle )
{
	return AngleNormalize(destAngle - srcAngle);
}

stock float AngleNormalize( float angle )
{
	angle = angle - 360.0 * RoundToFloor(angle / 360.0);
	while (angle > 180.0) angle -= 360.0;
	while (angle < -180.0) angle += 360.0;
	return angle;
}

stock float[] GetAbsVelocity(int entity)
{
	float vec[3];

	CBaseEntity(entity).GetAbsVelocity(vec);
	
	return vec;
}

stock float VMX_VectorNormalize(float a1[3])
{
	float flLength = GetVectorLength(a1, true) + 0.0000000001;
	float v4 = (1.0 / SquareRoot(flLength)); 
	float den = v4 * ((3.0 - ((v4 * v4) * flLength)) * 0.5);
	
	ScaleVector(a1, den);
	
	return den * flLength;
}

stock float[] GetEyePosition(int client)
{
	float vec[3]; BaseEntity_EyePosition(client, vec);
	
	return vec;
}

stock float ApproachAngle( float target, float value, float speed )
{
	float delta = AngleDiff(target, value);
	
	if (speed < 0.0) 
		speed = -speed;
	
	if (delta > speed) 
		value += speed;
	else if (delta < -speed) 
		value -= speed;
	else
		value = target;
	
	return AngleNormalize(value);
}

stock float GetCurrentCharge(int iWeapon)
{
	if (!HasEntProp(iWeapon, Prop_Send, "m_flChargeBeginTime"))
		return 0.0;
	
	float flCharge = 0.0;
	
	float flChargeBeginTime = GetEntPropFloat(iWeapon, Prop_Send, "m_flChargeBeginTime");
	
	if (flChargeBeginTime != 0.0)
	{
		flCharge = MinFloat(1.0, GetGameTime() - flChargeBeginTime);
	}
	
	return flCharge;
}

stock bool IsServerFull()
{
	return GetClientCount(false) >= MaxClients;
}

//From stocksoup/memory.inc
stock Address DereferencePointer(Address addr) {
	// maybe someday we'll do 64-bit addresses
	return view_as<Address>(LoadFromAddress(addr, NumberType_Int32));
}

stock void TFBot_NoticeThreat(int tfbot, int threat)
{
	//UpdateDelayedThreatNotices is called in CTFBotTacticalMonitor::Update, but that behavior can be interrupted so we use it here to ensure he's noticed
	OSLib_RunScriptCode(tfbot, _, _, "self.DelayedThreatNotice(EntIndexToHScript(%d),0);self.UpdateDelayedThreatNotices()", threat);
}

stock void PrintToChatTeam(int team, const char[] format, any ...)
{
	char buffer[254];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, sizeof(buffer), format, 3);
			PrintToChat(i, "%s", buffer);
		}
	}
}

stock int GetTeamHumanClientCount(int team)
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
			count++;
	
	return count;
}

/* TODO: remove this as we have a better way to do this
we are only doing this for right now until we can solve a potential issue */
stock int TEMP_GetPlayerMaxHealth(int client)
{
	return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}

//This seems heavily based on PlayerLocomotion::Approach
stock void MovePlayerTowardsGoal(int client, const float vGoal[3], float vVel[3])
{
	//WASD Movement
	float forward3D[3];
	BasePlayer_EyeVectors(client, forward3D);
	
	float vForward[3];
	vForward[0] = forward3D[0];
	vForward[1] = forward3D[1];
	NormalizeVector(vForward, vForward);
	
	float right[3] 
	right[0] = vForward[1];
	right[1] = -vForward[0];

	//PlayerLocomotion::GetFeet
	float vFeet[3]; GetClientAbsOrigin(client, vFeet);
	
	float to[3]; 
	SubtractVectors(vGoal, vFeet, to);

	/*float goalDistance = */
	NormalizeVector(to, to);

	float ahead = GetVectorDotProduct(to, vForward);
	float side  = GetVectorDotProduct(to, right);
	
	const float epsilon = 0.25;

	if (ahead > epsilon)
	{
		//PressForwardButton();
		vVel[0] = PLAYER_SIDESPEED;
	}
	else if (ahead < -epsilon)
	{
		//PressBackwardButton();
		vVel[0] = -PLAYER_SIDESPEED;
	}

	if (side <= -epsilon)
	{
		//PressLeftButton();
		vVel[1] = -PLAYER_SIDESPEED;
	}
	else if (side >= epsilon)
	{
		//PressRightButton();
		vVel[1] = PLAYER_SIDESPEED;
	}
}