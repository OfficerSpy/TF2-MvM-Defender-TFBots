Menu g_hBotPreferenceMenu;
static Menu m_hWeaponPrefClassMenu;

static char m_sSelectedClass[MAXPLAYERS + 1][32];

bool StartBotVote(int callerClient)
{
	Menu vMenu = CreateMenu(MenuHandler_BotVote, MENU_ACTIONS_ALL);
	SetMenuTitle(vMenu, "%N wants to enable bots for this round.\nBots will fill in for missing teammates.", callerClient);
	AddMenuItem(vMenu, "0", "Add bots for this game.");
	AddMenuItem(vMenu, "1", "Don't add bots this game.");
	SetMenuExitButton(vMenu, false);
	
	PrintToChatAll("%s A player started a bot game vote.", PLUGIN_PREFIX);
	
	int total = 0;
	int[] players = new int[MaxClients];
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Red)
			players[total++] = i;
	
	return VoteMenu(vMenu, players, total, 15);
}

void CreateBotPreferenceMenu()
{
	delete g_hBotPreferenceMenu;
	
	g_hBotPreferenceMenu = CreateMenu(MenuHandler_BotPreferenceMain);
	SetMenuTitle(g_hBotPreferenceMenu, "Teammate Bot Preferences");
	AddMenuItem(g_hBotPreferenceMenu, "0", "Class");
	AddMenuItem(g_hBotPreferenceMenu, "1", "Weapons");
	
	delete m_hWeaponPrefClassMenu;
	
	m_hWeaponPrefClassMenu = CreateMenu(MenuHandler_WeaponClassPreference);
	SetMenuExitBackButton(m_hWeaponPrefClassMenu, true);
	AddMenuItem(m_hWeaponPrefClassMenu, "0", "Scout");
	AddMenuItem(m_hWeaponPrefClassMenu, "1", "Soldier");
	AddMenuItem(m_hWeaponPrefClassMenu, "2", "Pyro");
	AddMenuItem(m_hWeaponPrefClassMenu, "3", "Demoman");
	AddMenuItem(m_hWeaponPrefClassMenu, "4", "Heavy");
	AddMenuItem(m_hWeaponPrefClassMenu, "5", "Engineer");
	AddMenuItem(m_hWeaponPrefClassMenu, "6", "Medic");
	AddMenuItem(m_hWeaponPrefClassMenu, "7", "Sniper");
	AddMenuItem(m_hWeaponPrefClassMenu, "8", "Spy");
}

void DisplayClassPreferenceMenu(int client, int item = 0)
{
	int flags = GetClassPreferencesFlags(client);
	
	Menu hClassPrefMenu = CreateMenu(MenuHandler_ClassPreference);
	SetMenuTitle(hClassPrefMenu, "Bot Class Preferences");
	SetMenuExitBackButton(hClassPrefMenu, true);
	AddMenuItem(hClassPrefMenu, "0", flags & PREF_FL_SCOUT ? "Scout: Yes" : "Scout: No");
	AddMenuItem(hClassPrefMenu, "1", flags & PREF_FL_SOLDIER ? "Soldier: Yes" : "Soldier: No");
	AddMenuItem(hClassPrefMenu, "2", flags & PREF_FL_PYRO ? "Pyro: Yes" : "Pyro: No");
	AddMenuItem(hClassPrefMenu, "3", flags & PREF_FL_DEMO ? "Demoman: Yes" : "Demoman: No");
	AddMenuItem(hClassPrefMenu, "4", flags & PREF_FL_HEAVY ? "Heavy: Yes" : "Heavy: No");
	AddMenuItem(hClassPrefMenu, "5", flags & PREF_FL_ENGINEER ? "Engineer: Yes" : "Engineer: No");
	AddMenuItem(hClassPrefMenu, "6", flags & PREF_FL_MEDIC ? "Medic: Yes" : "Medic: No");
	AddMenuItem(hClassPrefMenu, "7", flags & PREF_FL_SNIPER ? "Sniper: Yes" : "Sniper: No");
	AddMenuItem(hClassPrefMenu, "8", flags & PREF_FL_SPY ? "Spy: Yes" : "Spy: No");
	DisplayMenuAtItem(hClassPrefMenu, client, item, MENU_TIME_FOREVER);
}

void DisplayWeaponPreferenceMenu(int client, char[] class, int item = 0)
{
	strcopy(m_sSelectedClass[client], sizeof(m_sSelectedClass[]), class);
	
	Menu hWeaponPrefMenu = CreateMenu(MenuHandler_WeaponPreference);
	SetMenuTitle(hWeaponPrefMenu, "Bot Weapon Preferences: %s", class);
	SetMenuExitBackButton(hWeaponPrefMenu, true);
	AddMenuItem(hWeaponPrefMenu, "0", GetWeaponPrefMenuItemText(client, class, TFWeaponSlot_Primary));
	AddMenuItem(hWeaponPrefMenu, "1", GetWeaponPrefMenuItemText(client, class, TFWeaponSlot_Secondary));
	AddMenuItem(hWeaponPrefMenu, "2", GetWeaponPrefMenuItemText(client, class, TFWeaponSlot_Melee));
	
	if (StrEqual(class, "spy", false))
		AddMenuItem(hWeaponPrefMenu, "3", GetWeaponPrefMenuItemText(client, class, TFWeaponSlot_Item1));
	
	DisplayMenuAtItem(hWeaponPrefMenu, client, item, MENU_TIME_FOREVER);
}

char[] GetWeaponPrefMenuItemText(int client, char[] class, int slot)
{
	char menuText[PLATFORM_MAX_PATH];
	char weaponName[PLATFORM_MAX_PATH];
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:
		{
			if (TF2Econ_GetItemName(GetWeaponPreference(client, class, "primary"), weaponName, sizeof(weaponName)))
				Format(menuText, sizeof(menuText), "Primary: %s", weaponName);
		}
		case TFWeaponSlot_Secondary:
		{
			if (TF2Econ_GetItemName(GetWeaponPreference(client, class, "secondary"), weaponName, sizeof(weaponName)))
				Format(menuText, sizeof(menuText), "Secondary: %s", weaponName);
		}
		case TFWeaponSlot_Melee:
		{
			if (TF2Econ_GetItemName(GetWeaponPreference(client, class, "melee"), weaponName, sizeof(weaponName)))
				Format(menuText, sizeof(menuText), "Melee: %s", weaponName);
		}
		case TFWeaponSlot_Item1:
		{
			if (TF2Econ_GetItemName(GetWeaponPreference(client, class, "pda2"), weaponName, sizeof(weaponName)))
				Format(menuText, sizeof(menuText), "PDA2: %s", weaponName);
		}
		default:
		{
			PrintToChatAll("[GetWeaponPrefMenuItemText] Unspecified weapon slot.");
			LogError("GetWeaponPrefMenuItemText: Unspecified weapon slot.");
		}
	}
	
	return menuText;
}

void CreateDisplayMenuAddDefenderBots(int client, int itemPosition = 0)
{
	if (IsFakeClient(client))
		return;
	
	Menu hMenu = new Menu(MenuHandler_AddDefenderBots);
	hMenu.SetTitle("Manually add bots");
	hMenu.AddItem("0", "Scout");
	hMenu.AddItem("1", "Soldier");
	hMenu.AddItem("2", "Pyro");
	hMenu.AddItem("3", "Demoman");
	hMenu.AddItem("4", "Heavy");
	hMenu.AddItem("5", "Engineer");
	hMenu.AddItem("6", "Medic");
	hMenu.AddItem("7", "Sniper");
	hMenu.AddItem("8", "Spy");
	hMenu.DisplayAt(client, itemPosition, MENU_TIME_FOREVER);
}

void CreateDisplayPanelBotPercentages(int client, float classPercents[TFClass_Engineer], const int duration = 30)
{
	if (IsFakeClient(client))
		return;
	
	Panel hPanel = new Panel();
	hPanel.SetTitle("Defender Bot Class Chances");
	
	char itemText[128];
	
	if (classPercents[0] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Scout: %.0f%%", classPercents[0]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[1] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Soldier: %.0f%%", classPercents[1]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[2] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Pyro: %.0f%%", classPercents[2]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[3] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Demoman: %.0f%%", classPercents[3]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[4] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Heavy: %.0f%%", classPercents[4]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[5] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Engineer: %.0f%%", classPercents[5]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[6] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Medic: %.0f%%", classPercents[6]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[7] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Sniper: %.0f%%", classPercents[7]);
		hPanel.DrawItem(itemText);
	}
	
	if (classPercents[8] > 0.0)
	{
		Format(itemText, sizeof(itemText), "Spy: %.0f%%", classPercents[8]);
		hPanel.DrawItem(itemText);
	}
	
	hPanel.Send(client, MenuHandler_ShowBotChances, duration);
	
	delete hPanel;
}

bool CreateDisplayPanelBotTeamComposition(int client, const int duration = 30)
{
	if (g_adtChosenBotClasses.Length == 0)
		return false;
	
	Panel hPanel = new Panel();
	hPanel.SetTitle("Current Bot Lineup");
	
	char itemText[TF2_CLASS_MAX_NAME_LENGTH];
	
	for (int i = 0; i < g_adtChosenBotClasses.Length; i++)
	{
		g_adtChosenBotClasses.GetString(i, itemText, sizeof(itemText));
		hPanel.DrawItem(itemText);
	}
	
	bool bSuccess = hPanel.Send(client, MenuHandler_ShowBotTeamComposition, duration);
	
	delete hPanel;
	
	return bSuccess;
}

static int MenuHandler_BotVote(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_VoteEnd:
		{
			if (param1 == 0) //yes
				ManageDefenderBots(true);
			else if (param1 == 1)
				PrintToChatAll("%s Bot vote was unsuccessful!", PLUGIN_PREFIX);
		}
	}
	
	return 0;
}

static int MenuHandler_BotPreferenceMain(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:	DisplayClassPreferenceMenu(param1);
				case 1:
				{
					if (redbots_manager_use_custom_loadouts.BoolValue == false)
					{
						PrintToChat(param1, "%s Custom loadouts are not enabled.", PLUGIN_PREFIX);
						return 0;
					}
					
					DisplayMenu(m_hWeaponPrefClassMenu, param1, MENU_TIME_FOREVER);
				}
			}
		}
	}
	
	return 0;
}

static int MenuHandler_ClassPreference(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int flags = GetClassPreferencesFlags(param1);
			
			switch (param2)
			{
				//This may look weird, but we do the opposite because this is them toggling the value
				case 0:	SetClassPreferences(param1, "scout", flags & PREF_FL_SCOUT ? 0 : 1);
				case 1:	SetClassPreferences(param1, "soldier", flags & PREF_FL_SOLDIER ? 0 : 1);
				case 2:	SetClassPreferences(param1, "pyro", flags & PREF_FL_PYRO ? 0 : 1);
				case 3:	SetClassPreferences(param1, "demoman", flags & PREF_FL_DEMO ? 0 : 1);
				case 4:	SetClassPreferences(param1, "heavyweapons", flags & PREF_FL_HEAVY ? 0 : 1);
				case 5:	SetClassPreferences(param1, "engineer", flags & PREF_FL_ENGINEER ? 0 : 1);
				case 6:	SetClassPreferences(param1, "medic", flags & PREF_FL_MEDIC ? 0 : 1);
				case 7:	SetClassPreferences(param1, "sniper", flags & PREF_FL_SNIPER ? 0 : 1);
				case 8:	SetClassPreferences(param1, "spy", flags & PREF_FL_SPY ? 0 : 1);
			}
			
			DisplayClassPreferenceMenu(param1, GetMenuSelectionPosition());
		}
		case MenuAction_End:	delete menu;
	}
	
	if (param2 == MenuCancel_ExitBack)
		DisplayMenu(g_hBotPreferenceMenu, param1, MENU_TIME_FOREVER);
	
	return 0;
}

static int MenuHandler_WeaponClassPreference(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:	DisplayWeaponPreferenceMenu(param1, "scout");
				case 1:	DisplayWeaponPreferenceMenu(param1, "soldier");
				case 2:	DisplayWeaponPreferenceMenu(param1, "pyro");
				case 3:	DisplayWeaponPreferenceMenu(param1, "demoman");
				case 4:	DisplayWeaponPreferenceMenu(param1, "heavyweapons");
				case 5:	DisplayWeaponPreferenceMenu(param1, "engineer");
				case 6:	DisplayWeaponPreferenceMenu(param1, "medic");
				case 7:	DisplayWeaponPreferenceMenu(param1, "sniper");
				case 8:	DisplayWeaponPreferenceMenu(param1, "spy");
			}
		}
	}
	
	if (param2 == MenuCancel_ExitBack)
		DisplayMenu(g_hBotPreferenceMenu, param1, MENU_TIME_FOREVER);
	
	return 0;
}

static int MenuHandler_WeaponPreference(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:	SetRandomWeaponPreference(param1, m_sSelectedClass[param1], "primary");
				case 1:	SetRandomWeaponPreference(param1, m_sSelectedClass[param1], "secondary");
				case 2:	SetRandomWeaponPreference(param1, m_sSelectedClass[param1], "melee");
				case 3:	SetRandomWeaponPreference(param1, m_sSelectedClass[param1], "pda2");
			}
			
			DisplayWeaponPreferenceMenu(param1, m_sSelectedClass[param1], GetMenuSelectionPosition());
		}
		case MenuAction_End:	delete menu;
	}
	
	if (param2 == MenuCancel_ExitBack)
		DisplayMenu(m_hWeaponPrefClassMenu, param1, MENU_TIME_FOREVER);
	
	return 0;
}

static int MenuHandler_AddDefenderBots(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:	AddDefenderTFBot(1, "scout", "red", "expert");
				case 1:	AddDefenderTFBot(1, "soldier", "red", "expert");
				case 2:	AddDefenderTFBot(1, "pyro", "red", "expert");
				case 3:	AddDefenderTFBot(1, "demoman", "red", "expert");
				case 4:	AddDefenderTFBot(1, "heavyweapons", "red", "expert");
				case 5:	AddDefenderTFBot(1, "engineer", "red", "expert");
				case 6:	AddDefenderTFBot(1, "medic", "red", "expert");
				case 7:	AddDefenderTFBot(1, "sniper", "red", "expert");
				case 8:	AddDefenderTFBot(1, "spy", "red", "expert");
			}
			
			CreateDisplayMenuAddDefenderBots(param1, GetMenuSelectionPosition());
			LogAction(param1, -1, "MenuHandler_AddDefenderBots: %L, select %d", param1, param2);
			return 0;
		}
		case MenuAction_End:
		{
			delete menu;
			return 0;
		}
	}
	
	return 0;
}

static int MenuHandler_ShowBotChances(Menu menu, MenuAction action, int param1, int param2)
{
	//Do nothing
	return 0;
}

static int MenuHandler_ShowBotTeamComposition(Menu menu, MenuAction action, int param1, int param2)
{
	//Do nothing
	return 0;
}