BehaviorAction CTFBotEvadeBuster()
{
	BehaviorAction action = ActionsManager.Create("DefenderEvadeBuster");
	
	action.OnStart = CTFBotEvadeBuster_OnStart;
	action.Update = CTFBotEvadeBuster_Update;
	
	return action;
}

public Action CTFBotEvadeBuster_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_NO);
	
	return action.Continue();
}

public Action CTFBotEvadeBuster_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidClientIndex(g_iDetonatingPlayer))
		return action.Done("No buster");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
	float pathGoalPosition[3];
	int mySentry = TF2_GetPlayerClass(actor) == TFClass_Engineer ? GetObjectOfType(actor, TFObject_Sentry) : -1;
	
	if (mySentry != -1 && !TF2_IsCarryingObject(actor) && myBot.IsRangeLessThan(mySentry, 500.0))
	{
		//I should go get my sentry
		pathGoalPosition = WorldSpaceCenter(mySentry);
		
		if (myBot.IsRangeLessThanEx(pathGoalPosition, 100.0))
		{
			SnapViewToPosition(actor, pathGoalPosition);
			VS_PressAltFireButton(actor);
		}
	}
	else
	{
		//Find areas to escape the sentry buster
		AreasCollector hAreas = TheNavMesh.CollectAreasInRadius(myOrigin, 1000.0);
		
		for (int i = 0; i < hAreas.Count(); i++)
		{
			CNavArea area = hAreas.Get(i);
			float center[3]; area.GetCenter(center);
			
			//It can't be too close to me
			if (myBot.IsRangeLessThanEx(center, 500.0))
				continue;
			
			pathGoalPosition = center;
			break;
		}
		
		delete hAreas;
	}
	
	if (IsZeroVector(pathGoalPosition))
		return action.Done("No escape route");
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.3, 0.4);
		m_pPath[actor].ComputeToPos(myBot, pathGoalPosition);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

bool CTFBotEvadeBuster_IsPossible(int client)
{
	//Nobody is detonating themselves
	if (!IsValidClientIndex(g_iDetonatingPlayer))
		return false;
	
	float myOrigin[3]; GetClientAbsOrigin(client, myOrigin);
	float theirOrigin[3]; GetClientAbsOrigin(g_iDetonatingPlayer, theirOrigin);
	
	//Not a threat to me
	if (GetVectorDistance(myOrigin, theirOrigin) > tf_bot_suicide_bomb_range.FloatValue)
		return false;
	
	return true;
}