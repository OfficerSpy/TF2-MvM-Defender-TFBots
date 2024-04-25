static DynamicHook m_hMyTouch;
static DynamicHook m_hIsBot;
static DynamicHook m_hEventKilled;
static DynamicHook m_hIsVisibleEntityNoticed;
static DynamicHook m_hIsIgnored;

static bool m_bTouchCredits;
static bool m_bPlayerKilled;
static bool m_bEngineerKilled;

bool InitDHooks(GameData hGamedata)
{
	int failCount = 0;
	
#if defined METHOD_MVM_UPGRADES
	//We could not find the address to g_MannVsMachineUpgrades, use this detour to fetch it instead
	//NOTE: this will not support late-load!
	if (!g_pMannVsMachineUpgrades)
		if (!RegisterDetour(hGamedata, "CMannVsMachineUpgradeManager::LoadUpgradesFile", _, DHookCallback_LoadUpgradesFile_Post))
			failCount++;
#endif
	
	if (!RegisterDetour(hGamedata, "CTFPlayer::ManageRegularWeapons", DHookCallback_ManageRegularWeapons_Pre, DHookCallback_ManageRegularWeapons_Post))
		failCount++;
	
	if (!RegisterHook(hGamedata, m_hMyTouch, "CItem::MyTouch"))
	{
		LogError("Failed to setup DynamicHook for CItem::MyTouch!");
		failCount++;
	}
	
	if (!RegisterHook(hGamedata, m_hIsBot, "CBasePlayer::IsBot"))
	{
		LogError("Failed to setup DynamicHook for CBasePlayer::IsBot!");
		failCount++;
	}
	
	if (!RegisterHook(hGamedata, m_hEventKilled, "CBaseEntity::Event_Killed"))
	{
		LogError("Failed to setup DynamicHook for CBaseEntity::Event_Killed!");
		failCount++;
	}
	
	if (!RegisterHook(hGamedata, m_hIsVisibleEntityNoticed, "IVision::IsVisibleEntityNoticed"))
	{
		LogError("Failed to setup DynamicHook for IVision::IsVisibleEntityNoticed!");
		failCount++;
	}
	
	if (!RegisterHook(hGamedata, m_hIsIgnored, "IVision::IsIgnored"))
	{
		LogError("Failed to setup DynamicHook for IVision::IsIgnored!");
		failCount++;
	}
	
	if (failCount > 0)
	{
		LogError("InitDHooks: found %d problems with gamedata!", failCount);
		return false;
	}
	
	return true;
}

public void DHooks_OnEntityCreated(int entity, const char[] classname)
{
	if (StrContains(classname, "item_currencypack_") != -1)
	{
		m_hMyTouch.HookEntity(Hook_Pre, entity, DHookCallback_MyTouch_Pre);
		m_hMyTouch.HookEntity(Hook_Post, entity, DHookCallback_MyTouch_Post);
	}
}

public void DHooks_DefenderBot(int client)
{
	m_hIsBot.HookEntity(Hook_Pre, client, DHookCallback_IsBot_Pre);
	m_hEventKilled.HookEntity(Hook_Pre, client, DHookCallback_EventKilled_Pre);
	m_hEventKilled.HookEntity(Hook_Post, client, DHookCallback_EventKilled_Post);
	
	INextBot bot = CBaseNPC_GetNextBotOfEntity(client);
	Address vision = view_as<Address>(bot.GetVisionInterface());
	
	if (vision != Address_Null)
	{
		m_hIsVisibleEntityNoticed.HookRaw(Hook_Pre, vision, DHookCallback_IsVisibleEntityNoticed_Pre);
		m_hIsVisibleEntityNoticed.HookRaw(Hook_Post, vision, DHookCallback_IsVisibleEntityNoticed_Post);
		m_hIsIgnored.HookRaw(Hook_Pre, vision, DHookCallback_IsIgnored_Pre);
	}
	else
	{
		LogError("DHooks_DefenderBot: IVision is NULL! Bot vision will not be hooked.");
	}
}

static MRESReturn DHookCallback_LoadUpgradesFile_Post(Address pThis)
{
	if (!g_pMannVsMachineUpgrades)
	{
		g_pMannVsMachineUpgrades = pThis;
		LogMessage("DHookCallback_LoadUpgradesFile_Post: Found \"g_MannVsMachineUpgrades\" @ 0x%X", g_pMannVsMachineUpgrades);
	}
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_ManageRegularWeapons_Pre(int pThis)
{
	if (redbots_manager_use_custom_loadouts.BoolValue)
	{
		/* Problem: bots will lose their items when buying upgrades so here we just block the function from executing
		However this should only be done when they're currently purchasing upgrades
		otherwise we run into a terrible problem with bots items being broken when they spawn in
		
		BACKTRACE REFERENCE:
		CUpgrades::PlayerPurchasingUpgrade
			CTFPlayer::Regenerate
				CTFPlayer::InitClass
					CTFPlayer::GiveDefaultItems
						CTFPlayer::ManageRegularWeapons */
		
		if (g_bIsDefenderBot[pThis] && IsPlayerAlive(pThis) && TF2_IsInUpgradeZone(pThis))
			return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_ManageRegularWeapons_Post(int pThis)
{
	if (redbots_manager_use_custom_loadouts.BoolValue)
	{
		if (g_bIsDefenderBot[pThis] && IsPlayerAlive(pThis) && !TF2_IsInUpgradeZone(pThis))
		{
			if (g_bHasCustomLoadout[pThis])
			{
				//There actually has to be a delay in frames, otherwise we run into the broken items problem again
				CreateTimer(0.1, Timer_GiveCustomLoadout, pThis, TIMER_FLAG_NO_MAPCHANGE);
			}
			else
			{
				PrepareCustomLoadout(pThis);
				CreateTimer(0.1, Timer_GiveCustomLoadout, pThis, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	
	return MRES_Ignored;
}

// VIRTUAL HOOKS
// Only hooked on certain entities, which in this case should only be our bots

static MRESReturn DHookCallback_MyTouch_Pre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	int player = hParams.Get(1);
	
	if (g_bIsDefenderBot[player])
		m_bTouchCredits = true;
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_MyTouch_Post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	int player = hParams.Get(1);
	
	if (g_bIsDefenderBot[player])
		m_bTouchCredits = false;
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_IsBot_Pre(int pThis, DHookReturn hReturn)
{
	if (IsClientInGame(pThis) && g_bIsDefenderBot[pThis])
	{
		if (m_bTouchCredits || m_bPlayerKilled)
		{
			hReturn.Value = false;
			
			return MRES_Supercede;
		}
	}
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_EventKilled_Pre(int pThis, DHookParam hParams)
{
	if (g_bIsDefenderBot[pThis])
	{
		m_bPlayerKilled = true;
		
		if (TF2_GetPlayerClass(pThis) == TFClass_Engineer)
		{
			//CTFBot::Event_Killed pretty much disbands the buildings from the engineer bot when it dies in mvm mode
			//Change to another class besides engineer before this death occurs
			//NOTE: this will mess with achievement data for class-specific requirements, but this shouldn't matter in mvm
			TF2_SetPlayerClass(pThis, TFClass_Soldier, _, false);
			m_bEngineerKilled = true;
		}
	}
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_EventKilled_Post(int pThis, DHookParam hParams)
{
	if (g_bIsDefenderBot[pThis])
	{
		m_bPlayerKilled = false;
		
		if (m_bEngineerKilled)
		{
			TF2_SetPlayerClass(pThis, TFClass_Engineer, _, false);
			m_bEngineerKilled = false;
		}
	}
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_IsVisibleEntityNoticed_Pre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	/* Doing this actually applies a few quirks here...
	- disguised spy is never forgotten unless redisguised
	- sapping anything around us will call out the spy
	- changing disguises in front of us calls out the spy */
	GameRules_SetProp("m_bPlayingMannVsMachine", false);
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_IsVisibleEntityNoticed_Post(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	//At the end of the day, we're still playing mvm
	GameRules_SetProp("m_bPlayingMannVsMachine", true);
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_IsIgnored_Pre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	int subject = hParams.Get(1);
	int myself = view_as<IVision>(pThis).GetBot().GetEntity();
	
	if (BaseEntity_IsPlayer(subject) && TF2_GetClientTeam(subject) != TFTeam_Red)
	{
		if (IsSentryBusterRobot(subject))
		{
			//We don't really care about sentry busters
			hReturn.Value = true;
			
			return MRES_Supercede;
		}
		
		if (TF2_IsInvulnerable(subject))
		{
			if (TF2_IsPlayerInCondition(subject, TFCond_ImmuneToPushback))
			{
				//Always ignored, since we can't actually do anything about them
				hReturn.Value = true;
				
				return MRES_Supercede;
			}
			
			int myWeapon = BaseCombatCharacter_GetActiveWeapon(myself);
			
			switch (TF2Util_GetWeaponID(myWeapon))
			{
				case TF_WEAPON_ROCKETLAUNCHER, TF_WEAPON_GRENADELAUNCHER, TF_WEAPON_PIPEBOMBLAUNCHER, TF_WEAPON_DIRECTHIT:
				{
					//Don't ignore when using these, as they have knockback potential
				}
				default:
				{
					//We will ignore uber enemies for threat selection because we otherwise waste ammo
					hReturn.Value = true;
					
					return MRES_Supercede;
				}
			}
		}
	}
	
	return MRES_Ignored;
}

static bool RegisterDetour(GameData gd, const char[] fnName, DHookCallback pre = INVALID_FUNCTION, DHookCallback post = INVALID_FUNCTION)
{
	DynamicDetour hDetour;
	hDetour = DynamicDetour.FromConf(gd, fnName);
	
	if (hDetour)
	{
		if (pre != INVALID_FUNCTION)
			hDetour.Enable(Hook_Pre, pre);
		
		if (post != INVALID_FUNCTION)
			hDetour.Enable(Hook_Post, post);
	}
	else
	{
		delete hDetour;
		LogError("Failed to detour \"%s\"!", fnName);
		
		return false;
	}
	
	delete hDetour;
	
	return true;
}

static bool RegisterHook(GameData gd, DynamicHook &hook, const char[] fnName)
{
	hook = DynamicHook.FromConf(gd, fnName);
	
	return hook != null;
}