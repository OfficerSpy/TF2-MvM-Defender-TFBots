//Used for offset calculations
//https://github.com/Mikusch/MannVsMann/blob/571737b5ae0aadc1e743360e94311ca64e693bd9/addons/sourcemod/scripting/mannvsmann/offsets.sp
static StringMap m_adtOffsets;

void InitOffsets(GameData hGamedata)
{
	m_adtOffsets = new StringMap();
	
	SetOffset(hGamedata, "CTFPlayer", "m_isLookingAroundForEnemies");
	SetOffset(hGamedata, "CPopulationManager", "m_nStartingCurrency");
	SetOffset(hGamedata, "CTFPlayer", "m_mission");
	
#if defined TESTING_ONLY
	//Dump offsets
	LogMessage("InitOffsets: CTFBot->m_isLookingAroundForEnemies = %d", GetOffset("CTFPlayer", "m_isLookingAroundForEnemies"));
	LogMessage("InitOffsets: CPopulationManager->m_nStartingCurrency = %d", GetOffset("CPopulationManager", "m_nStartingCurrency"));
	LogMessage("InitOffsets: CTFBot->m_mission = %d", GetOffset("CTFPlayer", "m_mission"));
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

void SetLookingAroundForEnemies(int client, bool shouldLook)
{
	SetEntData(client, GetOffset("CTFPlayer", "m_isLookingAroundForEnemies"), shouldLook, 1);
}

int GetStartingCurrency(int populator)
{
	//NOTE: the actual starting currecny is determined by two variables, but the other one doesn't seem to matter
	return GetEntData(populator, GetOffset("CPopulationManager", "m_nStartingCurrency"));
}

MissionType GetTFBotMission(int client)
{
	return view_as<MissionType>(GetEntData(client, GetOffset("CTFPlayer", "m_mission")));
}