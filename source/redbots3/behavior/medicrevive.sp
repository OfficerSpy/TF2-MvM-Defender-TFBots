#define MEDIC_REVIVE_RANGE	600.0

BehaviorAction CTFBotMedicRevive()
{
	BehaviorAction action = ActionsManager.Create("DefenderMedicRevive");
	
	action.OnStart = CTFBotMedicRevive_OnStart;
	action.Update = CTFBotMedicRevive_Update;
	// action.OnEnd = CTFBotMedicRevive_OnEnd;
	action.OnInjured = CTFBotMedicRevive_OnInjured;
	
	return action;
}

public Action CTFBotMedicRevive_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	return action.Continue();
}

public Action CTFBotMedicRevive_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	if (secondary == -1)
		return action.Done("No medigun!");
	
	int marker = GetNearestReviveMarker(actor, MEDIC_REVIVE_RANGE);
	
	if (marker == -1)
		return action.Done("No reanimator!");
	
	float markerPos[3]; markerPos = WorldSpaceCenter(marker);
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (myBot.IsRangeLessThanEx(markerPos, WEAPON_MEDIGUN_RANGE))
	{
		int healTarget = GetEntPropEnt(secondary, Prop_Send, "m_hHealingTarget");
		
		if (healTarget != -1 && healTarget != marker)
		{
			//We're healing something that's not the revive marker, stop holding the attack button
		}
		else
		{
			TF2Util_SetPlayerActiveWeapon(actor, secondary);
			SnapViewToPosition(actor, markerPos);
			VS_PressFireButton(actor);
		}
		
		//Do not path if we are healing our target
		if (healTarget == marker)
			return action.Continue();
	}
	else
	{
		//Fend off from enemies
		int primary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Primary);
		
		if (primary != -1)
			TF2Util_SetPlayerActiveWeapon(actor, primary);
	}
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.2);
		m_pPath[actor].ComputeToPos(myBot, markerPos);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

/* public void CTFBotMedicRevive_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	CBaseNPC_GetNextBotOfEntity(actor).GetBodyInterface().ClearPendingAimReply();
} */

public Action CTFBotMedicRevive_OnInjured(BehaviorAction action, int actor, Address takedamageinfo, ActionDesiredResult result)
{
	CTakeDamageInfo info = CTakeDamageInfo(takedamageinfo);
	
	if (info.GetDamage() > 0.0)
	{
		int weapon = BaseCombatCharacter_GetActiveWeapon(actor);
		
		//Someone hit me while I'm trying to revive someone, let's pop uber now if possible
		if (weapon != -1 && TF2Util_GetWeaponID(weapon) == TF_WEAPON_MEDIGUN)
			VS_PressAltFireButton(actor);
	}
	
	return action.Continue();
}

bool CTFBotMedicRevive_IsPossible(int client)
{
	int marker = GetNearestReviveMarker(client, MEDIC_REVIVE_RANGE);
	
	if (marker == -1)
		return false;
	
	if (!IsPathToVectorPossible(client, GetAbsOrigin(marker)))
		return false;
	
	return true;
}