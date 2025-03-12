int m_iTarget[MAXPLAYERS + 1];
float m_flNextMarkTime[MAXPLAYERS + 1];

BehaviorAction CTFBotMarkGiant()
{
	BehaviorAction action = ActionsManager.Create("DefenderMarkGiant");
	
	action.OnStart = CTFBotMarkGiant_OnStart;
	action.Update = CTFBotMarkGiant_Update;
	action.OnEnd = CTFBotMarkGiant_OnEnd;
	
	return action;
}

public Action CTFBotMarkGiant_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	int weapon = GetMarkForDeathWeapon(actor);
	
	if (weapon == INVALID_ENT_REFERENCE)
		return action.Done("Don't have a mark-for-death weapon");
	
	ArrayList potential_victims = new ArrayList();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == actor)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (IsPlayerMarkable(actor, i))
			potential_victims.Push(i);
	}
	
	if (potential_victims.Length == 0)
	{
		delete potential_victims;
		m_iTarget[actor] = -1;
		return action.Done("No eligible mark victims");
	}
	
	m_iTarget[actor] = potential_victims.Get(GetRandomInt(0, potential_victims.Length - 1));
	
	delete potential_victims;
	
	EquipWeaponSlot(actor, TFWeaponSlot_Melee);
	
	return action.Continue();
}

public Action CTFBotMarkGiant_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidClientIndex(m_iTarget[actor]) || !IsPlayerAlive(m_iTarget[actor]))
	{
		m_iTarget[actor] = -1;
		return action.Done("Mark target is no longer valid");
	}
	
	if (!IsPlayerMarkable(actor, m_iTarget[actor]))
	{
		m_iTarget[actor] = -1;
		return action.Done("Mark target is no longer markable");
	}
	
	float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
	float targetOrigin[3]; GetClientAbsOrigin(m_iTarget[actor], targetOrigin);
	
	float dist_to_target = GetVectorDistance(myOrigin, targetOrigin);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (dist_to_target < 512.0)
	{
		//TODO: aim directly on target instead of doing this dumb shit
		IVision myVision = myBot.GetVisionInterface();
		
		if (myVision.GetKnownCount(TFTeam_Blue) > 1 || myVision.GetKnown(m_iTarget[actor]) == NULL_KNOWN_ENTITY)
		{
			myVision.ForgetAllKnownEntities();
			myVision.AddKnownEntity(m_iTarget[actor]);
		}
	}
	
	//TODO: stop pathing once we reached the desired attack range
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToTarget(myBot, m_iTarget[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotMarkGiant_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_flNextMarkTime[actor] = GetGameTime() + 30.0;
	m_iTarget[actor] = -1;
	// UpdateLookAroundForEnemies(actor, true);
}

int GetMarkForDeathWeapon(int player)
{
	for (int i = 0; i < 8; i++) 
	{
		int weapon = GetPlayerWeaponSlot(player, i);
		
		if (!IsValidEntity(weapon)) 
			continue;
		
		int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")
		
		if (m_iItemDefinitionIndex == 355) //Fan O'War
			return weapon;
	}
	
	return INVALID_ENT_REFERENCE;
}

bool IsPlayerMarkable(int bot, int victim)
{
	if (m_flNextMarkTime[bot] < GetGameTime())
		return false;

	/* must be ingame */
	if (!IsClientInGame(victim))
		return false;

	/* must be alive */
	if (!IsPlayerAlive(victim)) 
		return false;
	
	/* must be an enemy */
	if (BaseEntity_GetTeamNumber(bot) == BaseEntity_GetTeamNumber(victim)) 
		return false;
	
	/* must be a giant */
	if (!TF2_IsMiniBoss(victim)) 
		return false;
	
	/* must not be a sentry buster */
	if (IsSentryBusterRobot(victim))
		return false;
	
	/* must not already be marked for death */
	if (TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeath)) 
		return false;
	
	/* must not be invulnerable */
	if (TF2_IsInvulnerable(victim))
		return false;
	
	return true;
}

bool CTFBotMarkGiant_IsPossible(int actor)
{
	if (GetMarkForDeathWeapon(actor) == INVALID_ENT_REFERENCE) 
		return false;
	
	bool victim_exists = false;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == actor)
			continue;

		if(!IsClientConnected(i))
			continue;
		
		if (IsPlayerMarkable(actor, i)) 
			victim_exists = true;
	}
	
	return victim_exists;
}