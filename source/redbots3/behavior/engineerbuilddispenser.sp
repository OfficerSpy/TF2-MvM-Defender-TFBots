BehaviorAction CTFBotMvMEngineerBuildDispenser()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildDispenser");
	
	action.OnStart = CTFBotMvMEngineerBuildDispenser_OnStart;
	action.Update = CTFBotMvMEngineerBuildDispenser_Update;
	action.OnEnd = CTFBotMvMEngineerBuildDispenser_OnEnd;
	
	return action;
}

public Action CTFBotMvMEngineerBuildDispenser_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

public Action CTFBotMvMEngineerBuildDispenser_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_aNestArea[actor] == NULL_AREA) 
	{
		return action.Done("No hint entity");
	}
	
	if (GetObjectOfType(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
	{
		//Fuck you.
		
		return action.Done("No sentry");
	}
	else
	{
		//sentry is not safe.
		if (m_ctSentrySafe[actor] < GetGameTime())
		{
			return action.Done("Sentry not safe");
		}
	}
	
	if (CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(actor))
	{
		//Fuck you too.
		
		return action.Done("Need to advance nest");
	}
	
	float areaCenter[3];
	CNavArea_GetRandomPoint(m_aNestArea[actor], areaCenter);
	
	float range_to_hint = GetVectorDistance(GetAbsOrigin(actor), areaCenter);
	
	if (range_to_hint < 200.0) 
	{
		//Start building a dispenser
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 0");
		
		//Look in "random" directions in an attempt to find a place to fit a dispenser.
		g_arrExtraButtons[actor].PressButtons(IN_RIGHT, 0.1);
		g_arrExtraButtons[actor].flKeySpeed = 5.0;
		
	//	if(g_flNextLookTime[actor] > GetGameTime())
	//		return false;
		
	//	g_flNextLookTime[actor] = GetGameTime() + GetRandomFloat(0.3, 1.0);
		
		//NOTE: we do not look around for incoming enemies cause all we care about is finding somewhere to place this dispenser
		
		//BotAim(actor).AimHeadTowards(areaCenter, OVERRIDE_ALL, 0.1, "Placing sentry");
	}
	
	if (range_to_hint > 70.0)
	{
		//PrintToServer("%f %f %f", areaCenter[0], areaCenter[1], areaCenter[2]);
		
		g_arrPluginBot[actor].SetPathGoalVector(areaCenter);
		g_arrPluginBot[actor].bPathing = true;
		
		//if(range_to_hint > 300.0)
		//{
			//Fuck em up.
			//EquipWeaponSlot(actor, TFWeaponSlot_Melee);
		//}
		
		return action.Continue();
	}
	
	g_arrPluginBot[actor].bPathing = false;
	
	VS_PressFireButton(actor);
	
	int sentry = GetObjectOfType(actor, TFObject_Dispenser);
	
	if (sentry == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	SetPlayerReady(actor, true);
	
	return action.Done("Built a dispenser");
}

public void CTFBotMvMEngineerBuildDispenser_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
}