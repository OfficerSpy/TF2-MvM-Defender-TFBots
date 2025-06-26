int m_iHealthPack[MAXPLAYERS + 1];

BehaviorAction CTFBotGetHealth()
{
	BehaviorAction action = ActionsManager.Create("DefenderGetHealth");
	
	action.OnStart = CTFBotGetHealth_OnStart;
	action.Update = CTFBotGetHealth_Update;
	action.OnEnd = CTFBotGetHealth_OnEnd;
	action.ShouldHurry = CTFBotGetHealth_ShouldHurry;
	action.ShouldAttack = CTFBotGetHealth_ShouldAttack;
	
	return action;
}

public Action CTFBotGetHealth_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	float health_ratio = float(GetClientHealth(actor)) / float(TEMP_GetPlayerMaxHealth(actor));
	float ratio = ClampFloat((health_ratio - tf_bot_health_critical_ratio.FloatValue) / (tf_bot_health_ok_ratio.FloatValue - tf_bot_health_critical_ratio.FloatValue), 0.0, 1.0);
	
	//	if (TF2_IsPlayerInCondition(actor, TFCond_OnFire))
//		ratio = 0.0;
	
	//((100 / 175) - 0.8) / (0.3 - 0.8)
	
	float far_range = tf_bot_health_search_far_range.FloatValue;
	float max_range = ratio * (tf_bot_health_search_near_range.FloatValue - far_range);
	max_range += far_range;
	
	JSONArray ammo = new JSONArray();
	ComputeHealthAndAmmoVectors(actor, ammo, max_range);
	
	if (ammo.Length <= 0)
	{
		delete ammo;
		return action.Done("No health");
	}
	
	float flSmallestDistance = 99999.0;
	
	for (int i = 0; i < ammo.Length; i++)
	{
		JSONObject entity = view_as<JSONObject>(ammo.Get(i));
		
		if (!IsValidHealth(entity.GetInt("entity_index")))
		{
			delete entity;
			continue;
		}
		
		float flDistance = entity.GetFloat("path_length");
		
		if (flDistance <= flSmallestDistance)
		{
			m_iHealthPack[actor] = entity.GetInt("entity_index");
			flSmallestDistance = flDistance;
		}
		
		delete entity;
	}
	
	delete ammo;
	
	if (m_iHealthPack[actor] != -1)
	{
		if (TF2_GetPlayerClass(actor) == TFClass_Engineer)
			UpdateLookAroundForEnemies(actor, true);
		
		BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_MEDIC);
		return action.Continue();
	}
	
	return action.Done("Could not find health");
}

public Action CTFBotGetHealth_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidHealth(m_iHealthPack[actor]))
		return action.Done("Health is not valid");
	
	if (IsHealedByMedic(actor))
		return action.Done("A medic heals me");
	
	if (GetClientHealth(actor) >= TEMP_GetPlayerMaxHealth(actor))
		return action.Done("I am healed");
	
	if (TF2_IsCarryingObject(actor))
	{
		//Drop our building or we cant defend ourselves
		VS_PressFireButton(actor);
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (IsHealedByObject(actor))
	{
		int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
		
		if (myWeapon != -1 && WeaponID_IsSniperRifle(TF2Util_GetWeaponID(myWeapon)) && !TF2_IsPlayerInCondition(actor, TFCond_Zoomed))
		{
			//Aim while healed by dispenser
			VS_PressAltFireButton(actor);
		}
	}
	else
	{
		//Path if not currently healed by dispenser
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.0);
			m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iHealthPack[actor]));
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
	
	if (threat)
		EquipBestWeaponForThreat(actor, threat);
	
	return action.Continue();
}

public void CTFBotGetHealth_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iHealthPack[actor] = -1;
}

public Action CTFBotGetHealth_ShouldHurry(BehaviorAction action, INextBot nextbot, QueryResultType& result)
{
	result = ANSWER_YES;
	return Plugin_Changed;
}

public Action CTFBotGetHealth_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	int me = action.Actor;
	
	if (TF2_GetPlayerClass(me) == TFClass_Spy)
	{
		int iThreat = knownEntity.GetEntity();
		
		if (BaseEntity_IsPlayer(iThreat) && GetClientHealth(iThreat) > 360 && !TF2_IsCritBoosted(me))
		{
			//Don't attack if we can't possibly kill them with our revolver (360 from 6 shots with max damage)
			result = ANSWER_NO;
			return Plugin_Changed;
		}
		else if (GetNearestEnemyCount(me, 1000.0) > 1)
		{
			//There's too many enemies nearby, it'd be better to redisguise so they'll forget about us
			result = ANSWER_NO;
			return Plugin_Changed;
		}
	}
	
	result = ANSWER_UNDEFINED;
	return Plugin_Changed;
}

bool IsValidHealth(int pack)
{
	if (!IsValidEntity(pack))
		return false;

	if (!HasEntProp(pack, Prop_Send, "m_fEffects"))
		return false;

	//It has been taken.
	if (GetEntProp(pack, Prop_Send, "m_fEffects") != 0)
		return false;

	char class[64]; GetEntityClassname(pack, class, sizeof(class));
	
	if (StrContains(class, "item_health", false) == -1 
	&& StrContains(class, "obj_dispenser", false) == -1
	&& StrContains(class, "func_regen", false) == -1)
	{
		return false;
	}
	
	if (StrContains(class, "obj_dispenser", false) != -1 && TF2_HasSapper(pack))
		return false;
	
	return true;
}

bool CTFBotGetHealth_IsPossible(int actor)
{
	if (IsHealedByMedic(actor) || TF2_IsInvulnerable(actor))
		return false;
	
	float health_ratio = float(GetClientHealth(actor)) / float(TEMP_GetPlayerMaxHealth(actor));
	float ratio = ClampFloat((health_ratio - tf_bot_health_critical_ratio.FloatValue) / (tf_bot_health_ok_ratio.FloatValue - tf_bot_health_critical_ratio.FloatValue), 0.0, 1.0);
	
//	if (TF2_IsPlayerInCondition(actor, TFCond_OnFire))
//		ratio = 0.0;
	
	float far_range = tf_bot_health_search_far_range.FloatValue;
	float max_range = ratio * (tf_bot_health_search_near_range.FloatValue - far_range);
	max_range += far_range;
	
	//Skip lag.
	if (m_iHealthPack[actor] != -1 && IsValidHealth(m_iHealthPack[actor]))
	{
		// UpdateLookAroundForEnemies(actor, true);
		return true;
	}

	if (redbots_manager_debug_actions.BoolValue)
		PrintToServer("ratio %f max_range %f", ratio, max_range);
	
	JSONArray ammo = new JSONArray();
	ComputeHealthAndAmmoVectors(actor, ammo, max_range);
	
	if (ammo.Length <= 0)
	{
		delete ammo;
		return false;
	}

	bool bPossible = false;
	
	for (int i = 0; i < ammo.Length; i++)
	{
		JSONObject entity = view_as<JSONObject>(ammo.Get(i));
		
		if (!IsValidHealth(entity.GetInt("entity_index")))
		{
			delete entity;
			continue;
		}
		
		bPossible = true;
		delete entity;
		break;
	}
	
	delete ammo;
	
	// UpdateLookAroundForEnemies(actor, true);
	return bPossible;
}