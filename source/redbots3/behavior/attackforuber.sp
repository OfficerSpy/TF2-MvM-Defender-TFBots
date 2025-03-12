#define MEDIC_ATTACK_UBER_LOW_HEALTH	100
#define MEDIC_ATTACK_UBER_SEEK_RANGE	500.0

float m_vecStartArea[MAXPLAYERS + 1][3];

BehaviorAction CTFBotAttackUber()
{
	BehaviorAction action = ActionsManager.Create("DefenderAttackUber");
	
	action.OnStart = CTFBotAttackUber_OnStart;
	action.Update = CTFBotAttackUber_Update;
	action.OnEnd = CTFBotAttackUber_OnEnd;
	
	return action;
}

public Action CTFBotAttackUber_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	GetClientAbsOrigin(actor, m_vecStartArea[actor]);
	
	return action.Continue();
}

public Action CTFBotAttackUber_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (GetClientHealth(actor) < MEDIC_ATTACK_UBER_LOW_HEALTH && !TF2_IsInvulnerable(actor))
		return action.Done("Low health");
	
	int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	if (secondary == -1 || TF2Util_GetWeaponID(secondary) != TF_WEAPON_MEDIGUN)
		return action.Done("No medigun");
	
	float myChargeLevel = GetEntPropFloat(secondary, Prop_Send, "m_flChargeLevel");
	
	if (myChargeLevel >= 1.0)
		return action.Done("Full uber");
	
	int melee = GetPlayerWeaponSlot(actor, TFWeaponSlot_Melee);
	
	if (melee == -1)
		return action.Done("No melee");
	
	TF2Util_SetPlayerActiveWeapon(actor, melee);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	//Let's not stray too far from the patient
	if (myBot.IsRangeGreaterThanEx(m_vecStartArea[actor], MEDIC_ATTACK_UBER_SEEK_RANGE))
		return action.Done("Too far from home");
	
	int target = FindEnemyNearestToMe(actor, MEDIC_ATTACK_UBER_SEEK_RANGE, _, true);
	
	if (target == -1)
		return action.Done("Nobody near me");
	
	if (myBot.IsRangeLessThan(target, TFBOT_MELEE_ATTACK_RANGE))
	{
		SnapViewToPosition(actor, WorldSpaceCenter(target));
		
		if (myChargeLevel < 0.5 && myBot.IsRangeLessThan(target, 100.0) && !IsPlayerMoving(target))
		{
			//Attempt to do a taunt kill on them for the full uber
			if (!TF2_IsTaunting(actor))
				VS_PressAltFireButton(actor);
			else
				return action.Continue();
		}
		else
		{
			VS_PressFireButton(actor);
		}
	}
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.3, 1.0);
		m_pPath[actor].ComputeToTarget(myBot, target);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotAttackUber_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_vecStartArea[actor] = NULL_VECTOR;
}

bool CTFBotAttackUber_IsPossible(int client, int medigun)
{
	bool isUbered = TF2_IsInvulnerable(client);
	
	//Health is too low
	if (!isUbered && GetClientHealth(client) < MEDIC_ATTACK_UBER_LOW_HEALTH)
		return false;
	
	//I should be healing someone first
	if (GetEntPropEnt(medigun, Prop_Send, "m_hHealingTarget") == -1)
		return false;
	
	//It's already full
	if (GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") >= 1.0)
		return false;
	
	//We are already using ubercharge
	if (GetEntProp(medigun, Prop_Send, "m_bChargeRelease") == 1)
		return false;
	
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	
	if (melee == -1)
		return false;
	
	if (!CanWeaponAddUberOnHit(melee))
		return false;
	
	//Too dangerous
	if (!isUbered && GetNearestEnemyCount(client, 1000.0) > 2)
		return false;
	
	if (FindEnemyNearestToMe(client, MEDIC_ATTACK_UBER_SEEK_RANGE, _, true) == -1)
		return false;
	
	return true;
}