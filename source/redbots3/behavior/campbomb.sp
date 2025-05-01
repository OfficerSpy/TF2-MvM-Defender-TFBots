#define BOMB_HATCH_RANGE_OKAY	5000.0
#define BOMB_HATCH_RANGE_CRITICAL	1000.0
#define BOMB_GUARD_RADIUS	400.0

BehaviorAction CTFBotCampBomb()
{
	BehaviorAction action = ActionsManager.Create("DefenderCampBomb");
	
	action.OnStart = CTFBotCampBomb_OnStart;
	action.Update = CTFBotCampBomb_Update;
	
	return action;
}

public Action CTFBotCampBomb_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_SENTRYHERE);
	
	return action.Continue();
}

public Action CTFBotCampBomb_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	switch (TF2_GetPlayerClass(actor))
	{
		case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
		{
			//Tank is more important
			if (CTFBotAttackTank_SelectTarget(actor))
				return action.ChangeTo(CTFBotAttackTank(), "Tank inbound");
		}
	}
	
	int flag = FindBombNearestToHatch();
	
	if (flag == -1)
		return action.Done("No bomb");
	
	if (BaseEntity_GetOwnerEntity(flag) != -1)
	{
		//Someone picked up the bomb!
		return action.ChangeTo(CTFBotDefenderAttack(), "Bomb is taken");
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float bombPosition[3]; bombPosition = WorldSpaceCenter(flag);
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
	
	//Close-range has to get up and personal with them
	if (myWeapon != -1 && (TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_FLAMETHROWER || IsMeleeWeapon(myWeapon)))
	{
		int nearest = GetEnemyPlayerNearestToPosition(actor, bombPosition, BOMB_GUARD_RADIUS);
		
		if (nearest != -1)
		{
			if (m_flRepathTime[actor] <= GetGameTime())
			{
				m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.5, 1.0);
				m_pPath[actor].ComputeToTarget(myBot, nearest);
			}
			
			m_pPath[actor].Update(myBot);
			
			return action.Continue();
		}
	}
	
	//Move towards the bomb's current area if we're too far or can't see it
	if (myBot.IsRangeGreaterThanEx(bombPosition, BOMB_GUARD_RADIUS) || !IsLineOfFireClearPosition(actor, GetEyePosition(actor), bombPosition))
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			m_pPath[actor].ComputeToPos(myBot, bombPosition);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
	
	if (threat)
		EquipBestWeaponForThreat(actor, threat);
	
	return action.Continue();
}

bool CTFBotCampBomb_IsPossible(int client)
{
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Scout, TFClass_Medic:
		{
			//We're not very useful for this
			return false;
		}
	}
	
	int flag = FindBombNearestToHatch();
	
	if (flag == -1)
		return false;
	
	if (BaseEntity_GetOwnerEntity(flag) != -1)
	{
		//No point in camping since DefenderAttack goes for the bomb carrier
		return false;
	}
	
	// float hatchPosition[3]; hatchPosition = GetBombHatchPosition();
	float bombPosition[3]; bombPosition = WorldSpaceCenter(flag);
	
	/* if (GetVectorDistance(hatchPosition, bombPosition) > BOMB_HATCH_RANGE_OKAY)
	{
		//The bomb is stil pretty far from the hatch
		return false;
	} */
	
	int iEnt = -1;
	const float maxWatchRadius = 1000.0;
	
	while ((iEnt = FindEntityByClassname(iEnt, "obj_sentrygun")) != -1)
	{
		if (BaseEntity_GetTeamNumber(iEnt) != GetClientTeam(client))
			continue;
		
		if (GetVectorDistance(bombPosition, WorldSpaceCenter(iEnt)) <= maxWatchRadius)
		{
			//There;s a sentry watching the bomb
			return false;
		}
	}
	
	//There;s too many of us doing this behavior
	if (GetCountOfBotsWithNamedAction("DefenderCampBomb") > 0)
		return false;
	
	return true;
}