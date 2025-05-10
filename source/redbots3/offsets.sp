//Used for offset calculations
//https://github.com/Mikusch/MannVsMann/blob/571737b5ae0aadc1e743360e94311ca64e693bd9/addons/sourcemod/scripting/mannvsmann/offsets.sp
static StringMap m_adtOffsets;

void InitOffsets(GameData hGamedata)
{
	m_adtOffsets = new StringMap();
	
	SetOffset(hGamedata, "CTFPlayer", "m_LastDamageType");
	SetOffset(hGamedata, "CObjectSentrygun", "m_bPlacementOK");
	SetOffset(hGamedata, "CTFBot", "m_isLookingAroundForEnemies");
	SetOffset(hGamedata, "CTFBot", "m_mission");
	SetOffset(hGamedata, "CPopulationManager", "m_nStartingCurrency");
	SetOffset(hGamedata, "CTFBuffItem", "m_bPlayingHorn");
	SetOffset(hGamedata, "CTFNavArea", "m_distanceToBombTarget");
	
#if defined TESTING_ONLY
	//Dump offsets
	LogMessage("InitOffsets: CTFPlayer->m_LastDamageType = %d", GetOffset("CTFPlayer", "m_LastDamageType"));
	LogMessage("InitOffsets: CObjectSentrygun->m_bPlacementOK = %d", GetOffset("CObjectSentrygun", "m_bPlacementOK"));
	LogMessage("InitOffsets: CTFBot->m_isLookingAroundForEnemies = %d", GetOffset("CTFBot", "m_isLookingAroundForEnemies"));
	LogMessage("InitOffsets: CTFBot->m_mission = %d", GetOffset("CTFBot", "m_mission"));
	LogMessage("InitOffsets: CPopulationManager->m_nStartingCurrency = %d", GetOffset("CPopulationManager", "m_nStartingCurrency"));
	LogMessage("InitOffsets: CTFBuffItem->m_bPlayingHorn = %d", GetOffset("CTFBuffItem", "m_bPlayingHorn"));
	LogMessage("InitOffsets: CTFNavArea->m_distanceToBombTarget = %d", GetOffset("CTFNavArea", "m_distanceToBombTarget"));
#endif
}

static void SetOffset(GameData hGamedata, const char[] cls, const char[] prop)
{
	char key[64], base_key[64], base_prop[64];
	Format(key, sizeof(key), "%s::%s", cls, prop);
	Format(base_key, sizeof(base_key), "%s_BaseOffset", cls);
	
	// Get the actual offset, calculated using a base offset if present
	if (hGamedata.GetKeyValue(base_key, base_prop, sizeof(base_prop)))
	{
		int base_offset = FindSendPropInfo(cls, base_prop);
		
		//For CTFBot, lookup on CTFPlayer
		if (StrEqual(cls, "CTFBot"))
			base_offset = FindSendPropInfo("CTFPlayer", base_prop);
		
		if (base_offset == -1)
		{
			// If we found nothing, search on CBaseEntity instead
			base_offset = FindSendPropInfo("CBaseEntity", base_prop);
			
			if (base_offset == -1)
			{
				ThrowError("Base offset '%s::%s' could not be found", cls, base_prop);
			}
		}
		
		int offset = base_offset + hGamedata.GetOffset(key);
		m_adtOffsets.SetValue(key, offset);
	}
	else
	{
		int offset = hGamedata.GetOffset(key);
		
		if (offset == -1)
		{
			ThrowError("Offset '%s' could not be found", key);
		}
		
		m_adtOffsets.SetValue(key, offset);
	}
}

//Explicitly interpreted as int
static any GetOffset(const char[] cls, const char[] prop)
{
	char key[64];
	Format(key, sizeof(key), "%s::%s", cls, prop);
	
	int offset;
	if (!m_adtOffsets.GetValue(key, offset))
	{
		ThrowError("Offset '%s' not present in map", key);
	}
	
	return offset;
}

int GetLastDamageType(int client)
{
	// return ReadInt(GetEntityAddress(client) + view_as<Address>(offset));
	return GetEntData(client, GetOffset("CTFPlayer", "m_LastDamageType"));
}

bool IsPlacementOK(int iObject)
{
	return view_as<bool>(GetEntData(iObject, GetOffset("CObjectSentrygun", "m_bPlacementOK"), 1));
}

void SetLookingAroundForEnemies(int client, bool shouldLook)
{
	SetEntData(client, GetOffset("CTFBot", "m_isLookingAroundForEnemies"), shouldLook, 1);
}

int GetTFBotMission(int client)
{
	return GetEntData(client, GetOffset("CTFBot", "m_mission"));
}

int GetStartingCurrency(int populator)
{
	//NOTE: the actual starting currecny is determined by two variables, but the other one doesn't seem to matter
	return GetEntData(populator, GetOffset("CPopulationManager", "m_nStartingCurrency"));
}

bool IsPlayingHorn(int weapon)
{
	return view_as<bool>(GetEntData(weapon, GetOffset("CTFBuffItem", "m_bPlayingHorn"), 1));
}

float GetTravelDistanceToBombTarget(CTFNavArea area)
{
	return LoadFromAddress(view_as<Address>(area) + GetOffset("CTFNavArea", "m_distanceToBombTarget"), NumberType_Int32);
}