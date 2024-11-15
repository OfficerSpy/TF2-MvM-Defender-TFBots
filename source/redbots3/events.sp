void InitGameEventHooks()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("mvm_wave_failed", Event_MvmWaveFailed);
	HookEvent("mvm_wave_complete", Event_MvmWaveComplete);
	HookEvent("revive_player_notify", Event_RevivePlayerNotify);
	HookEvent("mvm_begin_wave", Event_MvmWaveBegin);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_used_powerup_bottle", Event_PlayerUsedPowerupBottle);
	HookEvent("post_inventory_application", Event_PostInventoryApplication);
	HookEvent("mvm_mission_update", Event_MvmMissionUpdate, EventHookMode_Pre);
}

static void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (TF2_GetClientTeam(client) == TFTeam_Red && IsTFBotPlayer(client))
		CreateTimer(0.2, Timer_PlayerSpawn, client, TIMER_FLAG_NO_MAPCHANGE);
	
	if (g_bIsDefenderBot[client])
	{
		g_bIsBeingRevived[client] = false;
		g_iBuyUpgradesNumber[client] = CanBuyUpgradesNow(client) ? GetRandomInt(1, 100) : 0;
		
		if (redbots_manager_debug.BoolValue)
			PrintToChatAll("[Event_PlayerSpawn] g_iBuyUpgradesNumber[%d] = %d", client, g_iBuyUpgradesNumber[client]);
	}
}

static void Event_MvmWaveFailed(Event event, const char[] name, bool dontBroadcast)
{
	if (redbots_manager_kick_bots.BoolValue)
	{
		RemoveAllDefenderBots("BotManager3: Wave failed!");
		ManageDefenderBots(false);
		CreateTimer(0.1, Timer_UpdateChosenBotTeamComposition, _, TIMER_FLAG_NO_MAPCHANGE);
		PrintToChatAll("%s Use command !viewbotlineup to view the next bot team composition", PLUGIN_PREFIX);
	}
	
	SetupSniperSpotHints();
	
	if (redbots_manager_mode.IntValue == MANAGER_MODE_READY_BOTS)
	{
		//Global cooldown before players can ready up again
		g_flNextReadyTime = GetGameTime() + redbots_manager_ready_cooldown.FloatValue;
	}
	
	CreateTimer(0.1, Timer_WaveFailure, _, TIMER_FLAG_NO_MAPCHANGE);
}

static void Event_MvmWaveComplete(Event event, const char[] name, bool dontBroadcast)
{
	if (redbots_manager_kick_bots.BoolValue)
	{
		RemoveAllDefenderBots("BotManager3: Wave complete!", IsFinalWave());
		ManageDefenderBots(false);
		CreateTimer(0.1, Timer_UpdateChosenBotTeamComposition, _, TIMER_FLAG_NO_MAPCHANGE);
		PrintToChatAll("%s Use command !viewbotlineup to view the next bot team composition", PLUGIN_PREFIX);
	}
	
#if defined MOD_REQUEST_CREDITS
	bool bRequestCredits = redbots_manager_bot_request_credits.BoolValue;
#endif
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bIsDefenderBot[i])
		{
			//Wave complete, rethink what we should do
			ResetIntentionInterface(i);
			
#if defined MOD_REQUEST_CREDITS
			if (bRequestCredits)
				FakeClientCommand(i, "sm_requestcredits");
#endif
		}
	}
}

static void Event_RevivePlayerNotify(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("entindex");
	
	//This event indicates someone attempted a revive on the client
	g_bIsBeingRevived[client] = true;
}

static void Event_MvmWaveBegin(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bIsDefenderBot[i] && IsPlayerAlive(i))
		{
			//Looking for sniping spots, don't disturb
			if (ActionsManager.GetAction(i, "SniperLurk") != INVALID_ACTION)
				continue;
			
			//Rethink what we're supposed to do
			ResetIntentionInterface(i);
		}
	}
	
	if (redbots_manager_mode.IntValue == MANAGER_MODE_AUTO_BOTS)
		ManageDefenderBots(true);
}

static void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	TFTeam team = view_as<TFTeam>(event.GetInt("team"));
	TFTeam oldTeam = view_as<TFTeam>(event.GetInt("oldteam"));
	bool isDisconnect = event.GetBool("disconnect");
	
	if (!IsFakeClient(client))
	{
		/* When changing teams, update bot team composition for
		- red player disconnected
		- player joined red
		- player left red */
		if ((isDisconnect && oldTeam == TFTeam_Red) || team == TFTeam_Red || oldTeam == TFTeam_Red)
			CreateTimer(0.1, Timer_UpdateChosenBotTeamComposition, _, TIMER_FLAG_NO_MAPCHANGE);
		
#if defined CHANGETEAM_RESTRICTIONS
		if (!isDisconnect && team == TFTeam_Red && oldTeam == TFTeam_Blue && !CheckCommandAccess(client, NULL_STRING, ADMFLAG_GENERIC, true))
		{
			//Switching from BLUE to RED will temporarily ban the player from starting the bots
			if (g_flEnableBotsCooldown[client] <= GetGameTime())
				g_flEnableBotsCooldown[client] = GetGameTime() + 30.0;
			else
				g_flEnableBotsCooldown[client] += 10.0;
		}
#endif
	}
}

static void Event_PlayerUsedPowerupBottle(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("player");
	
	if (g_bIsDefenderBot[client])
	{
		int powerupType = event.GetInt("type");
		
		if (powerupType == POWERUP_BOTTLE_REFILL_AMMO)
			SetSapperCooldown(client, 0.0);
	}
}

static void Event_PostInventoryApplication(Event event, const char[] name, bool dontBroadcast)
{
	//If this event happened, someone regenereated and thus refilled their ammo
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (g_bIsDefenderBot[client])
		SetSapperCooldown(client, 0.0);
}

static void Event_MvmMissionUpdate(Event event, const char[] name, bool dontBroadcast)
{
	//TFBot spies fire this event on death, so block it when a defender bot dies
	if (g_bSpyKilled)
		event.BroadcastDisabled = true;
}

static Action Timer_PlayerSpawn(Handle timer, any data)
{
	if (!IsClientInGame(data) || !IsTFBotPlayer(data) || TF2_GetClientTeam(data) != TFTeam_Red)
		return Plugin_Stop;
	
	if (g_bIsDefenderBot[data])
	{
#if defined MOD_REQUEST_CREDITS
		//Mainly for wave failures, try to request credits again
		if (redbots_manager_bot_request_credits.BoolValue && GameRules_GetRoundState() == RoundState_BetweenRounds)
			FakeClientCommand(data, "sm_requestcredits");
#endif
		
		if (redbots_manager_debug.BoolValue)
			PrintToChatAll("[Timer_PlayerSpawn] %N's currency: %d", data, TF2_GetCurrency(data));
		
		//We already made this guy into our bot, so do nothing
		return Plugin_Stop;
	}
	
	char clientName[MAX_NAME_LENGTH]; GetClientName(data, clientName, sizeof(clientName));
	
	//Identify if the bot is ours
	if (StrContains(clientName, TFBOT_IDENTITY_NAME) != -1)
	{
		g_bIsDefenderBot[data] = true;
		g_bHasBoughtUpgrades[data] = false;
		
		if (redbots_manager_use_custom_loadouts.BoolValue)
		{
			//NOTE: for some reason, custom weapons aren't given unless the player respawns again
			TF2_RespawnPlayer(data);
		}
		else
		{
			//Not using custom loadouts, so we will only ever be using a sniper rifle
			//NOTE: custom loadouts runs it own check for the sniper's primary
			if (TF2_GetPlayerClass(data) == TFClass_Sniper)
				SetMission(data, CTFBot_MISSION_SNIPER);
		}
		
		//Let medic bots use their shields
		VS_AddBotAttribute(data, CTFBot_PROJECTILE_SHIELD);
		
		//Bots don't get their credits set when joining red because CTFGameRules::GetTeamAssignmentOverride ignores bot players
		//Set their credits manually to what they should have like human players
		TF2_SetCurrency(data, GetStartingCurrency(g_iPopulationManager) + GetAcquiredCreditsOfAllWaves());
		
		//Set the bot's field-of-view to 90
		//Its vision FOV will update in CTFBotMainAction::Update based on the property m_iFOV
		SetFakeClientConVar(data, "fov_desired", "90");
		
		SDKHook(data, SDKHook_TouchPost, DefenderBot_TouchPost);
		
		DHooks_DefenderBot(data);
		
#if defined IDLEBOT_AIMING
		//In this build we handle the bot's aiming manually, so don't have any of its nextbot aiming interfere with ours
		VS_AddBotAttribute(data, CTFBot_IGNORE_ENEMIES);
#endif
		
#if defined MOD_REQUEST_CREDITS
		if (redbots_manager_bot_request_credits.BoolValue)
			FakeClientCommand(data, "sm_requestcredits");
#endif
		
#if defined MOD_CUSTOM_ATTRIBUTES
		if (TF2Attrib_IsValidAttributeName("cannot be sapped"))
			TF2Attrib_SetByName(data, "cannot be sapped", 1.0);
#endif
		
		SetRandomNameOnBot(data);
	}
	
	return Plugin_Stop;
}

static Action Timer_WaveFailure(Handle timer)
{
	if (GameRules_GetRoundState() != RoundState_BetweenRounds)
		return Plugin_Stop;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bIsDefenderBot[i])
		{
			/* NOTE: this isn't actually necessary, but the reason why I'm doing this is so we
			or the population manager forgets about the bots' upgrades so they can 
			just go and buy upgrades again in their upgrade behavior, though this is really 
			just for the bots that failed a wave but were not kicked */
			if (g_bHasUpgraded[i])
			{
				g_bHasBoughtUpgrades[i] = false;
				RefundPlayerUpgrades(i);
				g_bHasUpgraded[i] = false;
			}
		}
	}
	
	return Plugin_Stop;
}

static Action Timer_UpdateChosenBotTeamComposition(Handle timer)
{
	UpdateChosenBotTeamComposition();
	
	return Plugin_Stop;
}