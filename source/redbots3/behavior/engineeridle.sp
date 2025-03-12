#define SENTRY_WATCH_BOMB_RANGE	400.0

float m_vecNestArea[MAXPLAYERS + 1][3];

BehaviorAction CTFBotEngineerIdle()
{
	BehaviorAction action = ActionsManager.Create("DefenderEngineerIdle");
	
	action.OnStart = CTFBotEngineerIdle_OnStart;
	action.Update = CTFBotEngineerIdle_Update;
	action.OnEnd = CTFBotEngineerIdle_OnEnd;
	action.OnSuspend = CTFBotEngineerIdle_OnSuspend;
	
	return action;
}

public Action CTFBotEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	return action.Continue();
}

public Action CTFBotEngineerIdle_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (CTFBotEvadeBuster_IsPossible(actor))
		return action.SuspendFor(CTFBotEvadeBuster(), "Sentry buster!");
	
	int mySentry = TF2_GetObject(actor, TFObject_Sentry);
	
	if (mySentry == -1)
		return action.SuspendFor(CTFBotBuildSentrygun(), "No sentry");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float sentryPosition[3]; sentryPosition = WorldSpaceCenter(mySentry);
	int flag = FindBombNearestToHatch();
	int melee = GetPlayerWeaponSlot(actor, TFWeaponSlot_Melee);
	bool bWatchForEnemies = true;
	bool bGrabBuilding = false;
	float pathGoalPosition[3];
	
	if (flag != -1)
	{
		float flagPosition[3]; flagPosition = GetAbsOrigin(flag);
		
		if (TF2_IsCarryingObject(actor))
		{
			bWatchForEnemies = false;
			bGrabBuilding = true;
			
			int carrier = BaseEntity_GetOwnerEntity(flag);
			
			if (carrier != -1)
			{
				//The bomb is being carried, move towards the bomb carrier
				GetClientAbsOrigin(carrier, pathGoalPosition);
				
				if (myBot.IsRangeLessThanEx(pathGoalPosition, SENTRY_WATCH_BOMB_RANGE))
					VS_PressFireButton(actor);
			}
			else
			{
				if (IsZeroVector(m_vecNestArea[actor]))
				{
					//Find a spot near the bomb to put the sentry at
					CTFBotEngineerIdle_FindNestAreaAroundVec(actor, flagPosition);
				}
				
				pathGoalPosition = m_vecNestArea[actor];
				
				if (myBot.IsRangeLessThanEx(m_vecNestArea[actor], 75.0))
					VS_PressFireButton(actor);
			}
		}
		else if (GetVectorDistance(flagPosition, sentryPosition) > SENTRY_WATCH_BOMB_RANGE)
		{
			CTFNavArea area = view_as<CTFNavArea>(TheNavMesh.GetNavArea(flagPosition));
			
			//We only care if the bomb is currently out of the spawn room
			if (area && !area.HasAttributeTF(RED_SPAWN_ROOM) && !area.HasAttributeTF(BLUE_SPAWN_ROOM))
			{
				//My sentry isn't watching the bomb, we need to go get it
				//Our current nest area is no longer good either, invalidate!
				pathGoalPosition = sentryPosition;
				m_vecNestArea[actor] = NULL_VECTOR;
				bGrabBuilding = true;
				
				if (myBot.IsRangeLessThanEx(sentryPosition, 100.0))
				{
					bWatchForEnemies = false;
					SnapViewToPosition(actor, sentryPosition);
					VS_PressAltFireButton(actor);
				}
			}
		}
	}
	
	if (!bGrabBuilding)
	{
		bool bRepairSentry = false;
		
		if (BaseEntity_GetHealth(mySentry) < TF2Util_GetEntityMaxHealth(mySentry) || TF2_GetUpgradeLevel(mySentry) < 3)
		{
			//Go repair my sentry
			pathGoalPosition = sentryPosition;
			bRepairSentry = true;
			
			if (myBot.IsRangeLessThanEx(sentryPosition, 100.0))
			{
				if (melee != -1)
					TF2Util_SetPlayerActiveWeapon(actor, melee);
				
				bWatchForEnemies = false;
				SnapViewToPosition(actor, sentryPosition);
				VS_PressFireButton(actor);
			}
		}
		
		if (!bRepairSentry)
		{
			int myDispenser = TF2_GetObject(actor, TFObject_Dispenser);
			
			if (myDispenser == -1)
				return action.SuspendFor(CTFBotBuildDispenser(), "No dispenser");
			
			float dispenserPosition[3]; dispenserPosition = WorldSpaceCenter(myDispenser);
			bool bRepairDispenser = false;
			
			if (BaseEntity_GetHealth(myDispenser) < TF2Util_GetEntityMaxHealth(myDispenser) || TF2_GetUpgradeLevel(myDispenser) < 3)
			{
				//Go repair my dispenser
				pathGoalPosition = dispenserPosition;
				bRepairDispenser = true;
				
				if (myBot.IsRangeLessThanEx(dispenserPosition, 100.0))
				{
					if (melee != -1)
						TF2Util_SetPlayerActiveWeapon(actor, melee);
					
					bWatchForEnemies = false;
					SnapViewToPosition(actor, dispenserPosition);
					VS_PressFireButton(actor);
				}
			}
			
			if (!bRepairDispenser)
			{
				//We're just gonna work on my sentry
				pathGoalPosition = sentryPosition;
				
				if (myBot.IsRangeLessThanEx(sentryPosition, 100.0))
				{
					if (melee != -1)
						TF2Util_SetPlayerActiveWeapon(actor, melee);
					
					bWatchForEnemies = false;
					SnapViewToPosition(actor, sentryPosition);
					VS_PressFireButton(actor);
				}
			}
		}
	}
	
	UpdateLookAroundForEnemies(actor, bWatchForEnemies);
	
	if (bWatchForEnemies)
	{
		int primary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Primary);
		
		if (primary != -1)
			TF2Util_SetPlayerActiveWeapon(actor, primary);
	}
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.5, 1.0);
		m_pPath[actor].ComputeToPos(myBot, pathGoalPosition);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotEngineerIdle_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	
}

public Action CTFBotEngineerIdle_OnSuspend(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	return action.Continue();
}

void CTFBotEngineerIdle_FindNestAreaAroundVec(int client, float vec[3])
{
	AreasCollector hAreas = TheNavMesh.CollectAreasInRadius(vec, SENTRY_WATCH_BOMB_RANGE - 1.0);
	
	for (int i = 0; i < hAreas.Count(); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(hAreas.Get(i));
		
		//Can't build in spawn rooms
		if (area.HasAttributeTF(RED_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		float center[3]; area.GetCenter(center);
		
		//Not too close...
		if (GetVectorDistance(vec, center) < 100.0)
			continue;
		
		m_vecNestArea[client] = center;
		break;
	}
	
	delete hAreas;
}

void CTFBotEngineerIdle_FindNestAreaNearTeamSpawnroom(int client, TFTeam team)
{
	int iAreaCount = TheNavMesh.GetNavAreaCount();
	CTFNavArea foundArea;
	
	for (int i = 0; i < iAreaCount; i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		//Area must be a spawn room exit
		if (!area.HasAttributeTF(SPAWN_ROOM_EXIT))
			continue;
		
		//Area should be in the team's spawn room
		if (team == TFTeam_Blue && !area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		if (team == TFTeam_Red && !area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		//Found a spawn room exit area
		foundArea = area;
		break;
	}
	
	AreasCollector hAreas = TheNavMesh.CollectSurroundingAreas(foundArea, 1500.0, 18.0);
	CTFNavArea buildArea;
	
	for (int i = 0; i < hAreas.Count(); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(hAreas.Get(i));
		
		//Our build area should not actually be on an exit
		if (area.HasAttributeTF(SPAWN_ROOM_EXIT))
			continue;
		
		//We can't build in spawn rooms
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		if (area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		buildArea = area;
		break;
	}
	
	delete hAreas;
	
	buildArea.GetCenter(m_vecNestArea[client]);
}