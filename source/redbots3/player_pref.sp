#define TF2_CLASS_MAX_NAME_LENGTH	14

enum
{
	PREF_FL_NONE = 0,
	PREF_FL_SCOUT = (1 << 0),
	PREF_FL_SOLDIER = (1 << 1),
	PREF_FL_PYRO = (1 << 2),
	PREF_FL_DEMO = (1 << 3),
	PREF_FL_HEAVY = (1 << 4),
	PREF_FL_ENGINEER = (1 << 5),
	PREF_FL_MEDIC = (1 << 6),
	PREF_FL_SNIPER = (1 << 7),
	PREF_FL_SPY = (1 << 8)
}

char g_sPlayerPrefPath[PLATFORM_MAX_PATH];
static KeyValues m_kvPlayerPrefData;

static Action Timer_SavePrefData(Handle timer)
{
	if (!m_kvPlayerPrefData.ExportToFile(g_sPlayerPrefPath))
	{
		LogError("Timer_SavePrefData: Failed to save player preference data!");
		PrintToChatAll("%s ERROR: Player preference data failed to save!", PLUGIN_PREFIX);
		return Plugin_Continue;
	}
	
	if (redbots_manager_debug.BoolValue)
		PrintToServer("%s Saved player preference data.", PLUGIN_PREFIX);
	
	return Plugin_Continue;
}

void LoadPreferencesData()
{
	m_kvPlayerPrefData = new KeyValues("PlayerBotPreferences");
	m_kvPlayerPrefData.ImportFromFile(g_sPlayerPrefPath);
	
	CreateTimer(20.0, Timer_SavePrefData, _, TIMER_REPEAT);
}

int GetClassPreferencesFlags(int client)
{
	char steamID[MAX_AUTHID_LENGTH];
	
	if (!GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID)))
	{
		LogError("GetClassPreferencesFlags: failed to get Steam ID for %L", client);
		return PREF_FL_NONE;
	}
	
	int flags = PREF_FL_NONE;
	
	m_kvPlayerPrefData.JumpToKey(steamID, true);
	m_kvPlayerPrefData.JumpToKey("class", true);
	
	if (m_kvPlayerPrefData.GetNum("scout", 0) == 1)
		flags |= PREF_FL_SCOUT;
	
	if (m_kvPlayerPrefData.GetNum("soldier", 0) == 1)
		flags |= PREF_FL_SOLDIER;
	
	if (m_kvPlayerPrefData.GetNum("pyro", 0) == 1)
		flags |= PREF_FL_PYRO;
	
	if (m_kvPlayerPrefData.GetNum("demoman", 0) == 1)
		flags |= PREF_FL_DEMO;
	
	if (m_kvPlayerPrefData.GetNum("heavyweapons", 0) == 1)
		flags |= PREF_FL_HEAVY;
	
	if (m_kvPlayerPrefData.GetNum("engineer", 0) == 1)
		flags |= PREF_FL_ENGINEER;
	
	if (m_kvPlayerPrefData.GetNum("medic", 0) == 1)
		flags |= PREF_FL_MEDIC;
	
	if (m_kvPlayerPrefData.GetNum("sniper", 0) == 1)
		flags |= PREF_FL_SNIPER;
	
	if (m_kvPlayerPrefData.GetNum("spy", 0) == 1)
		flags |= PREF_FL_SPY;
	
	m_kvPlayerPrefData.Rewind();
	
	return flags;
}

void SetClassPreferences(int client, const char[] class, int value)
{
	char steamID[MAX_AUTHID_LENGTH];
	
	if (!GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID)))
	{
		LogError("SetClassPreferences: failed to get Steam ID for %L", client);
		return;
	}
	
	m_kvPlayerPrefData.JumpToKey(steamID, true);
	m_kvPlayerPrefData.JumpToKey("class", true);
	m_kvPlayerPrefData.SetNum(class, value);
	m_kvPlayerPrefData.Rewind();
}

//Return weapon def index
int GetWeaponPreference(int client, const char[] class, const char[] slot)
{
	char steamID[MAX_AUTHID_LENGTH];
	
	if (!GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID)))
	{
		LogError("GetWeaponPreference: failed to get Steam ID for %L", client);
		return TF_ITEMDEF_DEFAULT;
	}
	
	int weaponIndex;
	
	m_kvPlayerPrefData.JumpToKey(steamID, true);
	m_kvPlayerPrefData.JumpToKey("loadout", true);
	m_kvPlayerPrefData.JumpToKey(class, true);
	weaponIndex = m_kvPlayerPrefData.GetNum(slot, TF_ITEMDEF_DEFAULT);
	m_kvPlayerPrefData.Rewind();
	
	return weaponIndex;
}

//Return weapon def index
int GetPreferredWeaponForClass(const char[] class, const char[] slot)
{
	ArrayList adtWeaponPref = new ArrayList();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsValidForBotPreferences(i))
		{
			int prefWeapon = GetWeaponPreference(i, class, slot);
			
			if (prefWeapon != TF_ITEMDEF_DEFAULT)
				adtWeaponPref.Push(prefWeapon);
		}
	}
	
	//No preferences found, probably no human red players
	if (adtWeaponPref.Length < 1)
	{
		delete adtWeaponPref;
		return GetRandomWeaponForClass(class, slot);
	}
	
	int itemDefIndex = adtWeaponPref.Get(GetRandomInt(0, adtWeaponPref.Length - 1));
	
	delete adtWeaponPref;
	
	return itemDefIndex;
}

void SetWeaponPreference(int client, const char[] class, const char[] slot, int value)
{
	char steamID[MAX_AUTHID_LENGTH]; GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID));
	
	m_kvPlayerPrefData.JumpToKey(steamID, true);
	m_kvPlayerPrefData.JumpToKey("loadout", true);
	m_kvPlayerPrefData.JumpToKey(class, true);
	m_kvPlayerPrefData.SetNum(slot, value);
	m_kvPlayerPrefData.Rewind();
}

/* void SetRandomWeaponPreference(int client, const char[] class, const char[] slot)
{
	if (StrEqual(class, "scout", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SCOUT_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_SCOUT_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SCOUT_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_SCOUT_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SCOUT_MELEE[GetRandomInt(0, sizeof(WEAPONS_SCOUT_MELEE) - 1)]);
	}
	else if (StrEqual(class, "soldier", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SOLDIER_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_SOLDIER_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SOLDIER_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_SOLDIER_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SOLDIER_MELEE[GetRandomInt(0, sizeof(WEAPONS_SOLDIER_MELEE) - 1)]);
	}
	else if (StrEqual(class, "pyro", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_PYRO_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_PYRO_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_PYRO_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_PYRO_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_PYRO_MELEE[GetRandomInt(0, sizeof(WEAPONS_PYRO_MELEE) - 1)]);
	}
	else if (StrEqual(class, "demoman", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_DEMOMAN_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_DEMOMAN_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_DEMOMAN_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_DEMOMAN_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_DEMOMAN_MELEE[GetRandomInt(0, sizeof(WEAPONS_DEMOMAN_MELEE) - 1)]);
	}
	else if (StrEqual(class, "heavyweapons", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_HEAVY_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_HEAVY_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_HEAVY_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_HEAVY_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_HEAVY_MELEE[GetRandomInt(0, sizeof(WEAPONS_HEAVY_MELEE) - 1)]);
	}
	else if (StrEqual(class, "engineer", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_ENGINEER_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_ENGINEER_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_ENGINEER_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_ENGINEER_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_ENGINEER_MELEE[GetRandomInt(0, sizeof(WEAPONS_ENGINEER_MELEE) - 1)]);
	}
	else if (StrEqual(class, "medic", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_MEDIC_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_MEDIC_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_MEDIC_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_MEDIC_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_MEDIC_MELEE[GetRandomInt(0, sizeof(WEAPONS_MEDIC_MELEE) - 1)]);
	}
	else if (StrEqual(class, "sniper", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SNIPER_PRIMARY[GetRandomInt(0, sizeof(WEAPONS_SNIPER_PRIMARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SNIPER_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_SNIPER_SECONDARY) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SNIPER_MELEE[GetRandomInt(0, sizeof(WEAPONS_SNIPER_MELEE) - 1)]);
	}
	else if (StrEqual(class, "spy", false))
	{
		if (StrEqual(slot, "primary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SPY_SECONDARY[GetRandomInt(0, sizeof(WEAPONS_SPY_SECONDARY) - 1)]);
		else if (StrEqual(slot, "secondary", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SPY_BUILDING[GetRandomInt(0, sizeof(WEAPONS_SPY_BUILDING) - 1)]);
		else if (StrEqual(slot, "melee", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SPY_MELEE[GetRandomInt(0, sizeof(WEAPONS_SPY_MELEE) - 1)]);
		else if (StrEqual(slot, "pda2", false))
			SetWeaponPreference(client, class, slot, WEAPONS_SPY_PDA2[GetRandomInt(0, sizeof(WEAPONS_SPY_PDA2) - 1)]);
	}
	else
	{
		PrintToChatAll("[SetRandomWeaponPreference] Unknown class of %s", class);
		LogError("SetRandomWeaponPreference: Unknown class %s", class);
	}
} */

void AddBotsBasedOnPreferences(int amount)
{
	//Can't add any more if the server is full
	if (IsServerFull())
		return;
	
	PrintToChatAll("%s Adding %d bot(s)...", PLUGIN_PREFIX, amount);
	
	if (amount <= 0)
		return;
	
	ArrayList adtClassPref = new ArrayList(TF2_CLASS_MAX_NAME_LENGTH);
	
	//Get the players' class preferences
	CollectPlayerBotClassPreferences(adtClassPref);
	
	if (adtClassPref.Length > 0)
	{
		for (int i = 1; i <= amount; i++)
		{
			//Now pick a random class from preferences
			//This makes class choice proportional, rather than majority
			char class[TF2_CLASS_MAX_NAME_LENGTH]; adtClassPref.GetString(GetRandomInt(0, adtClassPref.Length - 1), class, sizeof(class));
			
			AddDefenderTFBot(1, class, "red", "expert");
		}
	}
	else
	{
		//Nobody had preferences, just add random bots
		AddRandomDefenderBots(amount);
	}
	
	delete adtClassPref;
}

void CollectPlayerBotClassPreferences(ArrayList stringList)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsValidForBotPreferences(i))
		{
			int classFlags = GetClassPreferencesFlags(i);
			
			if (classFlags & PREF_FL_SCOUT)
				stringList.PushString("scout");
			
			if (classFlags & PREF_FL_SOLDIER)
				stringList.PushString("soldier");
			
			if (classFlags & PREF_FL_PYRO)
				stringList.PushString("pyro");
			
			if (classFlags & PREF_FL_DEMO)
				stringList.PushString("demoman");
			
			if (classFlags & PREF_FL_HEAVY)
				stringList.PushString("heavyweapons");
			
			if (classFlags & PREF_FL_ENGINEER)
				stringList.PushString("engineer");
			
			if (classFlags & PREF_FL_MEDIC)
				stringList.PushString("medic");
			
			if (classFlags & PREF_FL_SNIPER)
				stringList.PushString("sniper");
			
			if (classFlags & PREF_FL_SPY)
				stringList.PushString("spy");
		}
	}
}

//Determines if this player should have an influence on bot choices with their preferences
bool IsValidForBotPreferences(int client)
{
	return !IsFakeClient(client) && TF2_GetClientTeam(client) == TFTeam_Red;
}

void ShowCurrentBotClassChances(int client = -1)
{
	const int maxClassCount = view_as<int>(TFClass_Engineer);
	
	//Each index is for a class, 0 = scout, 1 = soldier, etc.
	//Defined as float for percentage calculation later down below
	float classChoiceCount[maxClassCount];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsValidForBotPreferences(i))
		{
			int classFlags = GetClassPreferencesFlags(i);
			
			if (classFlags & PREF_FL_SCOUT)
				classChoiceCount[0]++;
			
			if (classFlags & PREF_FL_SOLDIER)
				classChoiceCount[1]++;
			
			if (classFlags & PREF_FL_PYRO)
				classChoiceCount[2]++;
			
			if (classFlags & PREF_FL_DEMO)
				classChoiceCount[3]++;
			
			if (classFlags & PREF_FL_HEAVY)
				classChoiceCount[4]++;
			
			if (classFlags & PREF_FL_ENGINEER)
				classChoiceCount[5]++;
			
			if (classFlags & PREF_FL_MEDIC)
				classChoiceCount[6]++;
			
			if (classFlags & PREF_FL_SNIPER)
				classChoiceCount[7]++;
			
			if (classFlags & PREF_FL_SPY)
				classChoiceCount[8]++;
		}
	}
	
	float totalChoices;
	
	for (int i = 0; i < sizeof(classChoiceCount); i++)
		totalChoices += classChoiceCount[i];
	
	if (totalChoices == 0.0)
	{
		if (client > 0)
			PrintHintText(client, "Nobody has any preferences!");
		else
			PrintHintTextToAll("Nobody has any preferences!");
		
		return;
	}
	
	//Like before, each index represents a class
	float classPercents[maxClassCount];
	
	//Class percentage is amount of the class chosen divided by total of all class choices
	for (int i = 0; i < sizeof(classPercents); i++)
		classPercents[i] = (classChoiceCount[i] / totalChoices) * 100;
	
	if (client > 0)
	{
		CreateDisplayPanelBotPercentages(client, classPercents);
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i))
				CreateDisplayPanelBotPercentages(i, classPercents);
	}
}