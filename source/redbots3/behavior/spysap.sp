int m_iSapTarget[MAXPLAYERS + 1];

BehaviorAction CTFBotSpySap()
{
	BehaviorAction action = ActionsManager.Create("DefenderSpySap");
	
	action.OnStart = CTFBotSpySap_OnStart;
	action.Update = CTFBotSpySap_Update;
	action.OnEnd = CTFBotSpySap_OnEnd;
	action.OnSuspend = CTFBotSpySap_OnSuspend;
	action.OnResume = CTFBotSpySap_OnResume;
	action.ShouldAttack = CTFBotSpySap_ShouldAttack;
	action.IsHindrance = CTFBotSpySap_IsHindrance;
	
	return action;
}

public Action CTFBotSpySap_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	UpdateLookAroundForEnemies(actor, false);
	
	return action.Continue();
}

public Action CTFBotSpySap_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidEntity(m_iSapTarget[actor]) || !BaseEntity_IsBaseObject(m_iSapTarget[actor]) || TF2_HasSapper(m_iSapTarget[actor]))
		if (!CTFBotSpySap_SelectTarget(actor))
			return action.Done("No sap target");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	const float sapRange = 40.0;
	
	if (myBot.IsRangeLessThan(m_iSapTarget[actor], 2.0 * sapRange))
	{
		int mySapper = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
		
		if (mySapper != -1)
			TF2Util_SetPlayerActiveWeapon(actor, mySapper);
		
		if (TF2_IsStealthed(actor) || TF2_IsFeignDeathReady(actor))
			VS_PressAltFireButton(actor);
		
		SnapViewToPosition(actor, WorldSpaceCenter(m_iSapTarget[actor]));
		VS_PressFireButton(actor);
	}
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		CBaseCombatCharacter(m_iSapTarget[actor]).UpdateLastKnownArea();
		
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToTarget(myBot, m_iSapTarget[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotSpySap_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
}

public Action CTFBotSpySap_OnSuspend(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

public Action CTFBotSpySap_OnResume(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, false);
	
	return action.Continue();
}

public Action CTFBotSpySap_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	result = ANSWER_NO;
	return Plugin_Changed;
}

public Action CTFBotSpySap_IsHindrance(BehaviorAction action, INextBot nextbot, int entity, QueryResultType& result)
{
	int me = action.Actor;
	
	if (m_iSapTarget[me] != -1 && nextbot.IsRangeLessThan(m_iSapTarget[me], 300.0))
	{
		result = ANSWER_NO;
		return Plugin_Changed;
	}
	
	result = ANSWER_UNDEFINED;
	return Plugin_Changed;
}

bool CTFBotSpySap_SelectTarget(int actor)
{
	m_iSapTarget[actor] = GetNearestSappableObject(actor, 2000.0);
	
	return m_iSapTarget[actor] != -1;
}