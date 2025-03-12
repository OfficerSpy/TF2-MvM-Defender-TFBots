BehaviorAction CTFBotBuildSentrygun()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildSentrygun");
	
	action.OnStart = CTFBotBuildSentrygun_OnStart;
	action.Update = CTFBotBuildSentrygun_Update;
	action.OnEnd = CTFBotBuildSentrygun_OnEnd;
	
	return action;
}

public Action CTFBotBuildSentrygun_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	return action.Continue();
}

public Action CTFBotBuildSentrygun_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (TF2_GetObject(actor, TFObject_Sentry) != -1)
	{
		//TODO: disposable
		
		return action.Done("Built sentry");
	}
	
	int flag = FindBombNearestToHatch();
	
	if (IsZeroVector(m_vecNestArea[actor]))
	{
		if (flag == -1)
		{
			//No bomb active, try to build near the robot spawn
			return action.Continue();
		}
		
		CTFBotEngineerIdle_FindNestAreaAroundVec(actor, GetAbsOrigin(flag));
		
		return action.Continue();
	}
	
	if (flag != -1)
	{
		float flagPosition[3]; flagPosition = GetAbsOrigin(flag);
		
		if (GetVectorDistance(m_vecNestArea[actor], flagPosition) > SENTRY_WATCH_BOMB_RANGE)
		{
			//Our desired build area is too far from the bomb, invalidate!
			m_vecNestArea[actor] = NULL_VECTOR;
			
			return action.Continue();
		}
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	bool bWatchForEnemies = true;
	
	if (myBot.IsRangeLessThanEx(m_vecNestArea[actor], 75.0))
	{
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 2 0");
		
		bWatchForEnemies = false;
		SnapViewToPosition(actor, m_vecNestArea[actor]);
		VS_PressFireButton(actor);
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
		m_pPath[actor].ComputeToPos(myBot, m_vecNestArea[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotBuildSentrygun_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	
}