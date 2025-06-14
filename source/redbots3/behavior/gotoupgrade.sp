int m_iStation[MAXPLAYERS + 1];

BehaviorAction CTFBotGotoUpgrade()
{
	BehaviorAction action = ActionsManager.Create("DefenderGotoUpgrade");
	
	action.OnStart = CTFBotGotoUpgrade_OnStart;
	action.Update = CTFBotGotoUpgrade_Update;
	action.OnEnd = CTFBotGotoUpgrade_OnEnd;
	action.OnNavAreaChanged = CTFBotGotoUpgrade_OnNavAreaChanged;
	
	return action;
}

public Action CTFBotGotoUpgrade_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	m_iStation[actor] = FindClosestUpgradeStation(actor);

	if (m_iStation[actor] <= MaxClients)
	{
		//We couldn't find an upgrade station to path to, so let's just pretend we're at one
		TF2_SetInUpgradeZone(actor, true);
		
		// return action.Done("No upgrade station");
	}
	
	if (GameRules_GetRoundState() == RoundState_RoundRunning)
	{
		float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
		
		//The closest station is so far away, pretend we're in it
		if (GetVectorDistance(myOrigin, WorldSpaceCenter(m_iStation[actor])) >= 1000.0)
			TF2_SetInUpgradeZone(actor, true);
	}
	
	// UpdateLookAroundForEnemies(actor, false);
	
	// EquipWeaponSlot(actor, TFWeaponSlot_Melee);
	
	return action.Continue();
}

public Action CTFBotGotoUpgrade_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotUpgrade(), "Reached upgrade station; buying upgrades");
	
	int station = m_iStation[actor];
	
	// if (!IsValidEntity(station))
		// return action.Done("Upgrade station is invalid");
	
	//Moved from OnStart for technical reasons
	float center[3];
	bool hasGoal = GetMapUpgradeStationGoal(center);
	
	if (!hasGoal)
	{
		CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(station), true, 1000.0, false, false, TEAM_ANY);
		
		if (area == NULL_AREA)
			return action.Continue();
		
		CNavArea_GetRandomPoint(area, center);
		
		center[2] += 50.0;
		
		TR_TraceRayFilter(center, WorldSpaceCenter(station), MASK_PLAYERSOLID, RayType_EndPoint, NextBotTraceFilterIgnoreActors);
		TR_GetEndPosition(center);
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, center);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotGotoUpgrade_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iStation[actor] = -1;
}

public Action CTFBotGotoUpgrade_OnNavAreaChanged(BehaviorAction action, int actor, CTFNavArea newArea, CTFNavArea oldArea, ActionDesiredResult result)
{
	//If we are for some reason not in our spawn room during an active game, just bail out
	if (newArea && GameRules_GetRoundState() == RoundState_RoundRunning)
	{
		TFNavAttributeType spawnRoomFlag = TF2_GetClientTeam(actor) == TFTeam_Red ? RED_SPAWN_ROOM : BLUE_SPAWN_ROOM;
		
		if (!newArea.HasAttributeTF(spawnRoomFlag))
			return action.TryDone(RESULT_IMPORTANT, "I am not in a spawn room");
	}
	
	return action.TryContinue();
}

int FindClosestUpgradeStation(int actor)
{
	int stations[MAXPLAYERS + 1];
	int stationcount;
	
	int i = -1;
	while ((i = FindEntityByClassname(i, "func_upgradestation")) != -1)
	{
		if (!IsUpgradeStationEnabled(i))
			continue;
		
		CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(i), true, 8000.0, false, false, TEAM_ANY);
		
		if (area == NULL_AREA)
			continue;
		
		float center[3]; area.GetCenter(center);
		
		center[2] += 50.0;
		
		TR_TraceRay(center, WorldSpaceCenter(i), MASK_PLAYERSOLID, RayType_EndPoint);
		TR_GetEndPosition(center);
		
		if (!IsPathToVectorPossible(actor, center))
			continue;
		
		stations[stationcount] = i;
		stationcount++;
	}
	
	return stations[GetRandomInt(0, stationcount - 1)];
}

bool GetMapUpgradeStationGoal(float buffer[3])
{
	char map[PLATFORM_MAX_PATH]; GetCurrentMap(map, PLATFORM_MAX_PATH);
	
	if (StrContains(map, "mvm_mannworks") != -1)
	{
		buffer = {-643.9, -2635.2, 384.0};
		return true;
	}
	else if (StrContains(map, "mvm_teien") != -1)
	{
		buffer = {4613.1, -6561.9, 260.0};
		return true;
	}
	else if (StrContains(map, "mvm_sequoia") != -1)
	{
		buffer = {-5117.0, -377.3, 4.5};
		return true;
	}
	else if (StrContains(map, "mvm_highground") != -1)
	{
		buffer = {-2013.0, 4561.0, 448.0};
		return true;
	}
	else if (StrContains(map, "mvm_newnormandy") != -1)
	{
		buffer = {-345.0, 4178.0, 205.0};
		return true;
	}
	else if (StrContains(map, "mvm_snowfall") != -1)
	{
		buffer = {-26.0, 792.0, -159.0};
		return true;
	}
	
	return false;
}