int m_iTeleporterTarget[MAXPLAYERS + 1];

BehaviorAction CTFBotDestroyTeleporter()
{
	BehaviorAction action = ActionsManager.Create("DefenderKillTeleporter");
	
	action.OnStart = CTFBotDestroyTeleporter_OnStart;
	action.Update = CTFBotDestroyTeleporter_Update;
	action.SelectMoreDangerousThreat = CTFBotDestroyTeleporter_SelectMoreDangerousThreat;
	
	return action;
}

public Action CTFBotDestroyTeleporter_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_JEERS);
	
	return action.Continue();
}

public Action CTFBotDestroyTeleporter_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidEntity(m_iTeleporterTarget[actor]) || !BaseEntity_IsBaseObject(m_iTeleporterTarget[actor]) || TF2_HasSapper(m_iTeleporterTarget[actor]))
		return action.Done("No teleporter");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToTarget(myBot, m_iTeleporterTarget[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public Action CTFBotDestroyTeleporter_SelectMoreDangerousThreat(BehaviorAction action, INextBot nextbot, int entity, CKnownEntity threat1, CKnownEntity threat2, CKnownEntity& knownEntity)
{
	int iThreat1 = threat1.GetEntity();
	int iThreat2 = threat2.GetEntity();
	
	int me = action.Actor;
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(me);
	
	if (myWeapon != -1 && (TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_FLAMETHROWER || IsMeleeWeapon(myWeapon)))
	{
		//We can only get the nearest threat
		knownEntity = SelectCloserThreat(nextbot, threat1, threat2);
		return Plugin_Changed;
	}
	
	//Any sentry nearby becomes a high priority threat because it can stop us from reaching our target
	if (nextbot.IsRangeLessThan(iThreat1, SENTRY_MAX_RANGE) && BaseEntity_IsBaseObject(iThreat1) && TF2_GetObjectType(iThreat1) == TFObject_Sentry)
	{
		knownEntity = threat1;
		return Plugin_Changed;
	}
	
	if (nextbot.IsRangeLessThan(iThreat2, SENTRY_MAX_RANGE) && BaseEntity_IsBaseObject(iThreat2) && TF2_GetObjectType(iThreat2) == TFObject_Sentry)
	{
		knownEntity = threat2;
		return Plugin_Changed;
	}
	
	//Our most dangerous threat should be the teleporter
	if (iThreat1 == m_iTeleporterTarget[me] && IsLineOfFireClearEntity(me, GetEyePosition(me), iThreat1))
	{
		knownEntity = threat1;
		return Plugin_Changed;
	}
	
	if (iThreat2 == m_iTeleporterTarget[me] && IsLineOfFireClearEntity(me, GetEyePosition(me), iThreat2))
	{
		knownEntity = threat2;
		return Plugin_Changed;
	}
	
	//We probably can't see it right now
	knownEntity = NULL_KNOWN_ENTITY;
	
	return Plugin_Changed;
}

bool CTFBotDestroyTeleporter_SelectTarget(int actor)
{
	if (GetCountOfBotsWithNamedAction("DefenderKillTeleporter") > 0)
		return false;
	
	m_iTeleporterTarget[actor] = GetNearestEnemyTeleporter(actor, 5000.0);
	
	return m_iTeleporterTarget[actor] != -1;
}