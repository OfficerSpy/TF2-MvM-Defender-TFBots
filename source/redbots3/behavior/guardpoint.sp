float m_vecPointDefendArea[MAXPLAYERS + 1][3];

BehaviorAction CTFBotGuardPoint()
{
	BehaviorAction action = ActionsManager.Create("DefenderGuardPoint");
	
	action.OnStart = CTFBotGuardPoint_OnStart;
	action.Update = CTFBotGuardPoint_Update;
	action.OnEnd = CTFBotGuardPoint_OnEnd;
	action.OnTerritoryContested = CTFBotGuardPoint_OnTerritoryContested;
	action.OnTerritoryLost = CTFBotGuardPoint_OnTerritoryLost;
	
	return action;
}

public Action CTFBotGuardPoint_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	int point = GetDefendablePointTrigger(TF2_GetClientTeam(actor));
	
	if (point == -1)
		return action.ChangeTo(CTFBotDefenderAttack(), "No point found");
	
	AreasCollector hAreas = TheNavMesh.CollectAreasInRadius(GetAbsOrigin(point), 300.0);
	float center[3];
	
	for (int i = 0; i < hAreas.Count(); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(hAreas.Get(i));
		
		//Don't go in spawn room
		if (area.HasAttributeTF(RED_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		area.GetCenter(center);
		
		if (!IsPathToVectorPossible(actor, center))
			continue;
		
		m_vecPointDefendArea[actor] = center;
		break;
	}
	
	delete hAreas;
	
	if (IsZeroVector(m_vecPointDefendArea[actor]))
		return action.ChangeTo(CTFBotDefenderAttack(), "NULL defense area");
	
	BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_HELP);
	
	return action.Continue();
}

public Action CTFBotGuardPoint_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	// if (IsZeroVector(m_vecPointDefendArea[actor]))
		// return action.ChangeTo(CTFBotDefenderAttack(), "Defend area is NULL");
	
	switch (TF2_GetPlayerClass(actor))
	{
		case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
		{
			if (CTFBotAttackTank_SelectTarget(actor))
				return action.ChangeTo(CTFBotAttackTank(), "Tank priority");
		}
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
	
	if (threat)
		EquipBestWeaponForThreat(actor, threat);
	
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
	
	//If we're close-range only, chase after them to defend the point
	if (myWeapon != -1 && (TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_FLAMETHROWER || IsMeleeWeapon(myWeapon)))
	{
		int nearest = GetEnemyPlayerNearestToPosition(actor, m_vecPointDefendArea[actor], 1000.0);
		
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
	
	//Stay near the point to defend it
	if (myBot.IsRangeGreaterThanEx(m_vecPointDefendArea[actor], 200.0))
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			m_pPath[actor].ComputeToPos(myBot, m_vecPointDefendArea[actor]);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	return action.Continue();
}

public void CTFBotGuardPoint_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_vecPointDefendArea[actor] = NULL_VECTOR;
}

public Action CTFBotGuardPoint_OnTerritoryContested(BehaviorAction action, int actor, int territory)
{
	if (redbots_manager_debug_actions.BoolValue)
		PrintToChatAll("[OnTerritoryContested] Losing CP %d", GetControlPointByID(territory));
	
	//Someone tried to capture it, keep defending
	return action.TryToSustain();
}

public Action CTFBotGuardPoint_OnTerritoryLost(BehaviorAction action, int actor, int territory)
{
	if (redbots_manager_debug_actions.BoolValue)
		PrintToChatAll("[OnTerritoryLost] Lost CP %d!", GetControlPointByID(territory));
	
	//We lost the point, give up
	return action.TryChangeTo(CTFBotDefenderAttack(), RESULT_CRITICAL, "Point lost");
}

bool CTFBotGuardPoint_IsPossible(int client)
{
	//There are better things for scout to do than this
	if (TF2_GetPlayerClass(client) == TFClass_Scout)
		return false;
	
	//One of us is already watching the point
	if (GetCountOfBotsWithNamedAction("DefenderGuardPoint") > 0)
		return false;
	
	//Nothing to defend
	if (GetDefendablePointTrigger(TF2_GetClientTeam(client)) == -1)
		return false;
	
	//I'd rather lose the point than lose the wave!
	if (IsFailureImminent(client))
		return false;
	
	return true;
}