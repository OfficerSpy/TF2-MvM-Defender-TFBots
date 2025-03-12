BehaviorAction CTFBotBuildDispenser()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildDispenser");
	
	action.OnStart = CTFBotBuildDispenser_OnStart;
	action.Update = CTFBotBuildDispenser_Update;
	action.OnEnd = CTFBotBuildDispenser_OnEnd;
	
	return action;
}

public Action CTFBotBuildDispenser_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	return action.Continue();
}

public Action CTFBotBuildDispenser_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (TF2_GetObject(actor, TFObject_Dispenser) != -1)
		return action.Done("Built dispenser");
	
	if (IsZeroVector(m_vecNestArea[actor]))
	{
		//Our nest area should not be invalid here
		//If it is, then our sentry is probably in a bad spot and needs to be moved
		return action.Done("No nest area");
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	bool bWatchForEnemies = true;
	
	if (myBot.IsRangeLessThanEx(m_vecNestArea[actor], 150.0))
	{
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 0 0");
		
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

public void CTFBotBuildDispenser_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	
}