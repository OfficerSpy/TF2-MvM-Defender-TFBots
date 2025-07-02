BehaviorAction CTFBotMvMEngineerBuildSentrygun()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildSentrygun");
	
	action.OnStart = CTFBotMvMEngineerBuildSentrygun_OnStart;
	action.Update = CTFBotMvMEngineerBuildSentrygun_Update;
	action.OnEnd = CTFBotMvMEngineerBuildSentrygun_OnEnd;
	
	return action;
}

public Action CTFBotMvMEngineerBuildSentrygun_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	if (GameRules_GetRoundState() == RoundState_BetweenRounds)
	{
		if (m_aNestArea[actor])
		{
			//Teleport ourselves to the nest area for a faster setup
			float vNestPosition[3]; m_aNestArea[actor].GetCenter(vNestPosition);
			vNestPosition[2] += TFBOT_STEP_HEIGHT;
			CBaseEntity(actor).SetAbsOrigin(vNestPosition);
		}
	}
	
	return action.Continue();
}

public Action CTFBotMvMEngineerBuildSentrygun_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_aNestArea[actor] == NULL_AREA) 
	{
		return action.Done("No hint entity");
	}
	
	if (CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(actor))
	{
		//And you.
		
		return action.Done("No sentry");
	}
	
	float areaCenter[3];
	m_aNestArea[actor].GetCenter(areaCenter);
	
	float range_to_hint = GetVectorDistance(GetAbsOrigin(actor), areaCenter);
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
	INextBot myNextbot = CBaseNPC_GetNextBotOfEntity(actor);
	IBody myBody = myNextbot.GetBodyInterface();
	ILocomotion myLoco = myNextbot.GetLocomotionInterface();
	
	if (range_to_hint < 200.0) 
	{
		//Start building a sentry
		if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) != TF_WEAPON_BUILDER)
			FakeClientCommandThrottled(actor, "build 2");
		
		UpdateLookAroundForEnemies(actor, false);
		
		if (!myLoco.IsStuck())
		{
			g_arrExtraButtons[actor].PressButtons(IN_DUCK, 0.1);
		}
		
		AimHeadTowards(myBody, areaCenter, MANDATORY, 0.1, _, "Placing sentry");
	}
	
	if (range_to_hint > 70.0)
	{
		//PrintToServer("%f %f %f", areaCenter[0], areaCenter[1], areaCenter[2]);
	
		g_arrPluginBot[actor].SetPathGoalVector(areaCenter);
		g_arrPluginBot[actor].bPathing = true;
		
		if (range_to_hint > 300.0)
		{
			//Fuck em up.
			EquipWeaponSlot(actor, TFWeaponSlot_Primary);
		}
		
		UpdateLookAroundForEnemies(actor, true);
		
		return action.Continue();
	}
	
	g_arrPluginBot[actor].bPathing = false;
	
	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_BUILDER)
	{
		int objBeingBuilt = GetEntPropEnt(myWeapon, Prop_Send, "m_hObjectBeingBuilt");
		
		if (objBeingBuilt == -1)
			return action.Continue();
		
		bool m_bPlacementOK = IsPlacementOK(objBeingBuilt);
		
		VS_PressFireButton(actor);
		
		if (!m_bPlacementOK && myBody.IsHeadAimingOnTarget() && myBody.GetHeadSteadyDuration() > 0.6)
		{
			//That spot was no good.
			//Time to pick a new spot.
			m_aNestArea[actor] = PickBuildArea(actor);
			
			return action.Continue();
		}
	}
	
	int sentry = GetObjectOfType(actor, TFObject_Sentry);
	
	if (sentry == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	SetPlayerReady(actor, true);
	
	return action.Done("Built a sentry");
}

public void CTFBotMvMEngineerBuildSentrygun_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
}