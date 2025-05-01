BehaviorAction CTFBotSpyLurkMvM()
{
	BehaviorAction action = ActionsManager.Create("DefenderSpyLurk");
	
	action.OnStart = CTFBotSpyLurkMvM_OnStart;
	action.Update = CTFBotSpyLurkMvM_Update;
	action.ShouldAttack = CTFBotSpyLurkMvM_ShouldAttack;
	action.IsHindrance = CTFBotSpyLurkMvM_IsHindrance;
	// action.SelectMoreDangerousThreat = CTFBotSpyLurkMvM_SelectMoreDangerousThreat;
	
	return action;
}

static Action CTFBotSpyLurkMvM_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	m_pChasePath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	//Track current target for IsHindrance
	m_iAttackTarget[actor] = -1;
	
	return action.Continue();
}

static Action CTFBotSpyLurkMvM_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (CTFBotSpySapPlayers_SelectTarget(actor))
		return action.SuspendFor(CTFBotSpySapPlayers(), "Sapping player");
	
	if (CTFBotSpySap_SelectTarget(actor))
		return action.SuspendFor(CTFBotSpySap(), "Sapping building");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	int target = GetBestTargetForSpy(actor, 2000.0);
	
	if (target != -1)
	{
		if (TF2_IsStealthed(actor) || TF2_IsFeignDeathReady(actor))
			VS_PressAltFireButton(actor);
		
		int melee = GetPlayerWeaponSlot(actor, TFWeaponSlot_Melee);
		
		if (melee != -1)
			TF2Util_SetPlayerActiveWeapon(actor, melee);
		
		float playerThreatForward[3]; BasePlayer_EyeVectors(target, playerThreatForward);
		float toPlayerThreat[3]; GetClientAbsOrigin(target, toPlayerThreat);
		float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
		
		SubtractVectors(toPlayerThreat, myOrigin, toPlayerThreat);
		
		float threatRange = NormalizeVector(toPlayerThreat, toPlayerThreat);
		const float behindTolerance = 0.0;
		bool isBehindVictim = GetVectorDotProduct(playerThreatForward, toPlayerThreat) > behindTolerance;
		bool isMovingTowardsVictim = true;
		
		if (IsLineOfFireClearEntity(actor, GetEyePosition(actor), target))
		{
			const float circleStrafeRange = 250.0;
			
			if (threatRange < circleStrafeRange)
			{
				// SnapViewToPosition(actor, WorldSpaceCenter(target));
				AimHeadTowards(myBot.GetBodyInterface(), WorldSpaceCenter(target), MANDATORY, 0.1, Address_Null, "Aim stab");
				
				if (!isBehindVictim)
				{
					//Try to circle around the enemy
					float myForward[3]; BasePlayer_EyeVectors(actor, myForward);
					float cross[3]; GetVectorCrossProduct(playerThreatForward, myForward, cross);
					
					if (cross[2] < 0.0)
					{
						g_iAdditionalButtons[actor] = IN_MOVERIGHT;
						g_flForceHoldButtonsTime[actor] = GetGameTime() + 0.1;
					}
					else
					{
						g_iAdditionalButtons[actor] = IN_MOVELEFT;
						g_flForceHoldButtonsTime[actor] = GetGameTime() + 0.1;
					}
					
					//Don't bump into them unless we're going for the stab
					if (threatRange < 100.0 && !HasBackstabPotential(target))
						isMovingTowardsVictim = false;
				}
			}
			
			if (threatRange < GetDesiredAttackRange(actor))
			{
				if (TF2_IsPlayerInCondition(actor, TFCond_Disguised))
				{
					if (redbots_manager_bot_backstab_skill.IntValue == 1)
					{
						//Attack if we know we can land a backstab
						if (GetEntProp(melee, Prop_Send, "m_bReadyToBackstab"))
							VS_PressFireButton(actor);
					}
					else
					{
						//Attack if we think we can land a backstab
						if (isBehindVictim || HasBackstabPotential(target))
							VS_PressFireButton(actor);
					}
				}
				else
				{
					//We're exposed anyways, attack!
					VS_PressFireButton(actor);
				}
			}
		}
		
		if (isMovingTowardsVictim)
			m_pChasePath[actor].Update(myBot, target);
	}
	else
	{
		//Can't find anyone near me, just wander around the bomb
		int flag = FindBombNearestToHatch();
		
		if (flag != -1)
		{
			float bombPosition[3]; bombPosition = GetAbsOrigin(flag);
			
			if (myBot.IsRangeGreaterThanEx(bombPosition, 200.0))
			{
				if (m_flRepathTime[actor] <= GetGameTime())
				{
					m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.0);
					m_pPath[actor].ComputeToPos(myBot, bombPosition);
				}
				
				m_pPath[actor].Update(myBot);
			}
		}
	}
	
	m_iAttackTarget[actor] = target;
	
	return action.Continue();
}

static Action CTFBotSpyLurkMvM_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	/* int me = action.Actor;
	int iThreat = knownEntity.GetEntity();
	
	if (iThreat != m_iAttackTarget[me] && BaseEntity_IsPlayer(iThreat))
	{
		int myWeapon = BaseCombatCharacter_GetActiveWeapon(me);
		
		if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_KNIFE && nextbot.IsRangeLessThan(iThreat, 71.0) && HasBackstabPotential(iThreat))
		{
			//If we can backstab them, we might as well
			result = ANSWER_YES;
			return Plugin_Changed;
		}
	} */
	
	//Don't as we will just make ourselves look stupid
	result = ANSWER_NO;
	return Plugin_Changed;
}

static Action CTFBotSpyLurkMvM_IsHindrance(BehaviorAction action, INextBot nextbot, int entity, QueryResultType& result)
{
	int me = action.Actor;
	
	if (m_iAttackTarget[me] != -1 && nextbot.IsRangeLessThan(m_iAttackTarget[me], 300.0))
	{
		//Don't avoid anyone as we get closer to our target
		result = ANSWER_NO;
		return Plugin_Changed;
	}
	
	result = ANSWER_UNDEFINED;
	return Plugin_Changed;
}

/* static Action CTFBotSpyLurkMvM_SelectMoreDangerousThreat(BehaviorAction action, Address nextbot, int entity, Address threat1, Address threat2, Address& knownEntity)
{
	int iThreat1 = view_as<CKnownEntity>(threat1).GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat1) && TF2_IsMiniBoss(iThreat1))
	{
		//Giants are high priority, and consequently their medics are too
		knownEntity = view_as<Address>(GetHealerOfThreat(view_as<INextBot>(nextbot), view_as<CKnownEntity>(threat1)));
		
		return Plugin_Changed;
	}
	
	int iThreat2 = view_as<CKnownEntity>(threat2).GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat2) && TF2_IsMiniBoss(iThreat2))
	{
		knownEntity = view_as<Address>(GetHealerOfThreat(view_as<INextBot>(nextbot), view_as<CKnownEntity>(threat2)));
		
		return Plugin_Changed;
	}
	
	//Use default targeting, which prioritizes closer threats first
	return Plugin_Continue;
} */