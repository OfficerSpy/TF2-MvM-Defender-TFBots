void InitGameEventHooks()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("mvm_wave_failed", Event_MvmWaveFailed);
	HookEvent("mvm_wave_complete", Event_MvmWaveComplete);
	HookEvent("revive_player_notify", Event_RevivePlayerNotify);
	HookEvent("mvm_begin_wave", Event_MvmWaveBegin);
}

static void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	//We're not being revived if we spawned in
	g_bIsBeingRevived[client] = false;
	
	if (TF2_GetClientTeam(client) == TFTeam_Red && IsTFBotPlayer(client))
		CreateTimer(0.2, Timer_PlayerSpawn, client, TIMER_FLAG_NO_MAPCHANGE);
}

static void Event_MvmWaveFailed(Event event, const char[] name, bool dontBroadcast)
{
	if (redbots_manager_kick_bots.BoolValue)
		RemoveAllDefenderBots("BotManager3: Wave failed!");
	
	SetupSniperSpotHints();
	
	if (redbots_manager_mode.IntValue == MANAGER_MODE_READY_BOTS)
	{
		//Global cooldown before players can ready up again
		g_flNextReadyTime = GetGameTime() + redbots_manager_ready_cooldown.FloatValue;
	}
}

public void Event_MvmWaveComplete(Event event, const char[] name, bool dontBroadcast)
{
	if (redbots_manager_kick_bots.BoolValue)
		RemoveAllDefenderBots("BotManager3: Wave complete!", IsFinalWave());
}

public void Event_RevivePlayerNotify(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("entindex");
	
	//This event indicates someone attempted a revive on the client
	g_bIsBeingRevived[client] = true;
}

public void Event_MvmWaveBegin(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_bIsDefenderBot[i] && IsPlayerAlive(i))
		{
			//Rethink what we're supposed to do
			ResetIntentionInterface(i);
		}
	}
	
	if (redbots_manager_mode.IntValue == MANAGER_MODE_AUTO_BOTS)
	{
		CreateTimer(0.1, Timer_CheckBotImbalance, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		g_bAreBotsEnabled = true;
	}
}

static Action Timer_PlayerSpawn(Handle timer, any data)
{
	if (!IsClientInGame(data) || !IsTFBotPlayer(data) || TF2_GetClientTeam(data) != TFTeam_Red)
		return Plugin_Stop;
	
	char clientName[MAX_NAME_LENGTH]; GetClientName(data, clientName, sizeof(clientName));
	
	//Identify if the bot is ours, ignore the ones we do know so this is only done once
	if (g_bIsDefenderBot[data] == false && StrContains(clientName, TFBOT_IDENTITY_NAME) != -1)
	{
		g_bIsDefenderBot[data] = true;
		
		SetRandomNameOnBot(data);
		
		RefundPlayerUpgrades(data); //Give current wave money and forces respawn
		g_bHasBoughtUpgrades[data] = false;
		
		SDKHook(data, SDKHook_Touch, DefenderBot_Touch);
		SDKHook(data, SDKHook_TouchPost, DefenderBot_TouchPost);
		
		DHooks_DefenderBot(data);
		
		//For some reason, custom weapons aren't given unless the player respawns again
		if (redbots_manager_use_custom_loadouts.BoolValue)
			TF2_RespawnPlayer(data);
		
		//Custom loadouts runs it own check for the sniper's primary
		if (!redbots_manager_use_custom_loadouts.BoolValue)
			SetMission(data, CTFBot_MISSION_SNIPER);
		
		//Let medic bots use their shields
		VS_AddBotAttribute(data, CTFBot_PROJECTILE_SHIELD);
		
		//We stop here cause of the respawn, so this whole function will be called again anyways
		return Plugin_Stop;
	}
	
	return Plugin_Stop;
}