float m_vecGoalArea[MAXPLAYERS + 1][3];
float m_ctMoveTimeout[MAXPLAYERS + 1];

BehaviorAction CTFBotMoveToFront()
{
	BehaviorAction action = ActionsManager.Create("DefenderMoveToFront");
	
	action.OnStart = CTFBotMoveToFront_OnStart;
	action.Update = CTFBotMoveToFront_Update;
	action.OnEnd = CTFBotMoveToFront_OnEnd;
	
	return action;
}

public Action CTFBotMoveToFront_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	int spawn = -1;
	
	while ((spawn = FindEntityByClassname(spawn, "func_respawnroomvisualizer")) != -1)
	{
		if (GetEntProp(spawn, Prop_Data, "m_iDisabled"))
			continue;
		
		if (BaseEntity_GetTeamNumber(spawn) == BaseEntity_GetTeamNumber(actor))
			continue;
		
		//PrintToServer("[%8.3f] CTFBotMoveToFront_OnStart(#%d): spawn == %i", GetGameTime(), actor, spawn);
		
		break;
	}
	
	if (spawn == -1)
		return action.Done("Cannot find robot spawn");
	
	float flSmallestDistance = 99999.0;
	int iBestEnt = -1;
	
	int holo = -1;
	
	while ((holo = FindEntityByClassname(holo, "prop_dynamic")) != -1)
	{
		char strModel[PLATFORM_MAX_PATH]; GetEntPropString(holo, Prop_Data, "m_ModelName", strModel, PLATFORM_MAX_PATH);
		
		if (!StrEqual(strModel, "models/props_mvm/robot_hologram.mdl"))
			continue;
	
		if (GetEntProp(holo, Prop_Send, "m_fEffects") & 32)
			continue;
		
		//if(BaseEntity_GetTeamNumber(holo) == BaseEntity_GetTeamNumber(actor))
			//continue;
		
		float flDistance = GetVectorDistance(WorldSpaceCenter(spawn), WorldSpaceCenter(holo));
		
		if (flDistance <= flSmallestDistance && IsPathToVectorPossible(actor, WorldSpaceCenter(holo)))
		{
			iBestEnt = holo;
			flSmallestDistance = flDistance;
		}
	}
	
	if (iBestEnt == -1)
	{
		SetPlayerReady(actor, true);
		
		//PrintToServer("[%8.3f] CTFBotMoveToFront_OnStart(#%d): iBestEnt == -1", GetGameTime(), actor);
		return action.Done("Cannot path to target hologram from whereever we are. Pressing F4");
	}
	
	CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(iBestEnt), true, 1000.0, true, true, GetClientTeam(actor));
	
	if (area == NULL_AREA)
	{
		//PrintToServer("[%8.3f] CTFBotMoveToFront_OnStart(#%d): Area == NavArea_Null!", GetGameTime(), actor);
		return action.Done("Nav area is NULL");
	}
	
	CNavArea_GetRandomPoint(area, m_vecGoalArea[actor]);
	
	m_ctMoveTimeout[actor] = GetGameTime() + 50.0;
	
	return action.Continue();
}

public Action CTFBotMoveToFront_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_ctMoveTimeout[actor] < GetGameTime())
	{
		SetPlayerReady(actor, true);
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToServer("[%8.3f] CTFBotMoveToFront(#%d): Timeout elapsed!", GetGameTime(), actor);
		
		return action.Done("Timeout elapsed!");
	}
	
	if (GetVectorDistance(m_vecGoalArea[actor], WorldSpaceCenter(actor)) < 80.0)
	{
		SetPlayerReady(actor, true);
		return action.Done("Goal reached!");
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(3.0, 4.0);
		m_pPath[actor].ComputeToPos(myBot, m_vecGoalArea[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotMoveToFront_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	// EquipWeaponSlot(actor, TFWeaponSlot_Primary);
	
	m_vecGoalArea[actor] = NULL_VECTOR;
}