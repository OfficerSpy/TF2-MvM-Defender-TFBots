/* --------------------------------------------------
MvM Defender TFBots
April 08 2024
Author: ★ Officer Spy ★
-------------------------------------------------- */
#include <sourcemod>
#include <tf2_stocks>
#include <dhooks>
#include <tf2attributes>
#include <tf_econ_data>
#include <tf2utils>
#include <cbasenpc>
#include <cbasenpc/tf/nav>
#include <ripext>

#define _disable_actions_query_result_type
#define _disable_actions_event_result_priority_type
#include <actions>

#pragma semicolon 1
#pragma newdecls required

// #define TESTING_ONLY

#define MOD_REQUEST_CREDITS
#define MOD_CUSTOM_ATTRIBUTES
#define MOD_ROLL_THE_DICE_REVAMPED

#define METHOD_MVM_UPGRADES

#define CHANGETEAM_RESTRICTIONS

// #define EXTRA_PLUGINBOT

// #define IDLEBOT_AIMING

#define PLUGIN_PREFIX	"[BotManager]"
#define TFBOT_IDENTITY_NAME	"TFBOT_SEX_HAVER"

enum
{
	MANAGER_MODE_MANUAL_BOTS = 0,
	MANAGER_MODE_READY_BOTS,
	MANAGER_MODE_AUTO_BOTS
};

//Globals
bool g_bLateLoad;
bool g_bBotsEnabled;
float g_flNextReadyTime;
int g_iDetonatingPlayer = -1;
ArrayList g_adtChosenBotClasses;
bool g_bBotClassesLocked;

//For defender bots
bool g_bIsDefenderBot[MAXPLAYERS + 1];
bool g_bIsBeingRevived[MAXPLAYERS + 1];
bool g_bHasUpgraded[MAXPLAYERS + 1];
int g_iAdditionalButtons[MAXPLAYERS + 1];
float g_flForceHoldButtonsTime[MAXPLAYERS + 1];
int g_iSubtractiveButtons[MAXPLAYERS + 1];
float g_flBlockInputTime[MAXPLAYERS + 1];
static float m_flDeadRethinkTime[MAXPLAYERS + 1];
int g_iBuybackNumber[MAXPLAYERS + 1];
int g_iBuyUpgradesNumber[MAXPLAYERS + 1];

#if !defined IDLEBOT_AIMING
static float m_flNextSnipeFireTime[MAXPLAYERS + 1];
#endif

#if defined MOD_ROLL_THE_DICE_REVAMPED
static float m_flNextRollTime[MAXPLAYERS + 1];
#endif

//For other players
bool g_bChoosingBotClasses[MAXPLAYERS + 1];

#if defined CHANGETEAM_RESTRICTIONS
float g_flEnableBotsCooldown[MAXPLAYERS + 1];
#endif

static float m_flLastCommandTime[MAXPLAYERS + 1];
static float m_flLastReadyInputTime[MAXPLAYERS + 1];

//Config
static ArrayList m_adtBotNames;
static ArrayList m_adtSniperHints;

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
ConVar redbots_manager_bot_buyback_chance;
ConVar redbots_manager_bot_buy_upgrades_chance;
ConVar redbots_manager_bot_max_tank_attackers;
ConVar redbots_manager_bot_aim_skill;
ConVar redbots_manager_bot_reflect_skill;
ConVar redbots_manager_bot_reflect_chance;
ConVar redbots_manager_bot_hear_spy_range;
ConVar redbots_manager_extra_bots;

#if defined MOD_REQUEST_CREDITS
ConVar redbots_manager_bot_request_credits;
#endif

#if defined MOD_ROLL_THE_DICE_REVAMPED
ConVar redbots_manager_bot_rtd_variance;
#endif

ConVar tf_bot_path_lookahead_range;
ConVar tf_bot_health_critical_ratio;
ConVar tf_bot_health_ok_ratio;
ConVar tf_bot_ammo_search_range;
ConVar tf_bot_health_search_far_range;
ConVar tf_bot_health_search_near_range;
ConVar tf_bot_suicide_bomb_range;

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
#include "redbots3/botaim.sp"

public Plugin myinfo =
{
	name = "[TF2] TFBots (MVM) with Manager",
	author = "Officer Spy",
	description = "Bot Management",
	version = "1.4.4",
	url = "https://github.com/OfficerSpy/TF2-MvM-Defender-TFBots"
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
	redbots_manager_bot_buyback_chance = CreateConVar("sm_redbots_manager_bot_buyback_chance", "5", "Chance for bots to buyback into the game.", FCVAR_NOTIFY);
	redbots_manager_bot_buy_upgrades_chance = CreateConVar("sm_redbots_manager_bot_buy_upgrades_chance", "50", "Chance for bots to buy upgrades in the middle of a game.", FCVAR_NOTIFY);
	redbots_manager_bot_max_tank_attackers = CreateConVar("sm_redbots_manager_bot_max_tank_attackers", "3", _, FCVAR_NOTIFY);
	redbots_manager_bot_aim_skill = CreateConVar("sm_redbots_manager_bot_aim_skill", "2", _, FCVAR_NOTIFY);
	redbots_manager_bot_reflect_skill = CreateConVar("sm_redbots_manager_bot_reflect_skill", "2", _, FCVAR_NOTIFY);
	redbots_manager_bot_reflect_chance = CreateConVar("redbots_manager_bot_reflect_chance", "100.0", _, FCVAR_NOTIFY);
	redbots_manager_bot_hear_spy_range = CreateConVar("sm_redbots_manager_bot_hear_spy_range", "3000.0", _, FCVAR_NOTIFY);
	redbots_manager_extra_bots = CreateConVar("sm_redbots_manager_extra_bots", "1", "How many more bots we are allowed to request beyond the team size", FCVAR_NOTIFY);
	
#if defined MOD_REQUEST_CREDITS
	redbots_manager_bot_request_credits = CreateConVar("sm_redbots_manager_bot_request_credits", "1", _, FCVAR_NOTIFY);
#endif
	
#if defined MOD_ROLL_THE_DICE_REVAMPED
	redbots_manager_bot_rtd_variance = CreateConVar("sm_redbots_manager_bot_rtd_variance", "15.0", _, FCVAR_NOTIFY);
#endif
	
	HookConVarChange(redbots_manager_mode, ConVarChanged_ManagerMode);
	
	RegConsoleCmd("sm_votebots", Command_Votebots);
	RegConsoleCmd("sm_vb", Command_Votebots);
	RegConsoleCmd("sm_botpref", Command_BotPreferences);
	RegConsoleCmd("sm_botpreferences", Command_BotPreferences);
	RegConsoleCmd("sm_viewbotchances", Command_ShowBotChances);
	RegConsoleCmd("sm_botchances", Command_ShowBotChances);
	RegConsoleCmd("sm_viewbotlineup", Command_ShowNewBotTeamComposition);
	RegConsoleCmd("sm_botlineup", Command_ShowNewBotTeamComposition);
	RegConsoleCmd("sm_rerollbotclasses", Command_RerollNewBotTeamComposition);
	RegConsoleCmd("sm_rerollbots", Command_RerollNewBotTeamComposition);
	RegConsoleCmd("sm_rollbots", Command_RerollNewBotTeamComposition);
	RegConsoleCmd("sm_playwithbots", Command_JoinBluePlayWithBots);
	RegConsoleCmd("sm_requestbot", Command_RequestExtraBot);
	RegConsoleCmd("sm_choosebotteam", Command_ChooseBotClasses);
	RegConsoleCmd("sm_cbt", Command_ChooseBotClasses);
	
#if defined TESTING_ONLY
	RegConsoleCmd("sm_bots_start_now", Command_BotsReadyNow);
#endif
	
	RegAdminCmd("sm_addbots", Command_AddBots, ADMFLAG_GENERIC);
	RegAdminCmd("sm_view_bot_upgrades", Command_ViewBotUpgrades, ADMFLAG_GENERIC);
	
	AddCommandListener(Listener_TournamentPlayerReadystate, "tournament_player_readystate");
	
	AddNormalSoundHook(SoundHook_General);
	
	InitGameEventHooks();
	
	GameData hGamedata = new GameData("tf2.defenderbots");
	
	if (hGamedata)
	{
		InitOffsets(hGamedata);
		
		bool bFailed = false;
		
#if defined METHOD_MVM_UPGRADES
		InitMvMUpgrades(hGamedata);
		
		g_pMannVsMachineUpgrades = GameConfGetAddress(hGamedata, "MannVsMachineUpgrades");
		
		if (!g_pMannVsMachineUpgrades)
			LogError("OnPluginStart: Failed to find Address to g_MannVsMachineUpgrades!");
#if defined TESTING_ONLY
		else
			LogMessage("OnPluginStart: Found \"g_MannVsMachineUpgrades\" @ 0x%X", g_pMannVsMachineUpgrades);
#endif
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
	
	if (g_bLateLoad)
	{
		g_iPopulationManager = FindEntityByClassname(MaxClients + 1, "info_populator");
	}
	
	LoadLoadoutFunctions();
	LoadPreferencesData();
	
	g_adtChosenBotClasses = new ArrayList(TF2_CLASS_MAX_NAME_LENGTH);
	m_adtBotNames = new ArrayList(MAX_NAME_LENGTH);
	m_adtSniperHints = new ArrayList(3);
	
	InitNextBotPathing();
	
#if defined IDLEBOT_AIMING
	InitTFBotAim();
#endif
}

public void OnPluginEnd()
{
	RemoveAllDefenderBots("BM3 OnPluginEnd");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	
	return APLRes_Success;
}

public void OnMapStart()
{
	g_bBotsEnabled = false;
	g_flNextReadyTime = 0.0;
	g_bBotClassesLocked = false;
	
	Config_LoadMap();
	Config_LoadBotNames();
	CreateBotPreferenceMenu();
}

public void OnConfigsExecuted()
{
	if (!tf_bot_path_lookahead_range)
		tf_bot_path_lookahead_range = FindConVar("tf_bot_path_lookahead_range");
	
	if (!tf_bot_health_critical_ratio)
		tf_bot_health_critical_ratio = FindConVar("tf_bot_health_critical_ratio");
	
	if (!tf_bot_health_ok_ratio)
		tf_bot_health_ok_ratio = FindConVar("tf_bot_health_ok_ratio");
	
	if (!tf_bot_ammo_search_range)
		tf_bot_ammo_search_range = FindConVar("tf_bot_ammo_search_range");
	
	if (!tf_bot_health_search_far_range)
		tf_bot_health_search_far_range = FindConVar("tf_bot_health_search_far_range");
	
	if (!tf_bot_health_search_near_range)
		tf_bot_health_search_near_range = FindConVar("tf_bot_health_search_near_range");
	
	if (!tf_bot_suicide_bomb_range)
		tf_bot_suicide_bomb_range = FindConVar("tf_bot_suicide_bomb_range");
}

/* public void OnMapEnd()
{
	RemoveAllDefenderBots("BM3 OnMapEnd");
} */

public void OnClientDisconnect(int client)
{
	g_bIsDefenderBot[client] = false;
	
	g_bChoosingBotClasses[client] = false;
	
	ResetLoadouts(client);
}

public void OnClientPutInServer(int client)
{
	g_bHasUpgraded[client] = false;
	g_iAdditionalButtons[client] = 0;
	g_flForceHoldButtonsTime[client] = 0.0;
	g_iSubtractiveButtons[client] = 0;
	g_flBlockInputTime[client] = 0.0;
	m_flDeadRethinkTime[client] = 0.0;
	g_iBuybackNumber[client] = 0;
	g_iBuyUpgradesNumber[client] = 0;
	
	// m_flNextSnipeFireTime[client] = 0.0;
	
#if defined MOD_ROLL_THE_DICE_REVAMPED
	m_flNextRollTime[client] = 0.0;
#endif
	
#if defined CHANGETEAM_RESTRICTIONS
	g_flEnableBotsCooldown[client] = 0.0;
#endif
	
	m_flLastCommandTime[client] = GetGameTime();
	m_flLastReadyInputTime[client] = 0.0;
	
	g_bHasBoughtUpgrades[client] = false;
	
	ResetNextBot(client);
	
#if defined IDLEBOT_AIMING
	BotAim(client).Reset();
#endif
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "info_populator"))
		g_iPopulationManager = entity;
	
	DHooks_OnEntityCreated(entity, classname);
}

/* NOTE: This forward is not consistent with nextbot functionalities such as Action::Update
Nextbot behavior updates are based on the value of convar nb_update_frequency
This forward is only called every time CBasePlayer::PlayerRunCommand is called, which updates on its own interval
So what gets done in here will never always be consistent with the nextbot behavior actions */
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_bIsDefenderBot[client] == false)
		return Plugin_Continue;
	
	if (IsPlayerAlive(client))
	{
		if (g_iAdditionalButtons[client] != 0)
		{
			if (g_iAdditionalButtons[client] & IN_BACK)
				vel[0] -= PLAYER_SIDESPEED;
			
			if (g_iAdditionalButtons[client] & IN_FORWARD)
				vel[0] += PLAYER_SIDESPEED;
			
			if (g_iAdditionalButtons[client] & IN_MOVELEFT)
				vel[1] -= PLAYER_SIDESPEED;
			
			if (g_iAdditionalButtons[client] & IN_MOVERIGHT)
				vel[1] += PLAYER_SIDESPEED;
			
			buttons |= g_iAdditionalButtons[client];
			
			//We are told to hold these inputs down for a specific time, don't clear until it expires
			if (g_flForceHoldButtonsTime[client] <= GetGameTime())
				g_iAdditionalButtons[client] = 0;
		}
		
		if (g_iSubtractiveButtons[client] != 0)
		{
			buttons &= ~g_iSubtractiveButtons[client];
			g_iSubtractiveButtons[client] = 0;
		}
		
#if defined EXTRA_PLUGINBOT
		PluginBot_SimulateFrame(client);
#endif
		
#if defined IDLEBOT_AIMING
		if (m_ctReload[client] > GetGameTime())
		{
			buttons |= IN_RELOAD;
		}
		
		if (m_ctFire[client] > GetGameTime())
		{
			buttons |= IN_ATTACK;
		}
		
		if (m_ctAltFire[client] > GetGameTime())
		{
			buttons |= IN_ATTACK2;
		}
#endif
		
		if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		{
			int myWeapon = BaseCombatCharacter_GetActiveWeapon(client);
			int weaponID = myWeapon != -1 ? TF2Util_GetWeaponID(myWeapon) : -1;
			
			if (buttons & IN_ATTACK)
			{
				switch (weaponID)
				{
#if !defined IDLEBOT_AIMING
					case TF_WEAPON_MINIGUN:
					{
						//Don't keep spinning the minigun if it ran out of ammo
						if (!HasAmmo(myWeapon))
							buttons &= ~IN_ATTACK;
					}
#endif
					case TF_WEAPON_SNIPERRIFLE_CLASSIC:
					{
						//For the classic, let go on a full charge
						if (GetEntPropFloat(myWeapon, Prop_Send, "m_flChargedDamage") >= 150.0)
							buttons &= ~IN_ATTACK;
					}
					case TF_WEAPON_BUFF_ITEM:
					{
						//Once we blow the horn, stop pressing the fire button
						if (IsPlayingHorn(myWeapon))
							buttons &= ~IN_ATTACK;
					}
				}
			}
			
			INextBot myBot = CBaseNPC_GetNextBotOfEntity(client);
			IVision myVision = myBot.GetVisionInterface();
			
			MonitorKnownEntities(client, myVision);
			
			CKnownEntity threat = myVision.GetPrimaryKnownThreat(false);
			
			OpportunisticallyUseWeaponAbilities(client, myWeapon, myBot, threat);
			OpportunisticallyUsePowerupBottle(client, myWeapon, myBot, threat);
			
			if ((weaponID == TF_WEAPON_FLAMETHROWER || weaponID == TF_WEAPON_FLAME_BALL) && CanWeaponAirblast(myWeapon))
				UtilizeCompressionBlast(client, myBot, threat, 1);
			
#if defined IDLEBOT_AIMING
			if (threat)
			{
				//TODO: disable on engineers for now until we make a proper better behavior
				if (TF2_GetPlayerClass(client) != TFClass_Engineer)
					BotAim(client).AimHeadTowardsEntity(threat.GetEntity(), CRITICAL, 0.1);
			}
#else
			if (WeaponID_IsSniperRifle(weaponID))
			{
				if (TF2_IsPlayerInCondition(client, TFCond_Zoomed))
				{
					if (redbots_manager_bot_aim_skill.IntValue >= 1)
					{
						//TODO: this needs to be more precise with actually getting our current m_lookAtSubject in PlayerBody as this can cause jittery aim
						if (threat && TF2_IsLineOfFireClear4(client, threat.GetEntity()))
						{
							//Help aim towards the desired target point
							float aimPos[3]; myBot.GetIntentionInterface().SelectTargetPoint(threat.GetEntity(), aimPos);
							SnapViewToPosition(client, aimPos);
							
							if (m_flNextSnipeFireTime[client] <= GetGameTime())
								VS_PressFireButton(client);
						}
						else
						{
							//Delay to give a reaction time the next time we can see a threat
							m_flNextSnipeFireTime[client] = GetGameTime() + SNIPER_REACTION_TIME;
						}
					}
					else
					{
						if (threat && myBot.GetBodyInterface().IsHeadAimingOnTarget())
						{
							if (m_flNextSnipeFireTime[client] <= GetGameTime())
								VS_PressFireButton(client);
						}
						else
						{
							m_flNextSnipeFireTime[client] = GetGameTime() + SNIPER_REACTION_TIME;
						}
					}
				}
				else
				{
					//Set a reaction time when we're not scoped in
					m_flNextSnipeFireTime[client] = GetGameTime() + SNIPER_REACTION_TIME;
				}
			}
			else
			{
				if (threat)
				{
					//Exclude certain things for scenarios where aim shouldn't be altered
					//TODO: replace this with a variable to control this
					if (IsCombatWeapon(client, myWeapon) && weaponID != TF_WEAPON_KNIFE && TF2_GetPlayerClass(client) != TFClass_Engineer && weaponID != TF_WEAPON_BONESAW)
					{
						int iThreat = threat.GetEntity();
						
						if (redbots_manager_bot_aim_skill.IntValue >= 2)
						{
							/* NOTE: this used to be handled in CTFBotMainAction_SelectTargetPoint, but it seems that function doesn't always get called when the bot is up close to it
							The bot will look up, but then start looking towards the center again and stop firing before going to look up and fire again
							It then just repeats this process over and over unless it gets away from the tank */
							if (weaponID == TF_WEAPON_FLAMETHROWER && IsBaseBoss(iThreat) && myBot.IsRangeLessThan(iThreat, FLAMETHROWER_REACH_RANGE))
							{
								float aimPos[3]; GetFlameThrowerAimForTank(iThreat, aimPos);
								SnapViewToPosition(client, aimPos);
								buttons |= IN_ATTACK;
							}
							else if (!threat.IsVisibleInFOVNow() && TF2_IsLineOfFireClear4(client, iThreat))
							{
								//We're not currently facing our threat, so let's quickly turn towards them
								float aimPos[3]; myBot.GetIntentionInterface().SelectTargetPoint(iThreat, aimPos);
								SnapViewToPosition(client, aimPos);
							}
						}
						else if (redbots_manager_bot_aim_skill.IntValue == 1)
						{
							if (weaponID == TF_WEAPON_FLAMETHROWER && IsBaseBoss(iThreat) && myBot.IsRangeLessThan(iThreat, FLAMETHROWER_REACH_RANGE))
							{
								float aimPos[3]; GetFlameThrowerAimForTank(iThreat, aimPos);
								SnapViewToPosition(client, aimPos);
								buttons |= IN_ATTACK;
							}
							else if (!threat.IsVisibleRecently() && TF2_IsLineOfFireClear4(client, iThreat))
							{
								float aimPos[3]; myBot.GetIntentionInterface().SelectTargetPoint(iThreat, aimPos);
								SnapViewToPosition(client, aimPos);
							}
						}
						else
						{
							if (weaponID == TF_WEAPON_FLAMETHROWER && IsBaseBoss(iThreat) && myBot.IsRangeLessThan(iThreat, FLAMETHROWER_REACH_RANGE))
							{
								float aimPos[3];
								GetFlameThrowerAimForTank(iThreat, aimPos);
								SnapViewToPosition(client, aimPos); //TODO: replace with AimHeadTowards
								buttons |= IN_ATTACK;
							}
						}
					}
				}
			}
#endif
			
#if defined MOD_ROLL_THE_DICE_REVAMPED
			if (redbots_manager_bot_rtd_variance.FloatValue >= COMMAND_MAX_RATE)
			{
				if (m_flNextRollTime[client] <= GetGameTime())
				{
					m_flNextRollTime[client] = GetGameTime() + GetRandomFloat(COMMAND_MAX_RATE, redbots_manager_bot_rtd_variance.FloatValue);
					FakeClientCommand(client, "sm_rtd");
				}
			}
#endif
		}
		
#if defined IDLEBOT_AIMING
		BotAim(client).Upkeep();
		BotAim(client).FireWeaponAtEnemy();
#endif
	}
	else
	{
		if (m_flDeadRethinkTime[client] <= GetGameTime())
		{
			//Think every second while we're dead
			m_flDeadRethinkTime[client] = GetGameTime() + 1.0;
			
			int iObsMode = BasePlayer_GetObserverMode(client);
			
			if (iObsMode == OBS_MODE_FREEZECAM || iObsMode == OBS_MODE_DEATHCAM)
			{
				//We can't buyback right now, so don't even think about it
				g_iBuybackNumber[client] = 0;
			}
			else
			{
				//Randomly think about buying back
				g_iBuybackNumber[client] = GetRandomInt(1, 100);
			}
			
			if (ShouldBuybackIntoGame(client))
				PlayerBuyback(client);
			
			if (redbots_manager_debug.BoolValue)
				PrintToChatAll("[OnPlayerRunCmd] g_iBuybackNumber[%d] = %d", client, g_iBuybackNumber[client]);
		}
		
		
	}
	
	return Plugin_Continue;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if (condition == TFCond_Taunting && TF2_GetClientTeam(client) == TFTeam_Blue && IsSentryBusterRobot(client))
	{
		//Keep track of the player that is detonating
		g_iDetonatingPlayer = client;
		CreateTimer(2.0, Timer_ForgetDetonatingPlayer, client);
	}
}

public Action Command_Votebots(int client, int args)
{
	if (g_bBotsEnabled)
	{
		PrintToChat(client, "%s Bots are already enabled for this round.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (redbots_manager_mode.IntValue != MANAGER_MODE_MANUAL_BOTS)
	{
		PrintToChat(client, "%s This is only allowed in MANAGER_MODE_MANUAL_BOTS.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (IsServerFull())
	{
		PrintToChat(client, "%s Server is at max capacity.", PLUGIN_PREFIX);
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
	
	if (g_bChoosingBotClasses[client])
	{
		PrintToChat(client, "%s You are already choosing the next team lineup.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (GetCountOfPlayersChoosingBotClasses() > 0)
	{
		PrintToChat(client, "%s Someone is currently choosing the next team lineup.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	switch (TF2_GetClientTeam(client))
	{
		case TFTeam_Red:
		{
#if defined CHANGETEAM_RESTRICTIONS
			float botBanTime = g_flEnableBotsCooldown[client] - GetGameTime();
			
			if (botBanTime > 0.0)
			{
				ReplyToCommand(client, "%s You cannot start the bots at this time.", PLUGIN_PREFIX);
				LogAction(client, -1, "MANAGER_MODE_MANUAL_BOTS: %L tried to start the bots on cooldown. (%f seconds)", client, botBanTime);
				
				return Plugin_Handled;
			}
#endif
			
			if (GetHumanAndDefenderBotCount(TFTeam_Red) < redbots_manager_defender_team_size.IntValue)
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

public Action Command_ShowBotChances(int client, int args)
{
	ShowCurrentBotClassChances(client);
	return Plugin_Handled;
}

public Action Command_ShowNewBotTeamComposition(int client, int args)
{
	if (CreateDisplayPanelBotTeamComposition(client))
		PrintToChat(client, "Use command !rerollbotclasses to reshuffle the bot class lineup.");
	
	return Plugin_Handled;
}

public Action Command_RerollNewBotTeamComposition(int client, int args)
{
#if !defined TESTING_ONLY
	if (TF2_GetClientTeam(client) != TFTeam_Red)
	{
		PrintToChat(client, "%s Your team is not allowed to use this.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
#endif
	
	UpdateChosenBotTeamComposition(client);
	CreateDisplayPanelBotTeamComposition(client);
	
	return Plugin_Handled;
}

public Action Command_JoinBluePlayWithBots(int client, int args)
{
	if (g_bBotsEnabled)
	{
		PrintToChat(client, "%s Bots are already enabled for this round.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (TF2_GetClientTeam(client) != TFTeam_Blue)
	{
		PrintToChat(client, "%s Your team is not allowed to use this.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (GetHumanAndDefenderBotCount(TFTeam_Red) > 0)
	{
		PrintToChat(client, "%s You cannot use this with players on RED team.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	AddRandomDefenderBots(redbots_manager_defender_team_size.IntValue); //TODO: replace me with a smarter team comp
	g_bBotsEnabled = true;
	PrintToChatAll("%s You will play a game with bots.", PLUGIN_PREFIX);
	
	return Plugin_Handled;
}

public Action Command_RequestExtraBot(int client, int args)
{
	if (!g_bBotsEnabled)
	{
		PrintToChat(client, "%s Bots aren't enabled.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (TF2_GetClientTeam(client) != TFTeam_Red)
	{
		PrintToChat(client, "%s Your team is not allowed to use this.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (IsServerFull())
	{
		PrintToChat(client, "%s It is currently not possible to add any more.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	int defenderLimit = redbots_manager_defender_team_size.IntValue + redbots_manager_extra_bots.IntValue;
	
	if (GetHumanAndDefenderBotCount(TFTeam_Red) >= defenderLimit)
	{
		PrintToChat(client, "%s You already have an additional unit.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	AddBotsBasedOnPreferences(1);
	PrintToChatAll("%s %N requested an additional unit.", PLUGIN_PREFIX, client);
	
	return Plugin_Handled;
}

public Action Command_ChooseBotClasses(int client, int args)
{
	if (g_bBotsEnabled)
	{
		PrintToChat(client, "%s Bots are already enabled.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (TF2_GetClientTeam(client) != TFTeam_Red)
	{
		PrintToChat(client, "%s Your team is not allowed to use this.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (g_bBotClassesLocked)
	{
		PrintToChat(client, "%s Someone has already chosen the lineup for the next game.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (g_bChoosingBotClasses[client])
	{
		PrintToChat(client, "%s You are already choosing the next team lineup.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	if (GetCountOfPlayersChoosingBotClasses() > 0)
	{
		PrintToChat(client, "%s Someone is currently choosing the next team lineup.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	int redTeamCount = GetHumanAndDefenderBotCount(TFTeam_Red);
	int defenderTeamSize = redbots_manager_defender_team_size.IntValue;
	
	if (redTeamCount >= defenderTeamSize)
	{
		PrintToChat(client, "%s You are not solo.", PLUGIN_PREFIX);
		return Plugin_Handled;
	}
	
	//Should only be able to call this while solo, so current team count should always be 1
	ShowDefenderBotTeamSetupMenu(client, _, true, defenderTeamSize - redTeamCount);
	
	return Plugin_Handled;
}

#if defined TESTING_ONLY
public Action Command_BotsReadyNow(int client, int args)
{
	/* for (int i = 1; i <= MaxClients; i++)
		if (g_bIsDefenderBot[i] && !IsPlayerReady(i))
			FakeClientCommand(i, "tournament_player_readystate 1"); */
	
	int target = GetClientAimTarget(client);
	SpawnSapper(client, target);
	
	return Plugin_Handled;
}
#endif

public Action Command_AddBots(int client, int args)
{
	if (args > 0)
	{
		char arg1[3]; GetCmdArg(1, arg1, sizeof(arg1));
		int amount = StringToInt(arg1);
		AddBotsBasedOnPreferences(amount);
		
		return Plugin_Handled;
	}
	
	CreateDisplayMenuAddDefenderBots(client);
	return Plugin_Handled;
}

public Action Command_ViewBotUpgrades(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_view_bot_upgrades <#userid|name> <slot>");
		return Plugin_Handled;
	}
	
	char arg[65]; GetCmdArg(1, arg, sizeof(arg));
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int slot = -1;
	
	if (args >= 2)
	{
		char arg2[3]; GetCmdArg(2, arg2, sizeof(arg2));
		
		slot = StringToInt(arg2);
	}
	
	for (int i = 0; i < target_count; i++)
		ShowPlayerUpgrades(client, target_list[i], slot);
	
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
			if (TF2_GetClientTeam(client) != TFTeam_Red)
				return Plugin_Continue;
			
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
						if (GetHumanAndDefenderBotCount(TFTeam_Red) < trueMinPlayers)
						{
							PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
							return Plugin_Handled;
						}
					}
					case MISSION_INTERMEDIATE:
					{
						trueMinPlayers = minPlayers + 1 > defenderTeamSize ? defenderTeamSize : minPlayers + 1;
						
						if (GetHumanAndDefenderBotCount(TFTeam_Red) < trueMinPlayers)
						{
							PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
							return Plugin_Handled;
						}
					}
					case MISSION_ADVANCED:
					{
						trueMinPlayers = minPlayers + 2 > defenderTeamSize ? defenderTeamSize : minPlayers + 2;
						
						if (GetHumanAndDefenderBotCount(TFTeam_Red) < trueMinPlayers)
						{
							PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
							return Plugin_Handled;
						}
					}
					case MISSION_EXPERT:
					{
						trueMinPlayers = minPlayers + 3 > defenderTeamSize ? defenderTeamSize : minPlayers + 3;
						
						if (GetHumanAndDefenderBotCount(TFTeam_Red) < trueMinPlayers)
						{
							PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
							return Plugin_Handled;
						}
					}
					case MISSION_NIGHTMARE:
					{
						trueMinPlayers = minPlayers + 4 > defenderTeamSize ? defenderTeamSize : minPlayers + 4;
						
						if (GetHumanAndDefenderBotCount(TFTeam_Red) < trueMinPlayers)
						{
							PrintToChat(client, "%s More players are required.", PLUGIN_PREFIX);
							return Plugin_Handled;
						}
					}
					default:	LogError("Listener_Readystate: Unknown difficulty returned!");
				}
			}
		}
		case MANAGER_MODE_READY_BOTS:
		{
			if (TF2_GetClientTeam(client) != TFTeam_Red)
				return Plugin_Continue;
			
			if (!ShouldProcessCommand(client))
				return Plugin_Handled;
			
			if (g_bBotsEnabled)
			{
				//Bots already going, okay to pass
				return Plugin_Continue;
			}
			else
			{
				if (g_flNextReadyTime > GetGameTime())
				{
					PrintToChat(client, "%s You're going too fast!", PLUGIN_PREFIX);
					
					//Give more time to ready dawg
					return Plugin_Handled;
				}
				
#if defined CHANGETEAM_RESTRICTIONS
				float botBanTime = g_flEnableBotsCooldown[client] - GetGameTime();
				
				if (botBanTime > 0.0)
				{
					ReplyToCommand(client, "%s You cannot start the bots at this time.", PLUGIN_PREFIX);
					LogAction(client, -1, "MANAGER_MODE_READY_BOTS: %L tried to start the bots on cooldown. (%f seconds)", client, botBanTime);
					
					return Plugin_Handled;
				}
#endif
				
				if (GetCountOfPlayersChoosingBotClasses() > 0)
				{
					PrintToChat(client, "%s Someone is currently choosing the next team lineup.", PLUGIN_PREFIX);
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
					ManageDefenderBots(true);
					return Plugin_Handled;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action SoundHook_General(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (channel == SNDCHAN_VOICE && volume > 0.0 && BaseEntity_IsPlayer(entity))
	{
		if (StrContains(sample, "spy_mvm_LaughShort", false) != -1)
		{
			if (TF2_IsPlayerInCondition(entity, TFCond_Disguised) && !TF2_IsStealthed(entity))
			{
				/* Robots have robotic voices even when disguised so any
				defender bot that can see him right now will call him out */
				for (int i = 1; i <= MaxClients; i++)
				{
					if (i == entity)
						continue;
					
					if (!IsClientInGame(i))
						continue;
					
					if (g_bIsDefenderBot[i] == false)
						continue;
					
					if (GetClientTeam(entity) == GetClientTeam(i))
						continue;
					
					if (GetVectorDistance(GetAbsOrigin(i), WorldSpaceCenter(entity)) > redbots_manager_bot_hear_spy_range.FloatValue)
						continue;
					
					if (TF2_IsLineOfFireClear4(i, entity))
						RealizeSpy(i, entity);
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_CheckBotImbalance(Handle timer)
{
	if (!g_bBotsEnabled)
		return Plugin_Stop;
	
	switch (redbots_manager_mode.IntValue)
	{
		case MANAGER_MODE_MANUAL_BOTS, MANAGER_MODE_READY_BOTS:
		{
			//Bots are added pre-round, but we can also monitor them during the round
			if (GameRules_GetRoundState() != RoundState_BetweenRounds && GameRules_GetRoundState() != RoundState_RoundRunning)
				return Plugin_Stop;
			
			int defenderCount = GetHumanAndDefenderBotCount(TFTeam_Red);
			
			if (defenderCount < redbots_manager_defender_team_size.IntValue)
			{
				int amount = redbots_manager_defender_team_size.IntValue - defenderCount;
				AddBotsBasedOnPreferences(amount);
			}
		}
		case MANAGER_MODE_AUTO_BOTS:
		{
			//Bots are added when rhe wave begins, only monitor them during the round
			if (GameRules_GetRoundState() != RoundState_RoundRunning)
				return Plugin_Stop;
			
			int defenderCount = GetHumanAndDefenderBotCount(TFTeam_Red);
			
			if (defenderCount < redbots_manager_defender_team_size.IntValue)
			{
				int amount = redbots_manager_defender_team_size.IntValue - defenderCount;
				AddBotsBasedOnPreferences(amount);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_ForgetDetonatingPlayer(Handle timer, any data)
{
	//They should have detonated by now
	
	//Another player might have started detonating
	//Don't forget the newest one so soon
	if (g_iDetonatingPlayer == data)
		g_iDetonatingPlayer = -1;
	
	return Plugin_Stop;
}

public void DefenderBot_TouchPost(int entity, int other)
{
	//Call out enemy spies upon contact
	if (BaseEntity_IsPlayer(other) && GetClientTeam(other) != GetClientTeam(entity) && TF2_IsPlayerInCondition(other, TFCond_Disguised))
		RealizeSpy(entity, other);
}

bool FakeClientCommandThrottled(int client, const char[] command)
{
	if (m_flLastCommandTime[client] > GetGameTime())
		return false;
	
	FakeClientCommand(client, command);
	
	m_flLastCommandTime[client] = GetGameTime() + 0.4;
	
	return true;
}

void MakePlayerDance(int client)
{
	if (IsPlayerAlive(client))
	{
		//TODO: tauntem
	}
}

void ShowPlayerUpgrades(int client, int target, int slot)
{
	Address pAttr;
	float value;
	int attribIndexes[MAX_RUNTIME_ATTRIBUTES];
	
	switch (slot)
	{
		case -1: //Player
		{
			PrintToChat(client, "UPGRADES FOR %N", target);
			
			int count = TF2Attrib_ListDefIndices(target, attribIndexes, sizeof(attribIndexes));
			
			for (int i = 0; i < count; i++)
			{
				pAttr = TF2Attrib_GetByDefIndex(target, attribIndexes[i]);
				value = TF2Attrib_GetValue(pAttr);
				
				PrintToChat(client, "INDEX %d, VALUE %f", attribIndexes[i], value);
			}
		}
		case 0: //Primary
		{
			int weapon = GetPlayerWeaponSlot(target, TFWeaponSlot_Primary);
			
			if (weapon == -1)
			{
				PrintToChat(client, "%N doesn't have a primary weapon.", target);
				return;
			}
			
			PrintToChat(client, "UPGRADES FOR %N's primary", target);
			
			int count = TF2Attrib_ListDefIndices(weapon, attribIndexes, sizeof(attribIndexes));
			
			for (int i = 0; i < count; i++)
			{
				pAttr = TF2Attrib_GetByDefIndex(weapon, attribIndexes[i]);
				value = TF2Attrib_GetValue(pAttr);
				
				PrintToChat(client, "INDEX %d, VALUE %f", attribIndexes[i], value);
			}
		}
		case 1: //Secondary
		{
			int weapon = GetPlayerWeaponSlot(target, TFWeaponSlot_Secondary);
			
			if (weapon == -1)
			{
				PrintToChat(client, "%N doesn't have a secondary weapon.", target);
				return;
			}
			
			PrintToChat(client, "UPGRADES FOR %N's secondary", target);
			
			int count = TF2Attrib_ListDefIndices(weapon, attribIndexes, sizeof(attribIndexes));
			
			for (int i = 0; i < count; i++)
			{
				pAttr = TF2Attrib_GetByDefIndex(weapon, attribIndexes[i]);
				value = TF2Attrib_GetValue(pAttr);
				
				PrintToChat(client, "INDEX %d, VALUE %f", attribIndexes[i], value);
			}
		}
		case 2: //Melee
		{
			int weapon = GetPlayerWeaponSlot(target, TFWeaponSlot_Melee);
			
			if (weapon == -1)
			{
				PrintToChat(client, "%N doesn't have a melee weapon.", target);
				return;
			}
			
			PrintToChat(client, "UPGRADES FOR %N's melee", target);
			
			int count = TF2Attrib_ListDefIndices(weapon, attribIndexes, MAX_RUNTIME_ATTRIBUTES);
			
			for (int i = 0; i < count; i++)
			{
				pAttr = TF2Attrib_GetByDefIndex(weapon, attribIndexes[i]);
				value = TF2Attrib_GetValue(pAttr);
				
				PrintToChat(client, "INDEX %d, VALUE %f", attribIndexes[i], value);
			}
		}
	}
	
	PrintToChat(client, "%N currently has %d credits.", target, TF2_GetCurrency(target));
}

int GetHumanAndDefenderBotCount(TFTeam team)
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && (g_bIsDefenderBot[i] || !IsFakeClient(i)) && TF2_GetClientTeam(i) == team)
			count++;
	
	return count;
}

int GetCountOfPlayersChoosingBotClasses()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_bChoosingBotClasses[i])
			count++;
	
	return count;
}

/* Used to check players last command input
Usually for preventing palyers from sending a command multiple times in a single frame */
bool ShouldProcessCommand(int client)
{
	if (m_flLastCommandTime[client] > GetGameTime())
		return false;
	
	m_flLastCommandTime[client] = GetGameTime() + COMMAND_MAX_RATE;
	return true;
}

void RemoveAllDefenderBots(char[] reason = "", bool bDanceInstead = false)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bIsDefenderBot[i])
		{
			//We dance on the final wave instead
			if (bDanceInstead)
			{
				MakePlayerDance(i);
				continue;
			}
			
			KickClient(i, reason);
		}
	}
}

static int m_iFindNameTries[MAXPLAYERS + 1];
void SetRandomNameOnBot(int client)
{
	char newName[MAX_NAME_LENGTH]; GetRandomDefenderBotName(newName, sizeof(newName));
	const int maxTries = 10;
	
	if (m_adtBotNames.Length > 0 && DoesAnyPlayerUseThisName(newName) && m_iFindNameTries[client] < maxTries)
	{
		m_iFindNameTries[client]++;
		
		//Someone's already using my name, mock them for it and try again
		PrintToChatAll("%s : %s", newName, g_sPlayerUseMyNameResponse[GetRandomInt(0, sizeof(g_sPlayerUseMyNameResponse) - 1)]);
		SetRandomNameOnBot(client);
		
		return;
	}
	
	m_iFindNameTries[client] = 0;
	SetClientName(client, newName);
}

void GetRandomDefenderBotName(char[] buffer, int maxlen)
{
	if (m_adtBotNames.Length == 0)
	{
		// LogError("GetRandomDefenderBotName: No bot names were ever parsed!");
		strcopy(buffer, maxlen, "You forgot to give me a name!");
		return;
	}
	
	char botName[MAX_NAME_LENGTH]; m_adtBotNames.GetString(GetRandomInt(0, m_adtBotNames.Length - 1), botName, sizeof(botName));
	
	strcopy(buffer, maxlen, botName);
}

void ManageDefenderBots(bool bManage, bool bAddBots = true)
{
	if (bManage)
	{
		if (bAddBots)
			AddBotsFromChosenTeamComposition();
		
		CreateTimer(1.0, Timer_CheckBotImbalance, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		g_bBotsEnabled = true;
		
		PrintToChatAll("%s Bots have been enabled.", PLUGIN_PREFIX);
	}
	else
	{
		g_bBotsEnabled = false;
	}
}

void AddDefenderTFBot(int count, char[] class, char[] team, char[] difficulty, bool quotaManaged = false)
{
	//Send command as many times as needed because custom names aren't supported when adding multiple
	for (int i = 0; i < count; i++)
		ServerCommand("tf_bot_add %d %s %s %s %s %s", 1, class, team, difficulty, quotaManaged ? "" : "noquota", TFBOT_IDENTITY_NAME);
}

void AddRandomDefenderBots(int amount)
{
	PrintToChatAll("%s Adding %d bot(s)...", PLUGIN_PREFIX, amount);
	
	for (int i = 1; i <= amount; i++)
		AddDefenderTFBot(1, g_sRawPlayerClassNames[GetRandomInt(1, 9)], "red", "expert");
}

void AddBotsWithPresetTeamComp(int count = 6, int teamType = 0)
{
	int total = 0;
	
	for (int i = 0; i < count; i++)
	{
		//We're done here
		if (total >= count)
			break;
		
		//We asked for more than the array size, cycle back from the beginning
		if (i >= sizeof(g_sBotTeamCompositions[]))
			i = 0;
		
		AddDefenderTFBot(1, g_sBotTeamCompositions[teamType][i], "red", "expert");
		total++;
	}
}

void SetupSniperSpotHints()
{
	if (m_adtSniperHints.Length > 0)
	{
		for (int i = 0; i < m_adtSniperHints.Length; i++)
		{
			float vec[3]; m_adtSniperHints.GetArray(i, vec);
			int ent = CreateEntityByName("func_tfbot_hint");
			
			if (ent != -1)
			{
				DispatchKeyValueVector(ent, "origin", vec);
				// DispatchKeyValue(ent, "targetname", "db_sniper");
				DispatchKeyValue(ent, "team", "2");
				DispatchKeyValue(ent, "hint", "0");
				DispatchSpawn(ent);
			}
		}
	}
	else
	{
		//No custom hints specified, so we'll just override any existing ones
		int ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "func_tfbot_hint")) != -1)
			DispatchKeyValue(ent, "team", "0");
		
		LogError("SetupSniperSpotHints: No hints specified by configuration, overriding other hint entities!");
	}
}

void UpdateChosenBotTeamComposition(int caller = -1)
{
	//A player has already chosen their team, don't let it change
	if (g_bBotClassesLocked)
	{
		if (caller != -1)
			PrintToChat(caller, "%s Bot team lineup is locked for the next game.");
		
		return;
	}
	
	//If someone is selecting the team, don't change it
	if (GetCountOfPlayersChoosingBotClasses() > 0)
	{
		if (caller != -1)
			PrintToChat(caller, "%s Someone is currently choosing the bot team lineup.");
		
		return;
	}
	
	g_adtChosenBotClasses.Clear();
	
	int newBotsToAdd = redbots_manager_defender_team_size.IntValue - GetHumanAndDefenderBotCount(TFTeam_Red);
	
	if (newBotsToAdd < 1)
		return;
	
	ArrayList adtClassPref = new ArrayList(TF2_CLASS_MAX_NAME_LENGTH);
	
	CollectPlayerBotClassPreferences(adtClassPref);
	
	if (adtClassPref.Length > 0)
	{
		//Choose the class lineup based on players' preferences
		for (int i = 1; i <= newBotsToAdd; i++)
		{
			char class[TF2_CLASS_MAX_NAME_LENGTH]; adtClassPref.GetString(GetRandomInt(0, adtClassPref.Length - 1), class, sizeof(class));
			
			g_adtChosenBotClasses.PushString(class);
		}
	}
	else
	{
		//No prefernces, the lineup is random
		for (int i = 1; i <= newBotsToAdd; i++)
			g_adtChosenBotClasses.PushString(g_sRawPlayerClassNames[GetRandomInt(1, 9)]);
	}
	
	delete adtClassPref;
	
	if (caller != -1)
		PrintToChatAll("%s %N changed the bot team lineup", PLUGIN_PREFIX, caller);
	else
		PrintToChatAll("%s Bot lineup changed", PLUGIN_PREFIX);
}

void AddBotsFromChosenTeamComposition()
{
	char class[TF2_CLASS_MAX_NAME_LENGTH];
	
	for (int i = 0; i < g_adtChosenBotClasses.Length; i++)
	{
		g_adtChosenBotClasses.GetString(i, class, sizeof(class));
		AddDefenderTFBot(1, class, "red", "expert");
	}
	
	//Once we add them it's not locked anymore
	g_bBotClassesLocked = false;
	
	PrintToChatAll("%s Added %d bot(s).", PLUGIN_PREFIX, g_adtChosenBotClasses.Length);
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
	
	eMissionDifficulty type = Config_GetMissionDifficultyFromName(missionName);
	
	//No config file specified a difficulty, search for one ourselves
	if (type == MISSION_UNKNOWN)
	{
		char mapName[PLATFORM_MAX_PATH]; GetCurrentMap(mapName, sizeof(mapName));
		
		//Searching by prefix or suffix
		if (StrEqual(missionName, mapName) || StrContains(missionName, "_norm_", false) != -1)
		{
			//If the mission name is the same as the map's name, it's typically a normal mission
			type = MISSION_NORMAL;
		}
		else if (StrContains(missionName, "_intermediate", false) != -1 || StrContains(missionName, "_int_", false) != -1)
		{
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

void Config_LoadMap()
{
	m_adtSniperHints.Clear();
	
	char mapName[PLATFORM_MAX_PATH]; GetCurrentMap(mapName, sizeof(mapName));
	char filePath[PLATFORM_MAX_PATH]; BuildPath(Path_SM, filePath, sizeof(filePath), "configs/defenderbots/map/%s.cfg", mapName);
	
	KeyValues kv = new KeyValues("MapConfig");
	
	if (!kv.ImportFromFile(filePath))
	{
		CloseHandle(kv);
		LogError("Config_LoadMap: File not found (%s)", filePath);
		return;
	}
	
	if (kv.JumpToKey("SniperHint"))
	{
		do
		{
			float vec[3]; kv.GetVector("origin", vec);
			m_adtSniperHints.PushArray(vec);
		} while (kv.GotoNextKey(false));
		
		kv.GoBack();
	}
	
	CloseHandle(kv);
	
#if defined TESTING_ONLY
	LogMessage("Config_LoadMap: Found %d locations for SniperHint", m_adtSniperHints.Length);
#endif
}

void Config_LoadBotNames()
{
	char filePath[PLATFORM_MAX_PATH]; BuildPath(Path_SM, filePath, sizeof(filePath), "configs/defenderbots/bot_names.txt");
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
				LogMessage("Config_GetMissionDifficultyFromName: Could not locate file %s. Skipping...", filePath);
			
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