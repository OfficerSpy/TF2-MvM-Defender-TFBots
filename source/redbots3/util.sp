#include <stocklib_officerspy/tf/tf_bot>
#include <stocklib_officerspy/tf/tf_player>
#include <stocklib_officerspy/tf/tf_obj>
#include <stocklib_officerspy/tf/tf_objective_resource>
#include <stocklib_officerspy/tf/stocklib_extra_vscript>
#include <stocklib_officerspy/econ_item_view>
#include <stocklib_officerspy/tf/tf_weaponbase>
#include <stocklib_officerspy/tf/entity_capture_flag>

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

#define SNIPER_REACTION_TIME	0.5

enum //medigun_resist_types_t
{
	MEDIGUN_BULLET_RESIST = 0,
	MEDIGUN_BLAST_RESIST,
	MEDIGUN_FIRE_RESIST,
	MEDIGUN_NUM_RESISTS
};

enum //medigun_weapontypes_t
{
	MEDIGUN_STANDARD = 0,
	MEDIGUN_UBER,
	MEDIGUN_QUICKFIX,
	MEDIGUN_RESIST
};

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
};

enum eMissionDifficulty
{
	MISSION_UNKNOWN = 0,
	MISSION_NORMAL,
	MISSION_INTERMEDIATE,
	MISSION_ADVANCED,
	MISSION_EXPERT,
	MISSION_NIGHTMARE,
	MISSION_MAX_COUNT
};

enum
{
	STATS_CREDITS_DROPPED = 0,
	STATS_CREDITS_ACQUIRED,
	STATS_CREDITS_BONUS,
	STATS_PLAYER_DEATHS,
	STATS_BUYBACKS
};

char g_sPlayerUseMyNameResponse[][] =
{
	"You're very funny for using my name.",
	"You totally stole my name."
};

//NOTE: Make sure this matches with the eMissionDifficulty enum size
char g_sMissionDifficultyFilePaths[][] =
{
	"",
	"configs/defender_bots_manager/mission/mission_normal.txt",
	"configs/defender_bots_manager/mission/mission_intermediate.txt",
	"configs/defender_bots_manager/mission/mission_advanced.txt",
	"configs/defender_bots_manager/mission/mission_expert.txt",
	"configs/defender_bots_manager/mission/mission_nightmare.txt"
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

void RefundPlayerUpgrades(int client)
{
	KeyValues kv = new KeyValues("MVM_Respec");
	
	TF2_SetInUpgradeZone(client, true);
	FakeClientCommandKeyValues(client, kv);
	TF2_SetInUpgradeZone(client, false);
	
	delete kv;
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
		char serverClassname[64]; GetEntityNetClass(item, serverClassname, sizeof(serverClassname));
		SetEntData(item, FindSendPropInfo(serverClassname, "m_iEntityQuality"), quality);
		SetEntData(item, FindSendPropInfo(serverClassname, "m_iEntityLevel"), level);
		
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
	
	if (!IsValidEntity(iWeapon))
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

int GetResistType(int client)
{
	return GetEntProp(BaseCombatCharacter_GetActiveWeapon(client), Prop_Send, "m_nChargeResistType");
}

int GetLastDamageType(int client)
{
	static int offset = -1;
	
	if (offset == -1)
		offset = FindSendPropInfo("CTFPlayer", "m_flMvMLastDamageTime") + 20; //m_LastDamageType
	
	// return ReadInt(GetEntityAddress(client) + view_as<Address>(offset));
	return GetEntData(client, offset);
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
	
	if (!IsValidEntity(iWeapon))
		return false;
	
	switch(TF2Util_GetWeaponID(iWeapon))
	{
		case TF_WEAPON_SNIPERRIFLE:         return true;
		case TF_WEAPON_SNIPERRIFLE_DECAP:   return true;
		case TF_WEAPON_SNIPERRIFLE_CLASSIC: return true;
	}
	
	return false;
}

void TF2_DetonateObjectsOfType(int client, TFObjectType type)
{
	int iObject = -1;
	while ((iObject = FindEntityByClassname(iObject, "obj_*")) != -1)
	{
		TFObjectType iObjType = TF2_GetObjectType(iObject);
		if(GetEntPropEnt(iObject, Prop_Send, "m_hBuilder") == client && iObjType == type)
		{
			SetVariantInt(5000);
			AcceptEntityInput(iObject, "RemoveHealth", client);
		}
	}
}

int TF2_GetObject(int client, TFObjectType type)
{
	int iEnt = -1;
	
	while ((iEnt = FindEntityByClassname(iEnt, "obj_*")) != -1)
	{
		if (TF2_GetBuilder(iEnt) != client)
			continue;
		
		if (TF2_GetObjectType(iEnt) != type)
			continue;
		
		if (TF2_IsPlacing(iEnt))
			continue;
		
		if (TF2_IsDisposableBuilding(iEnt))
			continue;
		
		return iEnt;
	}
	
	return iEnt;
}

float[] GetAbsOrigin(int client)
{
	// if (client <= 0)
		// return NULL_VECTOR;

	float vec[3]; CBaseEntity(client).GetAbsOrigin(vec);
	
	return vec;
}

/* float[] GetTurretAngles(int sentry)
{
	// if (!IsBaseObject(sentry))
		// return NULL_VECTOR;
	
	float angle[3];
	
	int offset = FindSendPropInfo("CObjectSentrygun", "m_iAmmoRockets");
	int iAngleOffset = (offset - 36); //m_vecCurAngles
	
	angle[0] = GetEntDataFloat(sentry, iAngleOffset + 0); //m_vecCurAngles.x
	angle[1] = GetEntDataFloat(sentry, iAngleOffset + 4); //m_vecCurAngles.y
	angle[2] = GetEntDataFloat(sentry, iAngleOffset + 8); //m_vecCurAngles.z
	
	return angle;
} */

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
		
		if (TF2_GetClientTeam(i) != GetEnemyTeamOfPlayer(client))
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

/* float[] GetAbsAngles(int client)
{
	// if (client <= 0)
		// return NULL_VECTOR;

	float vec[3]; BaseEntity_GetLocalAngles(client, vec);
	
	return vec;
} */

int SelectRandomReachableEnemy(int actor)
{
	TFTeam opposingTFTeam = GetEnemyTeamOfPlayer(actor);
	
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

float[] GetBombHatchPosition()
{
	float flOrigin[3];

	int iHole = FindEntityByClassname(-1, "func_capturezone");
	
	if (IsValidEntity(iHole))
		flOrigin = WorldSpaceCenter(iHole);
	
	return flOrigin;
}

TFTeam GetEnemyTeamOfPlayer(int client)
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
	
	int total = GetEntProp(ent, Prop_Send, "m_runningTotalWaveStats", _, STATS_CREDITS_ACQUIRED)
	total += GetEntProp(ent, Prop_Send, "m_previousWaveStats", _, STATS_CREDITS_ACQUIRED)
	total += GetEntProp(ent, Prop_Send, "m_currentWaveStats", _, STATS_CREDITS_ACQUIRED);
	
	if (withBonus)
	{
		total += GetEntProp(ent, Prop_Send, "m_runningTotalWaveStats", _, STATS_CREDITS_BONUS)
		total += GetEntProp(ent, Prop_Send, "m_previousWaveStats", _, STATS_CREDITS_BONUS)
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
	TFTeam enemyTeam = GetEnemyTeamOfPlayer(client);
	
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
	
	TFTeam enemyTeam = GetEnemyTeamOfPlayer(client);
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
	
	TFTeam enemyTeam = GetEnemyTeamOfPlayer(client);
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
	TFTeam enemyTeam = GetEnemyTeamOfPlayer(client);
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

//NOTE: not ideal, as a lot of maps just place the control point in the air
/* int GetNearestDefendableControlPoint(int client, const float max_distance = 999999.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	int myTeam = GetClientTeam(client);
	
	float bestDistance = 999999.0;
	int bestEnt = -1;
	
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "team_control_point")) != -1)
	{
		//My team does not own it
		if (BaseEntity_GetTeamNumber(ent) != myTeam)
			continue;
		
		//Cannot be captured right now
		if (GetEntProp(ent, Prop_Data, "m_bLocked") == 1)
			continue;
		
		float distance = GetVectorDistance(origin, GetAbsOrigin(ent));
		
		if (distance <= bestDistance && distance <= max_distance)
		{
			bestDistance = distance;
			bestEnt = ent;
		}
	}
	
	return bestEnt;
} */

int GetDefendablePointTrigger(TFTeam team)
{
	int trigger = -1;
	
	//Look for a trigger_timer_door associated with a control point
	while ((trigger = FindEntityByClassname(trigger, "trigger_timer_door")) != -1)
	{		
		//Ignore disabled triggers
		if (GetEntProp(trigger, Prop_Data, "m_bDisabled") == 1)
			continue;
		
		//Apparently some community maps don't disable the trigger when capped
		char cpname[32]; GetEntPropString(trigger, Prop_Data, "m_iszCapPointName", cpname, sizeof(cpname));
		
		//Trigger has no point associated with it
		if (strlen(cpname) < 3)
			continue;
		
		//Now find the matching control point
		int point = -1;
		char targetname[32];
		
		while ((point = FindEntityByClassname(point, "team_control_point")) != -1)
		{
			GetEntPropString(point, Prop_Data, "m_iName", targetname, sizeof(targetname));
			
			//Found the match
			if (strcmp(targetname, cpname, false) == 0)
				if (BaseEntity_GetTeamNumber(point) == view_as<int>(team))
					return trigger;
		}
	}
	
	return -1;
}

int GetNearestSappablePlayerHealingSomeone(int client, const float max_distance, bool bGiantsOnly = false, TFClassType class = TFClass_Unknown, float speedCheck = 0.0)
{
	float origin[3]; GetClientAbsOrigin(client, origin);
	
	TFTeam enemyTeam = GetEnemyTeamOfPlayer(client);
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
	if (!TF2_IsLineOfFireClear4(client, ent1))
	{
		return ent2;
	}
	
	if (!TF2_IsLineOfFireClear4(client, ent2))
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

stock int GetTeamHumanClientCount(int team)
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
			count++;
	
	return count;
}

//From stocksoup/memory.inc
stock Address DereferencePointer(Address addr) {
	// maybe someday we'll do 64-bit addresses
	return view_as<Address>(LoadFromAddress(addr, NumberType_Int32));
}