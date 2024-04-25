#include <sourcemod>
#include <tf2_stocks>
#include <dhooks>
#include <tf2attributes>
#include <tf_econ_data>
#include <tf2utils>
#include <cbasenpc>
#include <inc_mod_compatibility/actions&cbasenpc>
#include <cbasenpc/tf/nav>
#include <ripext>

#pragma semicolon 1
#pragma newdecls required

// #define TESTING_ONLY

#define METHOD_MVM_UPGRADES

#define PLUGIN_PREFIX	"[BotManager]"
#define TFBOT_IDENTITY_NAME	"TFBOT_SEX_HAVER"

enum
{
	MANAGER_MODE_MANUAL_BOTS = 0,
	MANAGER_MODE_READY_BOTS,
	MANAGER_MODE_AUTO_BOTS
};

bool g_bAreBotsEnabled;
float g_flNextReadyTime;

bool g_bIsDefenderBot[MAXPLAYERS + 1];
bool g_bIsBeingRevived[MAXPLAYERS + 1];
int g_iAdditionalButtons[MAXPLAYERS + 1];

static float m_flNextCommand[MAXPLAYERS + 1];
static float m_flLastReadyInputTime[MAXPLAYERS + 1];

//Config
static ArrayList m_adtBotNames;

//Global entities
int g_iPopulationManager = -1;

ConVar redbots_manager_debug;
ConVar redbots_manager_debug_actions;
ConVar redbots_manager_mode;
ConVar redbots_manager_use_custom_loadouts;
ConVar redbots_manager_kick_bots;
ConVar redbots_manager_min_players;
ConVar redbots_manager_defender_team_size;
ConVar redbots_manager_ready_cooldown;
ConVar redbots_manager_bot_upgrade_interval;
ConVar redbots_manager_bot_use_upgrades;

ConVar tf_bot_path_lookahead_range;
ConVar tf_bot_health_critical_ratio;
ConVar tf_bot_health_ok_ratio;
ConVar tf_bot_ammo_search_range;
ConVar tf_bot_health_search_far_range;
ConVar tf_bot_health_search_near_range;

#if defined METHOD_MVM_UPGRADES
Address g_pMannVsMachineUpgrades;
#endif

#include "redbots3/util.sp"
#include "redbots3/offsets.sp"
#include "redbots3/sdkcalls.sp"
#include "redbots3/loadouts.sp"
#include "redbots3/dhooks.sp"
#include "redbots3/events.sp"
#include "redbots3/player_pref.sp"
#include "redbots3/menu.sp"
#include "redbots3/tf_upgrades.sp"
#include "redbots3/nextbot_actions.sp"

public Plugin myinfo =
{
	name = "[TF2] TFBots (MVM) with Manager",
	author = "Officer Spy",
	description = "Bot Management",
	version = "1.0.1",
	url = ""
};

public void OnPluginStart()
{
#if defined TESTING_ONLY
	BuildPath(Path_SM, g_sPlayerPrefPath, PLATFORM_MAX_PATH, "data/testing/bot_prefs.txt");
	PrintToServer("[BOTS MANAGER] DEBUG BUILD: FOR DEV USE ONLY");
#else
	BuildPath(Path_SM, g_sPlayerPrefPath, PLATFORM_MAX_PATH, "data/bot_prefs.txt");
#endif
	
	redbots_manager_debug = CreateConVar("sm_redbots_manager_debug", "0", _, FCVAR_NONE);
	redbots_manager_debug_actions = CreateConVar("sm_redbots_manager_debug_actions", "0", _, FCVAR_NONE);
	redbots_manager_mode = CreateConVar("sm_redbots_manager_mode", "0", "What mode of the mod the use.", FCVAR_NOTIFY);
	redbots_manager_use_custom_loadouts = CreateConVar("sm_redbots_manager_use_custom_loadouts", "0", "Let's bots use different weapons.", FCVAR_NOTIFY);
	redbots_manager_kick_bots = CreateConVar("sm_redbots_manager_kick_bots", "1", "Kick bots on wave failure/completion.", FCVAR_NOTIFY);
	redbots_manager_min_players = CreateConVar("sm_redbots_manager_min_players", "3", "Minimum players for normal missions. Other difficulties are adjusted based on this value. Set to -1 to disable entirely.", FCVAR_NOTIFY, true, -1.0, true, float(MAXPLAYERS));
	redbots_manager_defender_team_size = CreateConVar("sm_redbots_manager_defender_team_size", "6", _, FCVAR_NOTIFY);
	redbots_manager_ready_cooldown = CreateConVar("sm_redbots_manager_ready_cooldown", "30.0", _, FCVAR_NOTIFY, true, 0.0);
	redbots_manager_bot_upgrade_interval = CreateConVar("sm_redbots_manager_bot_upgrade_interval", "-1", _, FCVAR_NOTIFY);
	redbots_manager_bot_use_upgrades = CreateConVar("sm_redbots_manager_bot_use_upgrades", "1", "Enable bots to buy upgrades.", FCVAR_NOTIFY);
	
	HookConVarChange(redbots_manager_mode, ConVarChanged_ManagerMode);
	
	RegConsoleCmd("sm_votebots", Command_Votebots);
	RegConsoleCmd("sm_vb", Command_Votebots);
	RegConsoleCmd("sm_botpref", Command_BotPreferences);
	RegConsoleCmd("sm_botpreferences", Command_BotPreferences);
	
#if defined TESTING_ONLY
	RegConsoleCmd("sm_bots_start_now", Command_BotsReadyNow);
#endif
	
	RegAdminCmd("sm_addbots", Command_AddBots, ADMFLAG_GENERIC);
	
	AddCommandListener(Listener_TournamentPlayerReadystate, "tournament_player_readystate");
	
	InitGameEventHooks();
	
	GameData hGamedata = new GameData("tf2.defenderbots");
	
	if (hGamedata)
	{
		InitOffsets(hGamedata);
		
		bool bFailed = false;
		
#if defined METHOD_MVM_UPGRADES
		g_pMannVsMachineUpgrades = GameConfGetAddress(hGamedata, "MannVsMachineUpgrades");
		
		if (g_pMannVsMachineUpgrades)
			LogMessage("OnPluginStart: Found \"g_MannVsMachineUpgrades\" @ 0x%X", g_pMannVsMachineUpgrades);
#endif
		
		if (!InitSDKCalls(hGamedata))
			bFailed = true;
		
		if (!InitDHooks(hGamedata))
			bFailed = true;
		
		delete hGamedata;
		
		if (bFailed)
			SetFailState("Gamedata failed!");
	}
	else
	{
		SetFailState("Failed to load gamedata file tf2.defenderbots.txt");
	}
	
	LoadLoadoutFunctions();
	LoadPreferencesData();
	
	m_adtBotNames = new ArrayList(MAX_NAME_LENGTH);
	
	InitNextBotPathing();
}

public void OnMapStart()
{
	g_bAreBotsEnabled = false;
	g_flNextReadyTime = 0.0;
	
	Config_LoadBotNames();
	CreateBotPreferenceMenu();
}

public void OnClientDisconnect(int client)
{
	g_bIsDefenderBot[client] = false;
	
	ResetLoadouts(client);
}

public void OnClientPutInServer(int client)
{
	g_iAdditionalButtons[client] = 0;
	m_flNextCommand[client] = GetGameTime();
	m_flLastReadyInputTime[client] = 0.0;
	
	g_bHasBoughtUpgrades[client] = false;
	
	ResetNextBot(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "info_populator"))
		g_iPopulationManager = entity;
	
	DHooks_OnEntityCreated(entity, classname);
}

public void OnConfigsExecuted()
{
	tf_bot_path_lookahead_range = FindConVar("tf_bot_path_lookahead_range");
	tf_bot_health_critical_ratio = FindConVar("tf_bot_health_critical_ratio");
	tf_bot_health_ok_ratio = FindConVar("tf_bot_health_ok_ratio");
	tf_bot_ammo_search_range = FindConVar("tf_bot_ammo_search_range");
	tf_bot_health_search_far_range = FindConVar("tf_bot_health_search_far_range");
	tf_bot_health_search_near_range = FindConVar("tf_bot_health_search_near_range");
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_bIsDefenderBot[client] == false)
		return Plugin_Continue;
	
	if (IsPlayerAlive(client))
	{
		if (g_iAdditionalButtons[client] != 0)
		{
			buttons |= g_iAdditionalButtons[client];
			g_iAdditionalButtons[client] = 0;
		}
		
		PluginBot_SimulateFrame(client);
	}
	
	return Plugin_Continue;
}

public Action Command_Votebots(int client, int args)
{
	if (redbots_manager_mode.IntValue != MANAGER_MODE_MANUAL_BOTS)
	{
		PrintToChat(client, "%s This is not allowed in this mode.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (GetClientCount(false) >= MaxClients)
	{
		PrintToChat(client, "%s Server is at max capacity.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (g_bAreBotsEnabled)
	{
		PrintToChat(client, "%s Bots are already enabled for this round.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
	{
		PrintToChat(client, "%s This cannot be used at this time.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (IsVoteInProgress())
	{
		PrintToChat(client, "%s A vote is already in progress.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	switch(TF2_GetClientTeam(client))
	{
		case TFTeam_Red:
		{
			if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < redbots_manager_defender_team_size.IntValue)
			{
				StartBotVote(client);
				return Plugin_Handled;
			}
			else
			{
				PrintToChat(client, "%s RED team is full.", PLUGIN_PREFIX);
				return Plugin_Handled;
			}
		}
		case TFTeam_Blue:
		{
			if (GetTeamClientCount(view_as<int>(TFTeam_Red)) <= 0)
			{
				AddRandomDefenderBots(redbots_manager_defender_team_size.IntValue); //TODO: replace me with a smarter team comp
				g_bAreBotsEnabled = true;
				PrintToChatAll("%s You will play a game with bots.", PLUGIN_PREFIX);
				return Plugin_Handled;
			}
			else
			{
				PrintToChat(client, "%s You cannot use this with players on RED team.", PLUGIN_PREFIX);
				return Plugin_Handled;
			}
		}
		default:
		{
			PrintToChat(client, "%s You cannot use this command on this team.", PLUGIN_PREFIX);
			return Plugin_Handled;
		}
	}
}

public Action Command_BotPreferences(int client, int args)
{
	DisplayMenu(g_hBotPreferenceMenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

#if defined TESTING_ONLY
public Action Command_BotsReadyNow(int client, int args)
{
	for (int i = 1; i <= MaxClients; i++)
		if (g_bIsDefenderBot[i] && !IsPlayerReady(i))
			FakeClientCommand(i, "tournament_player_readystate 1");
	
	return Plugin_Handled;
}
#endif

public Action Command_AddBots(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%s Specify an amount of bots to add", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	char arg1[3]; GetCmdArg(1, arg1, sizeof(arg1));
	
	int amount = StringToInt(arg1);
	
	AddBotsBasedOnPreferences(amount);
	// CreateTimer(0.1, Timer_CheckBotImbalance, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	g_bAreBotsEnabled = true;
	
	return Plugin_Handled;
}

public void ConVarChanged_ManagerMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int mode = StringToInt(newValue);
	
	//TODO: really only here for legacy reasons
	//Catch all cases of everything!
}

public Action Listener_TournamentPlayerReadystate(int client, const char[] command, int argc)
{
	switch (redbots_manager_mode.IntValue)
	{
		case MANAGER_MODE_MANUAL_BOTS:
		{
			if (TF2_GetClientTeam(client) == TFTeam_Red)
			{
				char arg1[2]; GetCmdArg(1, arg1, sizeof(arg1));
				int value = StringToInt(arg1);
				
				//0 means we unready, let it pass
				if (value < 1)
					return Plugin_Continue;
				
				//Allow players that are ready to unready
				if (IsPlayerReady(client))
					return Plugin_Continue;
				
				if (redbots_manager_min_players.IntValue != -1)
				{
					eMissionDifficulty difficulty = GetMissionDifficulty();
					int defenderTeamSize = redbots_manager_defender_team_size.IntValue;
					int minPlayers = redbots_manager_min_players.IntValue;
					int trueMinPlayers;
					
					switch (difficulty)
					{
						case MISSION_NORMAL:
						{
							//Don't go over the max amount of red players
							trueMinPlayers = minPlayers > defenderTeamSize ? defenderTeamSize : minPlayers;
							
							//Block ready status if we don't have enough players
							if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < trueMinPlayers)
							{
								PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
								return Plugin_Handled;
							}
						}
						case MISSION_INTERMEDIATE:
						{
							trueMinPlayers = minPlayers + 1 > defenderTeamSize ? defenderTeamSize : minPlayers + 1;
							
							if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < trueMinPlayers)
							{
								PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
								return Plugin_Handled;
							}
						}
						case MISSION_ADVANCED:
						{
							trueMinPlayers = minPlayers + 2 > defenderTeamSize ? defenderTeamSize : minPlayers + 2;
							
							if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < trueMinPlayers)
							{
								PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
								return Plugin_Handled;
							}
						}
						case MISSION_EXPERT:
						{
							trueMinPlayers = minPlayers + 3 > defenderTeamSize ? defenderTeamSize : minPlayers + 3;
							
							if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < trueMinPlayers)
							{
								PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
								return Plugin_Handled;
							}
						}
						case MISSION_NIGHTMARE:
						{
							trueMinPlayers = minPlayers + 4 > defenderTeamSize ? defenderTeamSize : minPlayers + 4;
							
							if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < trueMinPlayers)
							{
								PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
								return Plugin_Handled;
							}
						}
						default:	LogError("Listener_Readystate: Unknown difficulty returned!");
					}
				}
			}
		}
		case MANAGER_MODE_READY_BOTS:
		{
			if (!g_bAreBotsEnabled)
			{
				if (g_flNextReadyTime > GetGameTime())
				{
					PrintToChat(client, "%s You're going too fast!", PLUGIN_PREFIX);
					
					//Give more time to ready dawg
					return Plugin_Handled;
				}
				
				if (m_flLastReadyInputTime[client] <= GetGameTime())
				{
					m_flLastReadyInputTime[client] = GetGameTime() + 3.0;
					PrintToChat(client, "%s Press ready again to start the bots.", PLUGIN_PREFIX);
					
					return Plugin_Handled;
				}
				else
				{
					CreateTimer(0.1, Timer_CheckBotImbalance, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
					g_bAreBotsEnabled = true;
					
					return Plugin_Handled;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_CheckBotImbalance(Handle timer)
{
	if (!g_bAreBotsEnabled)
		return Plugin_Stop;
	
	switch (redbots_manager_mode.IntValue)
	{
		case MANAGER_MODE_MANUAL_BOTS, MANAGER_MODE_READY_BOTS:
		{
			//Bots are added pre-round, don't monitor them during the round
			if (GameRules_GetRoundState() != RoundState_BetweenRounds)
				return Plugin_Stop;
			
			if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < redbots_manager_defender_team_size.IntValue)
			{
				int amount = redbots_manager_defender_team_size.IntValue - GetTeamClientCount(view_as<int>(TFTeam_Red));
				AddBotsBasedOnPreferences(amount);
			}
		}
		case MANAGER_MODE_AUTO_BOTS:
		{
			//Bots are added when rhe wave begins, only monitor them during the round
			if (GameRules_GetRoundState() != RoundState_RoundRunning)
				return Plugin_Stop;
			
			if (GetTeamClientCount(view_as<int>(TFTeam_Red)) < redbots_manager_defender_team_size.IntValue)
			{
				int amount = redbots_manager_defender_team_size.IntValue - GetTeamClientCount(view_as<int>(TFTeam_Red));
				AddBotsBasedOnPreferences(amount);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action DefenderBot_Touch(int entity, int other)
{
	if (BaseEntity_IsPlayer(other) && CBaseNPC_GetNextBotOfEntity(entity).IsEnemy(other))
	{
		//Use default behavior to realize they are a spy on contact
		GameRules_SetProp("m_bPlayingMannVsMachine", false);
	}
	
	return Plugin_Continue;
}

public void DefenderBot_TouchPost(int entity, int other)
{
	if (BaseEntity_IsPlayer(other) && CBaseNPC_GetNextBotOfEntity(entity).IsEnemy(other))
	{
		//Revert cause we are still playing mvm
		GameRules_SetProp("m_bPlayingMannVsMachine", true);
	}
}

bool FakeClientCommandThrottled(int client, const char[] command)
{
	if (m_flNextCommand[client] > GetGameTime())
		return false;
	
	FakeClientCommand(client, command);
	
	m_flNextCommand[client] = GetGameTime() + 0.4;
	
	return true;
}

void RemoveAllDefenderBots(char[] reason = "", bool bFinalWave = false)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bIsDefenderBot[i])
		{
			//We dance on the final wave instead
			if (bFinalWave)
			{
				MakePlayerDance(i);
				continue;
			}
			
			KickClient(i, reason);
		}
	}
	
	g_bAreBotsEnabled = false;
}

void SetRandomNameOnBot(int client)
{
	char newName[MAX_NAME_LENGTH]; GetRandomDefenderBotName(newName, sizeof(newName));
	
	if (DoesAnyPlayerUseThisName(newName))
	{
		//Someone's already using my name, mock them for it and try again
		FakeClientCommand(client, "say %s", g_sPlayerUseMyNameResponse[GetRandomInt(0, sizeof(g_sPlayerUseMyNameResponse) - 1)], newName);
		SetRandomNameOnBot(client);
		return;
	}
	
	SetClientName(client, newName);
}

void GetRandomDefenderBotName(char[] buffer, int maxlen)
{
	if (m_adtBotNames.Length == 0)
	{
		LogError("GetRandomDefenderBotName: No bot names were ever parsed!");
		return;
	}
	
	char botName[MAX_NAME_LENGTH]; m_adtBotNames.GetString(GetRandomInt(0, m_adtBotNames.Length - 1), botName, sizeof(botName));
	
	strcopy(buffer, maxlen, botName);
}

void MakePlayerDance(int client)
{
	if (IsPlayerAlive(client))
	{
		//TODO: tauntem
	}
}

void AddDefenderTFBot(int count, char[] class, char[] team, char[] difficulty)
{
	ServerCommand("tf_bot_add %d %s %s %s %s", count, class, team, difficulty, TFBOT_IDENTITY_NAME);
}

void AddRandomDefenderBots(int amount)
{
	PrintToChatAll("%s Adding %d bot(s)...", PLUGIN_PREFIX, amount);
	
	for (int i = 1; i <= amount; i++)
		AddDefenderTFBot(1, g_sRawPlayerClassNames[GetRandomInt(1, 9)], "red", "expert");
	
	ServerCommand("tf_bot_quota 0");
}

void SetupSniperSpotHints()
{
	//TODO: replace this with our own hints to be spawned from config file
	
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "func_tfbot_hint")) != -1)
	{
		DispatchKeyValue(ent, "team", "0");
	}
}

eMissionDifficulty GetMissionDifficulty()
{
	int rsrc = FindEntityByClassname(MaxClients + 1, "tf_objective_resource");
	
	if (rsrc == -1)
	{
		LogError("GetMissionDifficulty: Could not find entity tf_objective_resource!");
		return MISSION_UNKNOWN;
	}
	
	char missionName[PLATFORM_MAX_PATH]; TF2_GetMvMPopfileName(rsrc, missionName, sizeof(missionName));
	
	//Remove unnecessary
	ReplaceString(missionName, sizeof(missionName), "scripts/population/", "");
	ReplaceString(missionName, sizeof(missionName), ".pop", "");
	
	eMissionDifficulty type;
	
	type = Config_GetMissionDifficultyFromName(missionName);
	
	//No config file specified a difficulty, search for one ourselves
	if (type == MISSION_UNKNOWN)
	{
		char mapName[PLATFORM_MAX_PATH]; GetCurrentMap(mapName, sizeof(mapName));
		
		if (StrEqual(missionName, mapName))
		{
			//If the mission name is the same as the map's name, it's typically a normal mission
			type = MISSION_NORMAL;
		}
		else if (StrContains(missionName, "_intermediate", false) != -1 || StrContains(missionName, "_int_", false) != -1)
		{
			//Searching by prefix or suffix
			type = MISSION_INTERMEDIATE;
		}
		else if (StrContains(missionName, "_advanced", false) != -1 || StrContains(missionName, "_adv_", false) != -1)
		{
			type = MISSION_ADVANCED;
		}
		else if (StrContains(missionName, "_expert", false) != -1 || StrContains(missionName, "_exp_", false) != -1)
		{
			type = MISSION_EXPERT;
		}
		else if (StrContains(missionName, "_night_", false) != -1)
		{
			//NOTE: No official mission actually uses this
			type = MISSION_NIGHTMARE;
		}
	}
	
	if (redbots_manager_debug.BoolValue)
		PrintToChatAll("GetMissionDifficulty: Current difficulty is %d", type);
	
	return type;
}

void Config_LoadBotNames()
{
	char filePath[PLATFORM_MAX_PATH]; BuildPath(Path_SM, filePath, sizeof(filePath), "configs/defender_bots_manager/bot_names.txt");
	File hConfigFile = OpenFile(filePath, "r");
	char currentLine[MAX_NAME_LENGTH + 1];
	
	if (hConfigFile == null)
	{
		LogError("Config_LoadBotNames: Could not locate file %s!", filePath);
		return;
	}
	
	m_adtBotNames.Clear();
	
	while (ReadFileLine(hConfigFile, currentLine, sizeof(currentLine)))
	{
		TrimString(currentLine);
		
		if (strlen(currentLine) > 0)
			m_adtBotNames.PushString(currentLine);
	}
	
	delete hConfigFile;
}

eMissionDifficulty Config_GetMissionDifficultyFromName(char[] missionName)
{	
	char filePath[PLATFORM_MAX_PATH];
	
	for (eMissionDifficulty i = MISSION_NORMAL; i < MISSION_MAX_COUNT; i++)
	{
		BuildPath(Path_SM, filePath, sizeof(filePath), g_sMissionDifficultyFilePaths[i]);
		
		File hOpenedFile = OpenFile(filePath, "r");
		
		if (hOpenedFile == null)
		{
			if (redbots_manager_debug.BoolValue)
				LogMessage("Config_GetMissionDifficultyFromName: Could not locate file %s. Skipping...", g_sMissionDifficultyFilePaths[i]);
			
			continue;
		}
		
		char currentLine[PLATFORM_MAX_PATH];
		
		while (ReadFileLine(hOpenedFile, currentLine, sizeof(currentLine)))
		{
			TrimString(currentLine);
			
			if (StrEqual(currentLine, missionName))
			{
				//Current line matches with the mission name in the file, this is it
				delete hOpenedFile;
				return i;
			}
		}
		
		delete hOpenedFile;
	}
	
	return MISSION_UNKNOWN;
}