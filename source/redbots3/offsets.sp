//Used for offset calculations
//https://github.com/Mikusch/MannVsMann/blob/571737b5ae0aadc1e743360e94311ca64e693bd9/addons/sourcemod/scripting/mannvsmann/offsets.sp
static StringMap m_adtOffsets;

static int m_iOffsetIsLookingAroundForEnemies;

void InitOffsets(GameData hGamedata)
{
	m_adtOffsets = new StringMap();
	
	SetOffset(hGamedata, "CTFPlayer", "m_isLookingAroundForEnemies");
	
	//Set offset values
	m_iOffsetIsLookingAroundForEnemies = GetOffset("CTFPlayer", "m_isLookingAroundForEnemies");
	
#if defined TESTING_ONLY
	//Dump offsets
	LogMessage("InitOffsets: CTFBot m_isLookingAroundForEnemies = %d", m_iOffsetIsLookingAroundForEnemies);
#endif
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

void SetLookingAroundForEnemies(int client, bool shouldLook)
{
	SetEntData(client, m_iOffsetIsLookingAroundForEnemies, shouldLook, 1);
}