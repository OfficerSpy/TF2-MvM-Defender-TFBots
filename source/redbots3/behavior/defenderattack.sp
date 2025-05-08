int m_iAttackTarget[MAXPLAYERS + 1];
float m_flRevalidateTarget[MAXPLAYERS + 1];

BehaviorAction CTFBotDefenderAttack()
{
	BehaviorAction action = ActionsManager.Create("DefenderAttack");
	
	action.OnStart = CTFBotDefenderAttack_OnStart;
	action.Update = CTFBotDefenderAttack_Update;
	
	return action;
}

static Action CTFBotDefenderAttack_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	//NOTE: the attack target is usually chosen before we enter this action with CTFBotDefenderAttack_SelectTarget
	
	m_flRevalidateTarget[actor] = GetGameTime() + 3.0;
	
	// UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

static Action CTFBotDefenderAttack_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (TF2_GetPlayerClass(actor) == TFClass_Sniper && GetTFBotMission(actor) == CTFBot_MISSION_SNIPER)
	{
		if (CanUsePrimayWeapon(actor))
		{
			//We can snipe again
			return action.Done("I have gun");
		}
	}
	
	if (CTFBotCampBomb_IsPossible(actor))
		return action.ChangeTo(CTFBotCampBomb(), "Camp bomb");
	
	if (CTFBotGuardPoint_IsPossible(actor))
		return action.ChangeTo(CTFBotGuardPoint(), "Defending a point");
	
	if (CTFBotDestroyTeleporter_SelectTarget(actor))
		return action.SuspendFor(CTFBotDestroyTeleporter(), "Get teleporter");
	
	if (!IsValidClientIndex(m_iAttackTarget[actor])
	|| !IsPlayerAlive(m_iAttackTarget[actor])
	|| TF2_GetClientTeam(m_iAttackTarget[actor]) != GetEnemyTeamOfPlayer(actor))
	{
		if (!CTFBotDefenderAttack_SelectTarget(actor))
			return action.Done("Target is not valid");
	}
	
	if (m_flRevalidateTarget[actor] <= GetGameTime())
	{
		m_flRevalidateTarget[actor] = GetGameTime() + 2.0;
	
		//Need new target.
		if (!IsTargetEntityReachable(actor, m_iAttackTarget[actor]))
			if (!CTFBotDefenderAttack_SelectTarget(actor))
				return action.Done("Unreachable target");
	}
	
	switch (TF2_GetPlayerClass(actor))
	{
		case TFClass_Scout:
		{
			//Scouts primarily prefer to get money
			if (CTFBotCollectMoney_IsPossible(actor))
				return action.ChangeTo(CTFBotCollectMoney(), "Collectinh money");
		}
		case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
		{
			//These classes prefer priortizing the tank more than anything
			if (CTFBotAttackTank_SelectTarget(actor))
				return action.ChangeTo(CTFBotAttackTank(), "Changing threat to tank");
		}
		case TFClass_Medic:
		{
			//Make sure we have our medigun before we even think about leaving this action
			int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
			
			if (secondary != -1)
			{
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i) && GetClientTeam(i) == GetClientTeam(actor) && IsPlayerAlive(i))
					{
						TFClassType class = TF2_GetPlayerClass(i);
						
						if (class != TFClass_Medic && class != TFClass_Sniper && class != TFClass_Engineer && class != TFClass_Spy)
						{
							//We have someone we'd prefer to heal
							return action.Done("I have patient");
						}
					}
				}
			}
		}
	}
	
	//TODO: Other classes should go for money, but only when there isn't a threat around
	
	CTFBotDefenderAttack_SelectTarget(actor, true);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float targetOrigin[3]; GetClientAbsOrigin(m_iAttackTarget[actor], targetOrigin);
	float myEyePos[3]; GetClientEyePosition(actor, myEyePos);
	
	//Path if out of range or cannot see target
	if (myBot.IsRangeGreaterThanEx(targetOrigin, GetDesiredAttackRange(actor)) || !IsLineOfFireClearPosition(actor, myEyePos, targetOrigin))
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.3, 0.4);
			m_pPath[actor].ComputeToTarget(myBot, m_iAttackTarget[actor]);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	IVision myVision = myBot.GetVisionInterface();
	CKnownEntity threat = myVision.GetPrimaryKnownThreat(false);
	
	if (threat)
	{
		//We have a threat, prepare to fight it
		EquipBestWeaponForThreat(actor, threat);
	}
	
	return action.Continue();
}

bool CTFBotDefenderAttack_SelectTarget(int actor, bool bBombCarrierOnly = false)
{
	//Always go after the bot closest to the bomb, if possible
	int target = FindBotNearestToBombNearestToHatch(actor);
	
	//No bomb in play, just find random target
	if (!bBombCarrierOnly && target == -1)
		target = SelectRandomReachableEnemy(actor);
	
	//Found a valid target, update
	if (target != -1)
	{
		//Go after the healer first
		int healer = GetHealerOfPlayer(target, true);
		
		if (healer != -1)
			target = healer;
		
		m_iAttackTarget[actor] = target;
		return true;
	}
	
	return false;
}

static bool IsTargetEntityReachable(int client, int target)
{
	CTFNavArea area = view_as<CTFNavArea>(CBaseCombatCharacter(target).GetLastKnownArea());
	
	if (area == NULL_AREA)
		return false;
	
	if ((TF2_GetClientTeam(client) == TFTeam_Red && area.HasAttributeTF(BLUE_SPAWN_ROOM))
	|| (TF2_GetClientTeam(client) == TFTeam_Blue && area.HasAttributeTF(RED_SPAWN_ROOM)))
	{
		//Usually cannot enter enemy spawns
		return false;
	}
	
	return true;
}