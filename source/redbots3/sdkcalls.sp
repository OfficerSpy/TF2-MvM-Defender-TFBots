static Handle m_hPostInventoryApplication;
static Handle m_hSetMission;
static Handle m_hGetMaxAmmo;
static Handle m_hGetNextThink;
static Handle m_hRealizeSpy;
static Handle m_hHasAmmo;
static Handle m_hGetAmmoCount;
static Handle m_hClip1;
static Handle m_hFinishedBuilding;

#if defined METHOD_MVM_UPGRADES
static Handle m_hGEconItemSchema;
static Handle m_hGetAttributeDefinitionByName;
static Handle m_hCanUpgradeWithAttrib;
static Handle m_hGetCostForUpgrade;
static Handle m_hGetUpgradeTier;
static Handle m_hIsUpgradeTierEnabled;
#endif


bool InitSDKCalls(GameData hGamedata)
{
	int failCount = 0;
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFPlayer::PostInventoryApplication");
	if ((m_hPostInventoryApplication = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFPlayer::PostInventoryApplication!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFBot::SetMission");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	if ((m_hSetMission = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFBot::SetMission!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFPlayer::GetMaxAmmo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hGetMaxAmmo = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFPlayer::GetMaxAmmo!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CBaseEntity::GetNextThink");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	if ((m_hGetNextThink = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CBaseEntity::GetNextThink!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFBot::RealizeSpy");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	if ((m_hRealizeSpy = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFBot::RealizeSpy!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Virtual, "CBaseCombatWeapon::HasAmmo");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
	if ((m_hHasAmmo = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CBaseCombatWeapon::HasAmmo!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Virtual, "CBaseCombatCharacter::GetAmmoCount");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hGetAmmoCount = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFPlayer::GetAmmoCount!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Virtual, "CTFWeaponBase::Clip1");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hClip1 = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFWeaponBase::Clip1!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Virtual, "CBaseObject::FinishedBuilding");
	if ((m_hFinishedBuilding = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CBaseObject::FinishedBuilding!");
		failCount++;
	}
	
#if defined METHOD_MVM_UPGRADES
	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "GEconItemSchema");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hGEconItemSchema = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for GEconItemSchema!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CEconItemSchema::GetAttributeDefinitionByName");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hGetAttributeDefinitionByName = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CEconItemSchema::GetAttributeDefinitionByName!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFGameRules::CanUpgradeWithAttrib");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
	if ((m_hCanUpgradeWithAttrib = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFGameRules::CanUpgradeWithAttrib!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFGameRules::GetCostForUpgrade");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hGetCostForUpgrade = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFGameRules::GetCostForUpgrade!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFGameRules::GetUpgradeTier");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((m_hGetUpgradeTier = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFGameRules::GetUpgradeTier!");
		failCount++;
	}
	
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(hGamedata, SDKConf_Signature, "CTFGameRules::IsUpgradeTierEnabled");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
	if ((m_hIsUpgradeTierEnabled = EndPrepSDKCall()) == null)
	{
		LogError("Failed to create SDKCall for CTFGameRules::IsUpgradeTierEnabled!");
		failCount++;
	}
#endif
	
	if (failCount > 0)
	{
		LogError("InitSDKCalls: GameData file has %d problems!", failCount);
		return false;
	}
	
	return true;
}

void PostInventoryApplication(int client)
{
	SDKCall(m_hPostInventoryApplication, client);
}

void SetMission(int client, MissionType mission, bool resetBehaviorSystem = true)
{
	SDKCall(m_hSetMission, client, mission, resetBehaviorSystem);
}

int GetMaxAmmo(int client, int iAmmoIndex, int iClassIndex = -1)
{
	return SDKCall(m_hGetMaxAmmo, client, iAmmoIndex, iClassIndex);
}

float GetNextThink(int entity, const char[] szContext = "")
{
	return SDKCall(m_hGetNextThink, entity, szContext);
}

void RealizeSpy(int client, int pPlayer)
{
	SDKCall(m_hRealizeSpy, client, pPlayer);
}

bool HasAmmo(int weapon)
{
	return SDKCall(m_hHasAmmo, weapon);
}

int GetAmmoCount(int client, int iAmmoIndex)
{
	return SDKCall(m_hGetAmmoCount, client, iAmmoIndex);
}

int Clip1(int weapon)
{
	return SDKCall(m_hClip1, weapon);
}

void FinishedBuilding(int baseObject)
{
	SDKCall(m_hFinishedBuilding, baseObject);
}

#if defined METHOD_MVM_UPGRADES
Address GEconItemSchema()
{
	return SDKCall(m_hGEconItemSchema);
}

Address GetAttributeDefinitionByName(Address econItemSchema, const char[] pszDefName)
{
	return SDKCall(m_hGetAttributeDefinitionByName, econItemSchema, pszDefName);
}

bool CanUpgradeWithAttrib(int pPlayer, int iWeaponSlot, int iAttribIndex, Address pUpgrade)
{
	return SDKCall(m_hCanUpgradeWithAttrib, pPlayer, iWeaponSlot, iAttribIndex, pUpgrade);
}

int GetCostForUpgrade(Address pUpgrade, int iItemSlot, int nClass, int pPurchaser = -1)
{
	return SDKCall(m_hGetCostForUpgrade, pUpgrade, iItemSlot, nClass, pPurchaser);
}

int GetUpgradeTier(int iUpgrade)
{
	return SDKCall(m_hGetUpgradeTier, iUpgrade);
}

bool IsUpgradeTierEnabled(int pTFPlayer, int iItemSlot, int iUpgrade)
{
	return SDKCall(m_hIsUpgradeTierEnabled, pTFPlayer, iItemSlot, iUpgrade);
}
#endif