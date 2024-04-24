#include <stocklib_officerspy/tf/tf_bot>
#include <stocklib_officerspy/tf/tf_player>
#include <stocklib_officerspy/tf/tf_obj>
#include <stocklib_officerspy/tf/tf_objective_resource>
#include <stocklib_officerspy/tf/stocklib_extra_vscript>
#include <stocklib_officerspy/econ_item_view>

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
	"You're very funny for using my name, %s",
	"You totally stole my name, %s"
};

//Make sure this matches with the eMissionDifficulty enum size
char g_sMissionDifficultyFilePaths[][] =
{
	"",
	"configs/defender_bots_manager/mission_normal.txt",
	"configs/defender_bots_manager/mission_intermediate.txt",
	"configs/defender_bots_manager/mission_advanced.txt",
	"configs/defender_bots_manager/mission_expert.txt",
	"configs/defender_bots_manager/mission_nightmare.txt"
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
			
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 1, _, 0); //OBJ_DISPENSER
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 1, _, 1); //OBJ_TELEPORTER
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 1, _, 2); //OBJ_SENTRYGUN
			SetEntProp(item, Prop_Send, "m_aBuildableObjectTypes", 0, _, 3); //OBJ_ATTACHMENT_SAPPER
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
		LogError("EconItemCreateNoSpawn: Failed to create entity '%s' with item definition %i.", classname, itemDefIndex);
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
	int m_LastDamageType = FindSendPropInfo("CTFPlayer", "m_flMvMLastDamageTime") + 20;
	
	return ReadInt(GetEntityAddress(client) + view_as<Address>(m_LastDamageType));
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
	int iObject = INVALID_ENT_REFERENCE;
	while ((iObject = FindEntityByClassname(iObject, "obj_*")) != -1)
	{
		TFObjectType iObjType = TF2_GetObjectType(iObject);
		
		if(GetEntPropEnt(iObject, Prop_Send, "m_hBuilder") == client && iObjType == type 
		&& !GetEntProp(iObject, Prop_Send, "m_bPlacing")
		&& !GetEntProp(iObject, Prop_Send, "m_bDisposableBuilding"))
		{			
			return iObject;
		}
	}
	
	return iObject;
}

float[] GetAbsOrigin(int client)
{
	// if (client <= 0)
		// return NULL_VECTOR;

	float vec[3]; CBaseEntity(client).GetAbsOrigin(vec);
	
	return vec;
}

float[] GetTurretAngles(int sentry)
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
}

bool IsWeapon(int client, int iWeaponID)
{
	int iWeapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (IsValidEntity(iWeapon))
		return TF2Util_GetWeaponID(iWeapon) == iWeaponID;
	
	return false;
}

bool IsSentryBusterRobot(int client)
{
	//TODO: maybe this could be done better for actual tfbots
	char model[PLATFORM_MAX_PATH]; GetClientModel(client, model, PLATFORM_MAX_PATH);
	
	return StrEqual(model, "models/bots/demo/bot_sentry_buster.mdl");
}

int TF2_FindBotNearestToBombNearestToHatch(int client)
{
	int iBomb = TF2_FindBombNearestToHatch();
	
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

int TF2_FindBombNearestToHatch()
{
	float flOrigin[3]; flOrigin = TF2_GetBombHatchPosition();
	
	float flBestDistance = 999999.0;
	int iBestEntity = -1;
	
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "item_teamflag")) != -1)
	{
		//Ignore bombs not in play
		if (GetEntProp(iEnt, Prop_Send, "m_nFlagStatus") == 0)
			continue;
		
		//Ignore bombs not on blue team.
		if (GetEntProp(iEnt, Prop_Send, "m_iTeamNum") != view_as<int>(TFTeam_Blue))
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

float[] GetAbsAngles(int client)
{
	// if (client <= 0)
		// return NULL_VECTOR;

	float vec[3]; BaseEntity_GetLocalAngles(client, vec);
	
	return vec;
}

bool IsHealedByMedic(int client)
{
	for (int i = 0; i < GetEntProp(client, Prop_Send, "m_nNumHealers"); i++)
	{
		int iHealerIndex = TF2_GetHealerByIndex(client, i);
		
		//Not a player.
		if (!IsValidClientIndex(iHealerIndex))
			continue;
		
		return true;
	}
	
	return false;
}

float[] TF2_GetBombHatchPosition()
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

stock void RefundPlayerUpgrades(int client)
{
	KeyValues kv = new KeyValues("MVM_Respec");
	
	SetEntProp(client, Prop_Send, "m_bInUpgradeZone", 1);	
	FakeClientCommandKeyValues(client, kv);
	SetEntProp(client, Prop_Send, "m_bInUpgradeZone", 0);
	
	delete kv;
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
    {
        return -1;		
    }
    		
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