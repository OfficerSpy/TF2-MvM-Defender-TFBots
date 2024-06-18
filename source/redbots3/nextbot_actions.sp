#define TANK_ATTACK_RANGE_MELEE	1.0
#define TANK_ATTACK_RANGE_SPLASH	400.0
#define TANK_ATTACK_RANGE_DEFAULT	100.0
#define BOMB_HATCH_RANGE_OKAY	5000.0
#define BOMB_HATCH_RANGE_CRITICAL	1000.0
#define BUY_UPGRADES_MAX_TIME	30.0
#define BUY_UPGRADES_FAST_MAX_TIME	3.0
#define MEDIC_REVIVE_RANGE	500.0
#define SENTRY_WATCH_BOMB_RANGE	400.0
#define FLAMETHROWER_REACH_RANGE	350.0
#define FLAMEBALL_REACH_RANGE	526.0
#define BOMB_GUARD_RADIUS	400.0

static char g_strHealthAndAmmoEntities[][] = 
{
	"func_regenerate",
	"item_ammopack*",
	"item_health*",
	"obj_dispenser",
	"tf_ammo_pack"
};

static int MAX_INT = 99999999;
static int MIN_INT = -99999999;

PathFollower m_pPath[MAXPLAYERS + 1];
ChasePath m_pChasePath[MAXPLAYERS + 1];
static float m_flRepathTime[MAXPLAYERS + 1];

static int m_nCurrentPowerupBottle[MAXPLAYERS + 1];
static float m_flNextBottleUseTime[MAXPLAYERS + 1];

static int m_iAttackTarget[MAXPLAYERS + 1];
static float m_flRevalidateTarget[MAXPLAYERS + 1];
static int m_iTarget[MAXPLAYERS + 1];
static float m_flNextMarkTime[MAXPLAYERS + 1];
static int m_iCurrencyPack[MAXPLAYERS + 1];
static int m_iStation[MAXPLAYERS + 1];
static JSONArray CTFPlayerUpgrades[MAXPLAYERS + 1];
static float m_flNextUpgrade[MAXPLAYERS + 1];
static int m_nPurchasedUpgrades[MAXPLAYERS + 1];
static float m_flUpgradingTime[MAXPLAYERS + 1];
static int m_iAmmoPack[MAXPLAYERS + 1];
static float m_vecGoalArea[MAXPLAYERS + 1][3];
static float m_ctMoveTimeout[MAXPLAYERS + 1];
static int m_iHealthPack[MAXPLAYERS + 1];
static float m_vecNestArea[MAXPLAYERS + 1][3];
static int m_iTankTarget[MAXPLAYERS + 1];
static int m_iSapTarget[MAXPLAYERS + 1];
static int m_iTeleporterTarget[MAXPLAYERS + 1];
static int m_iPlayerSapTarget[MAXPLAYERS + 1];
static float m_flSapperCooldown[MAXPLAYERS + 1];

#if defined EXTRA_PLUGINBOT
//Replicate behavior of PathFollower's PluginBot
bool pb_bPath[MAXPLAYERS + 1];
float pb_vecPathGoal[MAXPLAYERS + 1][3];
int pb_iPathGoalEntity[MAXPLAYERS + 1];
#endif

void InitNextBotPathing()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		m_pPath[i] = PathFollower(_, Path_FilterIgnoreActors, Path_FilterOnlyActors);
		m_pChasePath[i] = ChasePath(LEAD_SUBJECT, _, Path_FilterIgnoreActors, Path_FilterOnlyActors);
	}
}

void ResetNextBot(int client)
{
	m_flRepathTime[client] = 0.0;
	
	m_nCurrentPowerupBottle[client] = POWERUP_BOTTLE_NONE;
	m_flNextBottleUseTime[client] = 0.0;
	
	m_iAttackTarget[client] = -1;
	// m_flRevalidateTarget[client] = 0.0;
	m_iTarget[client] = -1;
	m_flNextMarkTime[client] = 0.0;
	m_iCurrencyPack[client] = -1;
	m_iStation[client] = -1;
	m_flNextUpgrade[client] = 0.0;
	m_nPurchasedUpgrades[client] = 0;
	m_flUpgradingTime[client] = 0.0;
	m_iAmmoPack[client] = -1;
	m_vecGoalArea[client] = NULL_VECTOR;
	m_ctMoveTimeout[client] = 0.0;
	m_iHealthPack[client] = -1;
	m_vecNestArea[client] = NULL_VECTOR;
	m_iTankTarget[client] = -1;
	m_iSapTarget[client] = -1;
	m_iTeleporterTarget[client] = -1;
	m_iPlayerSapTarget[client] = -1;
	m_flSapperCooldown[client] = 0.0;
	
#if defined EXTRA_PLUGINBOT
	pb_bPath[client] = false;
	pb_vecPathGoal[client] = NULL_VECTOR;
	pb_iPathGoalEntity[client] = -1;
#endif
}

#if defined EXTRA_PLUGINBOT
void PluginBot_SimulateFrame(int client)
{
	//SimulateFrame > PFContext::RecalculatePath
	//This is used whenever we want to path somewhere constantly
	if (pb_bPath[client])
	{
		bool shouldPathToVec = !IsZeroVector(pb_vecPathGoal[client]);
		bool shouldPathToEntity = pb_iPathGoalEntity[client] > 0;
		
		if (shouldPathToVec || shouldPathToEntity)
		{
			INextBot myBot = CBaseNPC_GetNextBotOfEntity(client);
			
			if (m_flRepathTime[client] <= GetGameTime())
			{
				CBaseCombatCharacter(client).UpdateLastKnownArea();
				
				if (shouldPathToVec)
					m_pPath[client].ComputeToPos(myBot, pb_vecPathGoal[client]);
				else if (shouldPathToEntity)
					m_pPath[client].ComputeToTarget(myBot, pb_iPathGoalEntity[client]);
				
				m_flRepathTime[client] = GetGameTime() + 0.2;
			}
			
			//I don't see a reason to use UpdateLastKnownArea again
			
			m_pPath[client].Update(myBot);
		}
	}
}
#endif

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	//TFBots are players, ignore all other nextbots
	if (actor <= MaxClients)
	{
		if (StrEqual(name, "MainAction"))
		{
			action.SelectMoreDangerousThreat = CTFBotMainAction_SelectMoreDangerousThreat;
			action.SelectTargetPoint = CTFBotMainAction_SelectTargetPoint;
		}
		else if (StrEqual(name, "TacticalMonitor"))
		{
			action.Update = CTFBotTacticalMonitor_Update;
		}
		else if (StrEqual(name, "ScenarioMonitor"))
		{
			action.Update = CTFBotScenarioMonitor_Update;
		}
		else if (StrEqual(name, "Heal"))
		{
			action.UpdatePost = CTFBotMedicHeal_UpdatePost;
		}
		else if (StrEqual(name, "FetchFlag"))
		{
			action.OnStart = CTFBotFetchFlag_OnStart;
		}
		else if (StrEqual(name, "MvMEngineerIdle"))
		{
			action.OnStart = CTFBotMvMEngineerIdle_OnStart;
		}
		else if (StrEqual(name, "SniperLurk"))
		{
			action.SelectMoreDangerousThreat = CTFBotSniperLurk_SelectMoreDangerousThreat;
		}
		else if (StrEqual(name, "SpyLeaveSpawnRoom"))
		{
			action.OnStart = CTFBotSpyLeaveSpawnRoom_OnStart;
		}
	}
}

public Action CTFBotMainAction_SelectMoreDangerousThreat(BehaviorAction action, INextBot nextbot, int entity, CKnownEntity threat1, CKnownEntity threat2, CKnownEntity& knownEntity)
{
	int me = action.Actor;
	
	if (g_bIsDefenderBot[me] == false)
		return Plugin_Continue;
	
	// if (!knownThreat1.IsVisibleRecently() && !knownThreat2.IsVisibleRecently())
		// return Plugin_Continue;
	
	CKnownEntity closeThreat = SelectCloserThreat(nextbot, threat1, threat1);
	
	if (BaseEntity_IsPlayer(closeThreat.GetEntity()))
	{
		//For players, target their healer first if they have one
		knownEntity = GetHealerOfThreat(nextbot, closeThreat);
	}
	else
	{
		//We target the closest threat to us
		knownEntity = closeThreat;
	}
	
	// PrintToChatAll("CTFBotMainAction_SelectMoreDangerousThreat");
	
	return Plugin_Changed;
}

public Action CTFBotMainAction_SelectTargetPoint(BehaviorAction action, INextBot nextbot, int entity, float vec[3])
{
	int me = action.Actor;
	
	if (g_bIsDefenderBot[me] == false)
		return Plugin_Continue;
	
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(me);
	
	if (myWeapon != -1)
	{
		switch (TF2Util_GetWeaponID(myWeapon))
		{
			//TFBots can't compensate their arc if projectile speed differs, so we do our own calculation here
			case TF_WEAPON_GRENADELAUNCHER, TF_WEAPON_PIPEBOMBLAUNCHER:
			{
				float target_point[3];
				
				target_point = WorldSpaceCenter(entity);
				float vecTarget[3], vecActor[3];
				vecTarget = GetAbsOrigin(entity);
				GetClientAbsOrigin(me, vecActor);
				
				float distance = GetVectorDistance(vecTarget, vecActor);
				
				if (distance > 150.0)
				{
					distance = distance / GetProjectileSpeed(myWeapon);
					
					float absVelocity[3]; CBaseEntity(entity).GetAbsVelocity(absVelocity);
					
					target_point[0] = vecTarget[0] + absVelocity[0] * distance;
					target_point[1] = vecTarget[1] + absVelocity[1] * distance;
					target_point[2] = vecTarget[2] + absVelocity[2] * distance;
				}
				else
				{
					target_point = WorldSpaceCenter(entity);
				}
				
				float vecToTarget[3]; SubtractVectors(target_point, vecActor, vecToTarget);
				
				float a5 = NormalizeVector(vecToTarget, vecToTarget);
				
				float ballisticElevation = 0.0125 * a5;
				
				if (ballisticElevation > 45.0)
					ballisticElevation = 45.0;
				
				float elevation = ballisticElevation * (FLOAT_PI / 180.0);
				float sineValue = Sine(elevation);
				float cosineValue = Cosine(elevation);
				
				if (cosineValue != 0.0)
					target_point[2] += (sineValue * a5) / cosineValue;
				
				vec = target_point;
				
				return Plugin_Changed;
			}
			//TFBots won't do projectile prediciton with cow mangler 5000 since it's left out of the code, so we'll do it ourselves
			case TF_WEAPON_PARTICLE_CANNON:
			{
				float target_point[3];
				
				float vecTarget[3], vecActor[3];
				vecTarget = GetAbsOrigin(entity);
				vecActor = GetAbsOrigin(me);
				
				float distance = GetVectorDistance(vecTarget, vecActor);
				
				if (distance > 150.0)
				{
					distance = distance * 0.00090909092;
					
					float absVelocity[3]; CBaseEntity(entity).GetAbsVelocity(absVelocity);
					
					target_point[0] = vecTarget[0] + absVelocity[0] * distance;
					target_point[1] = vecTarget[1] + absVelocity[1] * distance;
					target_point[2] = vecTarget[2] + absVelocity[2] * distance;
					
					if (!TF2_IsLineOfFireClear2(me, target_point))
					{
						vecTarget = WorldSpaceCenter(entity);
						
						target_point[0] = vecTarget[0] + absVelocity[0] * distance;
						target_point[1] = vecTarget[1] + absVelocity[1] * distance;
						target_point[2] = vecTarget[2] + absVelocity[2] * distance;
					}
				}
				else
				{
					target_point = WorldSpaceCenter(entity);
				}
				
				vec = target_point;
				
				return Plugin_Changed;
			}
		}
	}
	
	return Plugin_Continue;
}

public Action CTFBotTacticalMonitor_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	if (GameRules_GetRoundState() == RoundState_RoundRunning)
	{
		bool low_health = false;
		
		float health_ratio = float(GetClientHealth(actor)) / float(TF2Util_GetEntityMaxHealth(actor));
		
		if ((GetTimeSinceWeaponFired(actor) > 2.0 || TF2_GetPlayerClass(actor) == TFClass_Sniper) && health_ratio < tf_bot_health_critical_ratio.FloatValue)
			low_health = true;
		else if (health_ratio < tf_bot_health_ok_ratio.FloatValue)
			low_health = true;
		
		if (low_health && CTFBotGetHealth_IsPossible(actor))
			return action.SuspendFor(CTFBotGetHealth(), "Getting health");
		else
		{
			int primary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Primary);
			
			if (primary != -1 && TF2Util_GetWeaponID(primary) == TF_WEAPON_FLAMETHROWER && (TF2_IsCritBoosted(actor) || TF2_IsPlayerInCondition(actor, TFCond_CritMmmph)))
			{
				//Don't bother going for ammo while using crits unless our weapon has completely run out
				if (!HasAmmo(primary) && CTFBotGetAmmo_IsPossible(actor))
					return action.SuspendFor(CTFBotGetAmmo(), "Get ammo for crit");
			}
			else if (IsAmmoLow(actor) && CTFBotGetAmmo_IsPossible(actor))
			{
				//Go for ammo when we're low and nearby packs are available
				return action.SuspendFor(CTFBotGetAmmo(), "Getting ammo");
			}
		}
	}
	
	return Plugin_Continue;
}

public Action CTFBotScenarioMonitor_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	//Suspend for the action we desire
	//Once it has ended, we will return here and suspend for another one
	return GetDesiredBotAction(actor, action);
}

public Action CTFBotMedicHeal_UpdatePost(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	if (result.type == CHANGE_TO)
	{
		//In mvm mode, medic bots will go for the flag when there's no patient available
		//Let's be smarter about it instead
		
		BehaviorAction resultingAction = result.action;
		char name[ACTION_NAME_LENGTH]; resultingAction.GetName(name);
		
		if (StrEqual(name, "FetchFlag"))
			return action.SuspendFor(CTFBotDefenderAttack(), "Stop the bomb");
	}
	
	if (CTFBotMedicRevive_IsPossible(actor))
		return action.SuspendFor(CTFBotMedicRevive(), "Revive teammate");
	
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
	
	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_MEDIGUN && GetMedigunType(myWeapon) == MEDIGUN_RESIST)
	{
		//TODO: get the value of m_patient instead
		int myPatient = GetEntPropEnt(myWeapon, Prop_Send, "m_hHealingTarget");
		
		if (myPatient > 0)
		{
			int iResistType = GetResistType(actor);
			int iLastDmgType = GetLastDamageType(myPatient);
			
			if (iLastDmgType & DMG_BULLET && iResistType != MEDIGUN_BULLET_RESIST)
				g_iAdditionalButtons[actor] |= IN_RELOAD;
			else if (iLastDmgType & DMG_BLAST && iResistType != MEDIGUN_BLAST_RESIST)
				g_iAdditionalButtons[actor] |= IN_RELOAD;
			else if (iLastDmgType & DMG_BURN && iResistType != MEDIGUN_FIRE_RESIST)
				g_iAdditionalButtons[actor] |= IN_RELOAD;
		}
	}
	
	return Plugin_Continue;
}

public Action CTFBotFetchFlag_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	return action.Done();
}

public Action CTFBotMvMEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	return action.Done();
}

public Action CTFBotSniperLurk_SelectMoreDangerousThreat(BehaviorAction action, INextBot nextbot, int entity, CKnownEntity threat1, CKnownEntity threat2, CKnownEntity& knownEntity)
{
	int me = action.Actor;
	
	if (g_bIsDefenderBot[me] == false)
		return Plugin_Continue;
	
	//Return NULL so the normal threat targetting happens
	knownEntity = NULL_KNOWN_ENTITY;
	
	return Plugin_Changed;
}

public Action CTFBotSpyLeaveSpawnRoom_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	return action.Done();
}

BehaviorAction CTFBotDefenderAttack()
{
	BehaviorAction action = ActionsManager.Create("DefenderAttack");
	
	action.OnStart = CTFBotDefenderAttack_OnStart;
	action.Update = CTFBotDefenderAttack_Update;
	
	return action;
}

public Action CTFBotDefenderAttack_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	//NOTE: the attack target is usually chosen before we enter this action with CTFBotDefenderAttack_SelectTarget
	
	m_flRevalidateTarget[actor] = GetGameTime() + 3.0;
	
	// UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

public Action CTFBotDefenderAttack_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (GetTeleporterKillerCount() < 1 && CTFBotDestroyTeleporter_SelectTarget(actor))
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
		if (/* TF2Util_IsPointInRespawnRoom(WorldSpaceCenter(m_iAttackTarget[actor])) || */ !IsPathToEntityPossible(actor, m_iAttackTarget[actor]))
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
	
	if (CTFBotCampBomb_IsPossible(actor))
		return action.ChangeTo(CTFBotCampBomb(), "Camp bomb");
	
	//TODO: Other classes should go for money, but only when there isn't a threat around
	
	CTFBotDefenderAttack_SelectTarget(actor, true);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float targetOrigin[3]; GetClientAbsOrigin(m_iAttackTarget[actor], targetOrigin);
	float myEyePos[3]; GetClientEyePosition(actor, myEyePos);
	
	//Path if out of range or cannot see target
	if (myBot.IsRangeGreaterThanEx(targetOrigin, GetDesiredAttackRange(actor)) || !TF2_IsLineOfFireClear(actor, myEyePos, targetOrigin))
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.5, 1.0);
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

BehaviorAction CTFBotMarkGiant()
{
	BehaviorAction action = ActionsManager.Create("DefenderMarkGiant");
	
	action.OnStart = CTFBotMarkGiant_OnStart;
	action.Update = CTFBotMarkGiant_Update;
	action.OnEnd = CTFBotMarkGiant_OnEnd;
	
	return action;
}

public Action CTFBotMarkGiant_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	int weapon = GetMarkForDeathWeapon(actor);
	
	if (weapon == INVALID_ENT_REFERENCE)
		return action.Done("Don't have a mark-for-death weapon");
	
	ArrayList potential_victims = new ArrayList();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == actor)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (IsPlayerMarkable(actor, i))
			potential_victims.Push(i);
	}
	
	if (potential_victims.Length == 0)
	{
		delete potential_victims;
		m_iTarget[actor] = -1;
		return action.Done("No eligible mark victims");
	}
	
	m_iTarget[actor] = potential_victims.Get(GetRandomInt(0, potential_victims.Length - 1));
	
	delete potential_victims;
	
	EquipWeaponSlot(actor, TFWeaponSlot_Melee);
	
	return action.Continue();
}

public Action CTFBotMarkGiant_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidClientIndex(m_iTarget[actor]) || !IsPlayerAlive(m_iTarget[actor]))
	{
		m_iTarget[actor] = -1;
		return action.Done("Mark target is no longer valid");
	}
	
	if (!IsPlayerMarkable(actor, m_iTarget[actor]))
	{
		m_iTarget[actor] = -1;
		return action.Done("Mark target is no longer markable");
	}
	
	float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
	float targetOrigin[3]; GetClientAbsOrigin(m_iTarget[actor], targetOrigin);
	
	float dist_to_target = GetVectorDistance(myOrigin, targetOrigin);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (dist_to_target < 512.0)
	{
		//TODO: aim directly on target instead of doing this dumb shit
		IVision myVision = myBot.GetVisionInterface();
		
		if (myVision.GetKnownCount(TFTeam_Blue) > 1 || myVision.GetKnown(m_iTarget[actor]) == NULL_KNOWN_ENTITY)
		{
			myVision.ForgetAllKnownEntities();
			myVision.AddKnownEntity(m_iTarget[actor]);
		}
	}
	
	//TODO: stop pathing once we reached the desired attack range
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToTarget(myBot, m_iTarget[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotMarkGiant_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_flNextMarkTime[actor] = GetGameTime() + 30.0;
	m_iTarget[actor] = -1;
	// UpdateLookAroundForEnemies(actor, true);
}

BehaviorAction CTFBotCollectMoney()
{
	BehaviorAction action = ActionsManager.Create("DefenderCollectMoney");
	
	action.OnStart = CTFBotCollectMoney_OnStart;
	action.Update = CTFBotCollectMoney_Update;
	action.OnEnd = CTFBotCollectMoney_OnEnd;
	
	return action;
}

public Action CTFBotCollectMoney_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	SelectCurrencyPack(actor);
	
	return action.Continue();
}

public Action CTFBotCollectMoney_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	//TODO: if we're not a scout, see if we should attack instead if we have an active threat
	
	if (!IsValidCurrencyPack(m_iCurrencyPack[actor])) 
		return action.Done("No credits to collect");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iCurrencyPack[actor]));
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotCollectMoney_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iCurrencyPack[actor] = -1;
}

BehaviorAction CTFBotGotoUpgrade()
{
	BehaviorAction action = ActionsManager.Create("DefenderGotoUpgrade");
	
	action.OnStart = CTFBotGotoUpgrade_OnStart;
	action.Update = CTFBotGotoUpgrade_Update;
	action.OnEnd = CTFBotGotoUpgrade_OnEnd;
	
	return action;
}

public Action CTFBotGotoUpgrade_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	m_iStation[actor] = FindClosestUpgradeStation(actor);

	if (m_iStation[actor] <= MaxClients)
	{
		//We couldn't find an upgrade station to path to, so let's just pretend we're at one
		TF2_SetInUpgradeZone(actor, true);
		
		// return action.Done("No upgrade station");
	}
	
	if (GameRules_GetRoundState() == RoundState_RoundRunning)
	{
		float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
		
		//The closest station is so far away, pretend we're in it
		if (GetVectorDistance(myOrigin, WorldSpaceCenter(m_iStation[actor])) >= 1000.0)
			TF2_SetInUpgradeZone(actor, true);
	}
	
	// UpdateLookAroundForEnemies(actor, false);
	
	// EquipWeaponSlot(actor, TFWeaponSlot_Melee);
	
	return action.Continue();
}

public Action CTFBotGotoUpgrade_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotUpgrade(), "Reached upgrade station; buying upgrades");
	
	int station = m_iStation[actor];
	
	// if (!IsValidEntity(station))
		// return action.Done("Upgrade station is invalid");
	
	//Moved from OnStart for technical reasons
	float center[3];
	bool hasGoal = GetMapUpgradeStationGoal(center);
	
	if (!hasGoal)
	{
		CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(station), true, 1000.0, false, false, TEAM_ANY);
		
		if (area == NULL_AREA)
			return action.Continue();
		
		CNavArea_GetRandomPoint(area, center);
		
		center[2] += 50.0;
		
		TR_TraceRayFilter(center, WorldSpaceCenter(station), MASK_PLAYERSOLID, RayType_EndPoint, NextBotTraceFilterIgnoreActors);
		TR_GetEndPosition(center);
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, center);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotGotoUpgrade_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iStation[actor] = -1;
}

BehaviorAction CTFBotUpgrade()
{
	BehaviorAction action = ActionsManager.Create("DefenderUpgrade");
	
	action.OnStart = CTFBotUpgrade_OnStart;
	action.Update = CTFBotUpgrade_Update;
	action.OnEnd = CTFBotUpgrade_OnEnd;
	action.OnSuspend = CTFBotUpgrade_OnSuspend;
	action.OnResume = CTFBotUpgrade_OnResume;
	
	return action;
}

public Action CTFBotUpgrade_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	if (!TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotGotoUpgrade(), "Not standing at an upgrade station!");
	
	CollectUpgrades(actor);
	
	KV_MvM_UpgradesBegin(actor);
	
	m_flNextUpgrade[actor] = GetGameTime() + GetUpgradeInterval();
	
	bool isRoundActive = GameRules_GetRoundState() == RoundState_RoundRunning;
	
	//How long should it take us to buy upgrades?
	if (g_bHasUpgraded[actor] == false && isRoundActive)
	{
		//We probably just joined during an active game
		m_flUpgradingTime[actor] = GetGameTime() + 15.0;
	}
	else
	{
		//spend less time upgrading during the round, normal otherwise
		m_flUpgradingTime[actor] = isRoundActive ? GetGameTime() + BUY_UPGRADES_FAST_MAX_TIME : GetGameTime() + BUY_UPGRADES_MAX_TIME;
	}
	
	// UpdateLookAroundForEnemies(actor, false);
	
	//Due to CTFBot::AvoidPlayers, other players can push us
	SetEntityMoveType(actor, MOVETYPE_NONE);
	
	return action.Continue();
}

public Action CTFBotUpgrade_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotGotoUpgrade(), "Not standing at an upgrade station!");
	
	if (m_flUpgradingTime[actor] <= GetGameTime())
	{
		//It shouldn't take us this long to upgrade...
		
		FakeClientCommand(actor, "tournament_player_readystate 1");
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToChatAll("%N upgrade for long with %d credits left!", actor, TF2_GetCurrency(actor));
		
		return GetUpgradePostAction(actor, action);
	}
	
	float flNextTime = m_flNextUpgrade[actor] - GetGameTime();
	
	if (flNextTime <= 0.0)
	{
		m_flNextUpgrade[actor] = GetGameTime() + GetUpgradeInterval();
		
		JSONObject info = CTFBotPurchaseUpgrades_ChooseUpgrade(actor);
		
		if (info != null) 
		{
			CTFBotPurchaseUpgrades_PurchaseUpgrade(actor, info);
			
			if (redbots_manager_debug_actions.BoolValue)
				PrintToChatAll("Currenct left for %N: %d", actor, TF2_GetCurrency(actor));
		}
		else 
		{
			// g_flNextUpdate[actor] = 0.0;
			
			FakeClientCommand(actor, "tournament_player_readystate 1");
			
			delete info;
			
			return GetUpgradePostAction(actor, action);
		}
		
		delete info;
	}
	
	if (TF2_GetPlayerClass(actor) == TFClass_Medic)
	{
		int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
		
		if (secondary != -1 && TF2Util_GetWeaponID(secondary) == TF_WEAPON_MEDIGUN && GetEntPropEnt(secondary, Prop_Send, "m_hHealingTarget") == -1)
		{
			int teammate = GerNearestTeammate(actor, WEAPON_MEDIGUN_RANGE);
			
			if (teammate != -1)
			{
				//Heal a nearby teammate so we build up uber
				TF2Util_SetPlayerActiveWeapon(actor, secondary);
				SnapViewToPosition(actor, WorldSpaceCenter(teammate));
				VS_PressFireButton(actor);
			}
		}
	}
	
	return action.Continue();
}

public void CTFBotUpgrade_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	//Lastly, try to purchase any canteens we can afford
	PurchaseAffordableCanteens(actor);
	
	KV_MvM_UpgradesDone(actor);
	
	TF2_DetonateObjectsOfType(actor, TFObject_Sentry);
	TF2_DetonateObjectsOfType(actor, TFObject_Dispenser);
	
	// UpdateLookAroundForEnemies(actor, true);
	
	if (IsPlayerAlive(actor))
	{
		if (GetEntityMoveType(actor) == MOVETYPE_NONE)
			SetEntityMoveType(actor, MOVETYPE_WALK);
		
		//Remember this bot's upgrades
		Command_BoughtUpgrades(actor, 0);
		
		//First upgrade session upon joining, give everything as if we prepared beforehand
		//Mainly for use with MANAGER_MODE_AUTO_BOTS
		if (GameRules_GetRoundState() == RoundState_RoundRunning && g_bHasUpgraded[actor] == false)
			UpgradeMidRoundPostActivity(actor);
		
		g_bHasUpgraded[actor] = true;
		g_iBuyUpgradesNumber[actor] = 0;
		
		TF2_SetInUpgradeZone(actor, false);
	}
}

public Action CTFBotUpgrade_OnSuspend(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	//NOTE: this action should never be suspended
	if (IsPlayerAlive(actor) && GetEntityMoveType(actor) == MOVETYPE_NONE)
		SetEntityMoveType(actor, MOVETYPE_WALK);
	
	return action.Continue();
}

public Action CTFBotUpgrade_OnResume(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (IsPlayerAlive(actor) && GetEntityMoveType(actor) == MOVETYPE_WALK)
		SetEntityMoveType(actor, MOVETYPE_NONE);
	
	return action.Continue();
}

BehaviorAction CTFBotGetAmmo()
{
	BehaviorAction action = ActionsManager.Create("DefenderGetAmmo");
	
	action.OnStart = CTFBotGetAmmo_OnStart;
	action.Update = CTFBotGetAmmo_Update;
	action.OnEnd = CTFBotGetAmmo_OnEnd;
	action.ShouldHurry = CTFBotGetAmmo_ShouldHurry;
	action.ShouldAttack = CTFBotGetAmmo_ShouldAttack;
	
	return action;
}

public Action CTFBotGetAmmo_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
#if defined EXTRA_PLUGINBOT
	//Disable constant pathing cause we don't need it here
	//Will cause conflcting pathing issues otherwise
	pb_bPath[actor] = false;
#endif
	
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	JSONArray ammo = new JSONArray();
	ComputeHealthAndAmmoVectors(actor, ammo, tf_bot_ammo_search_range.FloatValue);
	
	if (ammo.Length <= 0)
	{
		delete ammo;
		return action.Done("No ammo");
	}
	
	float flSmallestDistance = 99999.0;
	
	for (int i = 0; i < ammo.Length; i++)
	{
		JSONObject entity = view_as<JSONObject>(ammo.Get(i));
		
		if (!IsValidAmmo(entity.GetInt("entity_index")))
		{
			delete entity;
			continue;
		}
		
		float flDistance = entity.GetFloat("path_length")
		
		if (flDistance <= flSmallestDistance)
		{
			m_iAmmoPack[actor] = entity.GetInt("entity_index");
			flSmallestDistance = flDistance;
		}
		
		delete entity;
	}
	
	delete ammo;
	
	if (m_iAmmoPack[actor] != -1)
	{
		if (TF2_GetPlayerClass(actor) == TFClass_Engineer)
			UpdateLookAroundForEnemies(actor, true);
		
		BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_DISPENSERHERE);
		return action.Continue();
	}
	
	// UpdateLookAroundForEnemies(actor, true);
	return action.Done("Could not find ammo");
}

public Action CTFBotGetAmmo_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidAmmo(m_iAmmoPack[actor]))
		return action.Done("ammo is not valid");
	
	if (IsAmmoFull(actor))
		return action.Done("Ammo is full");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iAmmoPack[actor]));
	}
	
	m_pPath[actor].Update(myBot);
	
	CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
	
	if (threat)
		EquipBestWeaponForThreat(actor, threat);
	
	return action.Continue();
}

public void CTFBotGetAmmo_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iAmmoPack[actor] = -1;
}

public Action CTFBotGetAmmo_ShouldHurry(BehaviorAction action, INextBot nextbot, QueryResultType& result)
{
	//Disables dodging and we won't spin the minigun after recently seeing threats
	result = ANSWER_YES;
	return Plugin_Handled;
}

public Action CTFBotGetAmmo_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	int me = action.Actor;
	
	if (TF2_GetPlayerClass(me) == TFClass_Spy && GetNearestEnemyCount(me, 1000.0) > 1)
	{
		//There's too many enemies nearby, let's just redisguise so they'll forget about us
		result = ANSWER_NO;
		return Plugin_Changed;
	}
	
	result = ANSWER_UNDEFINED;
	return Plugin_Changed;
}

BehaviorAction CTFBotMoveToFront()
{
	BehaviorAction action = ActionsManager.Create("DefenderMoveToFront");
	
	action.OnStart = CTFBotMoveToFront_OnStart;
	action.Update = CTFBotMoveToFront_Update;
	action.OnEnd = CTFBotMoveToFront_OnEnd;
	
	return action;
}

public Action CTFBotMoveToFront_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	int spawn = -1;
	while ((spawn = FindEntityByClassname(spawn, "func_respawnroomvisualizer")) != -1)
	{
		if (GetEntProp(spawn, Prop_Data, "m_iDisabled"))
			continue;
		
		if (BaseEntity_GetTeamNumber(spawn) == BaseEntity_GetTeamNumber(actor))
			continue;
		
		//PrintToServer("[%8.3f] CTFBotMoveToFront_OnStart(#%d): spawn == %i", GetGameTime(), actor, spawn);
		
		break;
	}
	
	if (spawn == -1)
		return action.Done("Cannot find robot spawn");
	
	float flSmallestDistance = 99999.0;
	int iBestEnt = -1;
	
	int holo = -1;
	while ((holo = FindEntityByClassname(holo, "prop_dynamic")) != -1)
	{
		char strModel[PLATFORM_MAX_PATH]; GetEntPropString(holo, Prop_Data, "m_ModelName", strModel, PLATFORM_MAX_PATH);
		
		if (!StrEqual(strModel, "models/props_mvm/robot_hologram.mdl"))
			continue;
	
		if (GetEntProp(holo, Prop_Send, "m_fEffects") & 32)
			continue;
		
		//if(BaseEntity_GetTeamNumber(holo) == BaseEntity_GetTeamNumber(actor))
			//continue;
		
		float flDistance = GetVectorDistance(WorldSpaceCenter(spawn), WorldSpaceCenter(holo));
		
		if (flDistance <= flSmallestDistance && IsPathToVectorPossible(actor, WorldSpaceCenter(holo)))
		{
			iBestEnt = holo;
			flSmallestDistance = flDistance;
		}
	}
	
	if (iBestEnt == -1)
	{
		FakeClientCommandThrottled(actor, "tournament_player_readystate 1");
		
		//PrintToServer("[%8.3f] CTFBotMoveToFront_OnStart(#%d): iBestEnt == -1", GetGameTime(), actor);
		return action.Done("Cannot path to target hologram from whereever we are. Pressing F4");
	}
	
	CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(iBestEnt), true, 1000.0, true, true, GetClientTeam(actor));
	
	if (area == NULL_AREA)
	{
		//PrintToServer("[%8.3f] CTFBotMoveToFront_OnStart(#%d): Area == NavArea_Null!", GetGameTime(), actor);
		return action.Done("Nav area is NULL");
	}
	
	CNavArea_GetRandomPoint(area, m_vecGoalArea[actor]);
	
	m_ctMoveTimeout[actor] = GetGameTime() + 50.0;
	
	return action.Continue();
}

public Action CTFBotMoveToFront_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_ctMoveTimeout[actor] < GetGameTime())
	{
		FakeClientCommandThrottled(actor, "tournament_player_readystate 1");
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToServer("[%8.3f] CTFBotMoveToFront(#%d): Timeout elapsed!", GetGameTime(), actor);
		
		return action.Done("Timeout elapsed!");
	}
	
	if (GetVectorDistance(m_vecGoalArea[actor], WorldSpaceCenter(actor)) < 80.0)
	{
		FakeClientCommandThrottled(actor, "tournament_player_readystate 1");
		return action.Done("Goal reached!");
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(3.0, 4.0);
		m_pPath[actor].ComputeToPos(myBot, m_vecGoalArea[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotMoveToFront_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	// EquipWeaponSlot(actor, TFWeaponSlot_Primary);
	
	m_vecGoalArea[actor] = NULL_VECTOR;
}

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
#if defined EXTRA_PLUGINBOT
	pb_bPath[actor] = false;
#endif
	
	float health_ratio = float(GetClientHealth(actor)) / float(TF2Util_GetEntityMaxHealth(actor));
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
	
	if (GetClientHealth(actor) >= TF2Util_GetEntityMaxHealth(actor))
		return action.Done("I am healed");
	
	if (TF2_IsCarryingObject(actor))
	{
		//Drop our building or we cant defend ourselves
		VS_PressFireButton(actor);
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iHealthPack[actor]));
	}
	
	m_pPath[actor].Update(myBot);
	
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
	
	if (TF2_GetPlayerClass(me) == TFClass_Spy && GetNearestEnemyCount(me, 1000.0) > 1)
	{
		result = ANSWER_NO;
		return Plugin_Changed;
	}
	
	result = ANSWER_UNDEFINED;
	return Plugin_Changed;
}

BehaviorAction CTFBotEngineerIdle()
{
	BehaviorAction action = ActionsManager.Create("DefenderEngineerIdle");
	
	action.OnStart = CTFBotEngineerIdle_OnStart;
	action.Update = CTFBotEngineerIdle_Update;
	action.OnEnd = CTFBotEngineerIdle_OnEnd;
	action.OnSuspend = CTFBotEngineerIdle_OnSuspend;
	
	return action;
}

public Action CTFBotEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	return action.Continue();
}

public Action CTFBotEngineerIdle_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (CTFBotEvadeBuster_IsPossible(actor))
		return action.SuspendFor(CTFBotEvadeBuster(), "Sentry buster!");
	
	int mySentry = TF2_GetObject(actor, TFObject_Sentry);
	
	if (mySentry == -1)
		return action.SuspendFor(CTFBotBuildSentrygun(), "No sentry");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float sentryPosition[3]; sentryPosition = WorldSpaceCenter(mySentry);
	int flag = FindBombNearestToHatch();
	int melee = GetPlayerWeaponSlot(actor, TFWeaponSlot_Melee);
	bool bWatchForEnemies = true;
	bool bGrabBuilding = false;
	float pathGoalPosition[3];
	
	if (flag != -1)
	{
		float flagPosition[3]; flagPosition = GetAbsOrigin(flag);
		
		if (TF2_IsCarryingObject(actor))
		{
			bWatchForEnemies = false;
			bGrabBuilding = true;
			
			int carrier = BaseEntity_GetOwnerEntity(flag);
			
			if (carrier != -1)
			{
				//The bomb is being carried, move towards the bomb carrier
				GetClientAbsOrigin(carrier, pathGoalPosition);
				
				if (myBot.IsRangeLessThanEx(pathGoalPosition, SENTRY_WATCH_BOMB_RANGE))
					VS_PressFireButton(actor);
			}
			else
			{
				if (IsZeroVector(m_vecNestArea[actor]))
				{
					//Find a spot near the bomb to put the sentry at
					CTFBotEngineerIdle_FindNestAreaAroundVec(actor, flagPosition);
				}
				
				pathGoalPosition = m_vecNestArea[actor];
				
				if (myBot.IsRangeLessThanEx(m_vecNestArea[actor], 75.0))
					VS_PressFireButton(actor);
			}
		}
		else if (GetVectorDistance(flagPosition, sentryPosition) > SENTRY_WATCH_BOMB_RANGE)
		{
			CTFNavArea area = view_as<CTFNavArea>(TheNavMesh.GetNavArea(flagPosition));
			
			//We only care if the bomb is currently out of the spawn room
			if (area && !area.HasAttributeTF(RED_SPAWN_ROOM) && !area.HasAttributeTF(BLUE_SPAWN_ROOM))
			{
				//My sentry isn't watching the bomb, we need to go get it
				//Our current nest area is no longer good either, invalidate!
				pathGoalPosition = sentryPosition;
				m_vecNestArea[actor] = NULL_VECTOR;
				bGrabBuilding = true;
				
				if (myBot.IsRangeLessThanEx(sentryPosition, 100.0))
				{
					bWatchForEnemies = false;
					SnapViewToPosition(actor, sentryPosition);
					VS_PressAltFireButton(actor);
				}
			}
		}
	}
	
	if (!bGrabBuilding)
	{
		bool bRepairSentry = false;
		
		if (BaseEntity_GetHealth(mySentry) < TF2Util_GetEntityMaxHealth(mySentry) || TF2_GetUpgradeLevel(mySentry) < 3)
		{
			//Go repair my sentry
			pathGoalPosition = sentryPosition;
			bRepairSentry = true;
			
			if (myBot.IsRangeLessThanEx(sentryPosition, 100.0))
			{
				if (melee != -1)
					TF2Util_SetPlayerActiveWeapon(actor, melee);
				
				bWatchForEnemies = false;
				SnapViewToPosition(actor, sentryPosition);
				VS_PressFireButton(actor);
			}
		}
		
		if (!bRepairSentry)
		{
			int myDispenser = TF2_GetObject(actor, TFObject_Dispenser);
			
			if (myDispenser == -1)
				return action.SuspendFor(CTFBotBuildDispenser(), "No dispenser");
			
			float dispenserPosition[3]; dispenserPosition = WorldSpaceCenter(myDispenser);
			bool bRepairDispenser = false;
			
			if (BaseEntity_GetHealth(myDispenser) < TF2Util_GetEntityMaxHealth(myDispenser) || TF2_GetUpgradeLevel(myDispenser) < 3)
			{
				//Go repair my dispenser
				pathGoalPosition = dispenserPosition;
				bRepairDispenser = true;
				
				if (myBot.IsRangeLessThanEx(dispenserPosition, 100.0))
				{
					if (melee != -1)
						TF2Util_SetPlayerActiveWeapon(actor, melee);
					
					bWatchForEnemies = false;
					SnapViewToPosition(actor, dispenserPosition);
					VS_PressFireButton(actor);
				}
			}
			
			if (!bRepairDispenser)
			{
				//We're just gonna work on my sentry
				pathGoalPosition = sentryPosition;
				
				if (myBot.IsRangeLessThanEx(sentryPosition, 100.0))
				{
					if (melee != -1)
						TF2Util_SetPlayerActiveWeapon(actor, melee);
					
					bWatchForEnemies = false;
					SnapViewToPosition(actor, sentryPosition);
					VS_PressFireButton(actor);
				}
			}
		}
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
		m_pPath[actor].ComputeToPos(myBot, pathGoalPosition);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public void CTFBotEngineerIdle_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	
}

public Action CTFBotEngineerIdle_OnSuspend(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	return action.Continue();
}

BehaviorAction CTFBotBuildSentrygun()
{
	BehaviorAction action = ActionsManager.Create("DefenderBuildSentrygun");
	
	action.OnStart = CTFBotBuildSentrygun_OnStart;
	action.Update = CTFBotBuildSentrygun_Update;
	action.OnEnd = CTFBotBuildSentrygun_OnEnd;
	
	return action;
}

public Action CTFBotBuildSentrygun_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	return action.Continue();
}

public Action CTFBotBuildSentrygun_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (TF2_GetObject(actor, TFObject_Sentry) != -1)
	{
		//TODO: disposable
		
		return action.Done("Built sentry");
	}
	
	int flag = FindBombNearestToHatch();
	
	if (IsZeroVector(m_vecNestArea[actor]))
	{
		if (flag == -1)
		{
			//No bomb active, try to build near the robot spawn
			return action.Continue();
		}
		
		CTFBotEngineerIdle_FindNestAreaAroundVec(actor, GetAbsOrigin(flag));
		
		return action.Continue();
	}
	
	if (flag != -1)
	{
		float flagPosition[3]; flagPosition = GetAbsOrigin(flag);
		
		if (GetVectorDistance(m_vecNestArea[actor], flagPosition) > SENTRY_WATCH_BOMB_RANGE)
		{
			//Our desired build area is too far from the bomb, invalidate!
			m_vecNestArea[actor] = NULL_VECTOR;
			
			return action.Continue();
		}
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	bool bWatchForEnemies = true;
	
	if (myBot.IsRangeLessThanEx(m_vecNestArea[actor], 75.0))
	{
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 2 0");
		
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

public void CTFBotBuildSentrygun_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	
}

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

BehaviorAction CTFBotAttackTank()
{
	BehaviorAction action = ActionsManager.Create("DefenderAttackTank");
	
	action.OnStart = CTFBotAttackTank_OnStart;
	action.Update = CTFBotAttackTank_Update;
	action.SelectMoreDangerousThreat = CTFBotAttackTank_SelectMoreDangerousThreat;
	
	return action;
}

public Action CTFBotAttackTank_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	//NOTE: CTFBotAttackTank_SelectTarget chooses a tank threat beforehand
	
	return action.Continue();
}

public Action CTFBotAttackTank_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidEntity(m_iTankTarget[actor]))
		if (!CTFBotAttackTank_SelectTarget(actor))
			return action.Done("No valid target");
	
	switch (TF2_GetPlayerClass(actor))
	{
		case TFClass_Scout:
		{
			//We still prefer money
			if (CTFBotCollectMoney_IsPossible(actor))
				return action.ChangeTo(CTFBotCollectMoney(), "Get credits");
		}
		case TFClass_Heavy, TFClass_Sniper:
		{
			//We're more useful against the robots than the tank
			if (CTFBotDefenderAttack_SelectTarget(actor))
				return action.ChangeTo(CTFBotDefenderAttack(), "Robot priority");
		}
	}
	
	EquipBestTankWeapon(actor);
	
	float myEyePos[3]; GetClientEyePosition(actor, myEyePos);
	float targetOrigin[3]; targetOrigin = WorldSpaceCenter(m_iTankTarget[actor]);
	float dist_to_tank = GetVectorDistance(myEyePos, targetOrigin);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	bool canSeeTarget = TF2_IsLineOfFireClear3(actor, myEyePos, m_iTankTarget[actor]);
	float attackRange = GetIdealTankAttackRange(actor);
	
	if (!canSeeTarget || dist_to_tank > attackRange)
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.5, 1.0);
			m_pPath[actor].ComputeToPos(myBot, GetAbsOrigin(m_iTankTarget[actor]), 0.0, true);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	return action.Continue();
}

public Action CTFBotAttackTank_SelectMoreDangerousThreat(BehaviorAction action, INextBot nextbot, int entity, CKnownEntity threat1, CKnownEntity threat2, CKnownEntity& knownEntity)
{
	int iThreat1 = threat1.GetEntity();
	int iThreat2 = threat2.GetEntity();
	
	int me = action.Actor;
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(me);
	
	if (myWeapon != -1 && (TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_FLAMETHROWER || IsMeleeWeapon(myWeapon)))
	{
		//Close range weapons only target the closest threat
		knownEntity = SelectCloserThreat(nextbot, threat1, threat2);
		return Plugin_Changed;
	}
	
	//Nearby enemies might try to kill us
	const float notSafeRange = 250.0;
	
	if (BaseEntity_IsPlayer(iThreat1))
	{
		if (nextbot.IsRangeLessThan(iThreat1, notSafeRange))
		{
			knownEntity = threat1;
			return Plugin_Changed;
		}
	}
	
	if (BaseEntity_IsPlayer(iThreat2))
	{
		if (nextbot.IsRangeLessThan(iThreat2, notSafeRange))
		{
			knownEntity = threat2;
			return Plugin_Changed;
		}
	}
	
	//Our most dangerous threat should be the tank
	if (iThreat1 == m_iTankTarget[me] && TF2_IsLineOfFireClear4(me, iThreat1))
	{
		knownEntity = threat1;
		return Plugin_Changed;
	}
	
	if (iThreat2 == m_iTankTarget[me] && TF2_IsLineOfFireClear4(me, iThreat2))
	{
		knownEntity = threat2;
		return Plugin_Changed;
	}
	
	//We probably can't see it right now
	knownEntity = NULL_KNOWN_ENTITY;
	
	return Plugin_Changed;
}

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

public Action CTFBotSpyLurkMvM_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	m_pChasePath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	//Track current target for IsHindrance
	m_iAttackTarget[actor] = -1;
	
	return action.Continue();
}

public Action CTFBotSpyLurkMvM_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (CTFBotSpySapPlayers_SelectTarget(actor))
		return action.SuspendFor(CTFBotSpySapPlayers(), "Sapping player");
	
	if (CTFBotSpySap_SelectTarget(actor))
		return action.SuspendFor(CTFBotSpySap(), "Sapping building");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	int target = GetBestTargetForSpy(actor, 2000.0);
	
	if (target != -1)
	{
		if (TF2_IsStealthed(actor))
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
		
		if (TF2_IsLineOfFireClear4(actor, target))
		{
			const float circleStrafeRange = 250.0;
			
			if (threatRange < circleStrafeRange)
			{
				SnapViewToPosition(actor, WorldSpaceCenter(target));
				
				if (!isBehindVictim)
				{
					//Try to circle around the enemy
					float myForward[3]; BasePlayer_EyeVectors(actor, myForward);
					float cross[3]; GetVectorCrossProduct(playerThreatForward, myForward, cross);
					
					if (cross[2] < 0.0)
						g_iAdditionalButtons[actor] |= IN_MOVERIGHT;
					else
						g_iAdditionalButtons[actor] |= IN_MOVELEFT;
				}
			}
			
			if (threatRange < GetDesiredAttackRange(actor))
			{
				if (TF2_IsPlayerInCondition(actor, TFCond_Disguised))
				{
					//They are stabable
					if (isBehindVictim || TF2_IsPlayerInCondition(target, TFCond_MVMBotRadiowave) || (TF2_IsPlayerInCondition(target, TFCond_Sapped) && !TF2_IsMiniBoss(target)))
						VS_PressFireButton(actor);
				}
				else
				{
					VS_PressFireButton(actor);
				}
			}
		}
		
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

public Action CTFBotSpyLurkMvM_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	//Don't as we will just make ourselves look stupid
	result = ANSWER_NO;
	return Plugin_Changed;
}

public Action CTFBotSpyLurkMvM_IsHindrance(BehaviorAction action, INextBot nextbot, int entity, QueryResultType& result)
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

/* public Action CTFBotSpyLurkMvM_SelectMoreDangerousThreat(BehaviorAction action, Address nextbot, int entity, Address threat1, Address threat2, Address& knownEntity)
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
	if (!IsValidEntity(m_iSapTarget[actor]) || TF2_HasSapper(m_iSapTarget[actor]))
		if (!CTFBotSpySap_SelectTarget(actor))
			return action.Done("No sap target");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	const float sapRange = 40.0;
	
	if (myBot.IsRangeLessThan(m_iSapTarget[actor], 2.0 * sapRange))
	{
		int mySapper = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
		
		if (mySapper != -1)
			TF2Util_SetPlayerActiveWeapon(actor, mySapper);
		
		if (TF2_IsStealthed(actor))
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

BehaviorAction CTFBotSpySapPlayers()
{
	BehaviorAction action = ActionsManager.Create("DefenderSpySapPlayer");
	
	action.OnStart = CTFBotSpySapPlayers_OnStart;
	action.Update = CTFBotSpySapPlayers_Update;
	action.ShouldAttack = CTFBotSpySapPlayers_ShouldAttack;
	action.IsHindrance = CTFBotSpySapPlayers_IsHindrance;
	
	return action;
}

public Action CTFBotSpySapPlayers_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	return action.Continue();
}

public Action CTFBotSpySapPlayers_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidClientIndex(m_iPlayerSapTarget[actor])
	|| !IsPlayerAlive(m_iPlayerSapTarget[actor])
	|| TF2_GetClientTeam(m_iPlayerSapTarget[actor]) != GetEnemyTeamOfPlayer(actor)
	|| !IsPlayerSappable(m_iPlayerSapTarget[actor]))
	{
		return action.Done("No player to sap");
	}
	
	int mySapper = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	if (mySapper == -1)
		return action.Done("No sapper");
	
	TF2Util_SetPlayerActiveWeapon(actor, mySapper);
	
	float origin[3]; GetClientAbsOrigin(m_iPlayerSapTarget[actor], origin);
	float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
	
	SubtractVectors(origin, myOrigin, origin);
	
	//If we're close enough, build a sapper on them
	if (GetVectorLength(origin) <= SAPPER_PLAYER_BUILD_ON_RANGE)
	{
		SpawnSapper(actor, m_iPlayerSapTarget[actor], mySapper);
		SetSapperCooldown(actor, SAPPER_RECHARGE_TIME);
		
		return action.Done("Sapped player");
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.3, 0.4);
		m_pPath[actor].ComputeToTarget(myBot, m_iPlayerSapTarget[actor]);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

public Action CTFBotSpySapPlayers_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	result = ANSWER_NO;
	return Plugin_Changed;
}

public Action CTFBotSpySapPlayers_IsHindrance(BehaviorAction action, INextBot nextbot, int entity, QueryResultType& result)
{
	//Avoid no one
	result = ANSWER_NO;
	return Plugin_Changed;
}

BehaviorAction CTFBotMedicRevive()
{
	BehaviorAction action = ActionsManager.Create("DefenderMedicRevive");
	
	action.OnStart = CTFBotMedicRevive_OnStart;
	action.Update = CTFBotMedicRevive_Update;
	// action.OnEnd = CTFBotMedicRevive_OnEnd;
	
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
	
	if (myBot.IsRangeLessThanEx(markerPos, WEAPON_MEDIGUN_RANGE) && TF2_IsLineOfFireClear2(actor, markerPos))
	{
		int healTarget = GetEntPropEnt(secondary, Prop_Send, "m_hHealingTarget");
		
		if (healTarget != -1 && healTarget != marker)
		{
			// g_iSubtractiveButtons[actor] |= IN_ATTACK;
		}
		else
		{
			TF2Util_SetPlayerActiveWeapon(actor, secondary);
			SnapViewToPosition(actor, markerPos);
			VS_PressFireButton(actor);
		}
		
		return action.Continue();
	}
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.9, 1.2);
		m_pPath[actor].ComputeToPos(myBot, markerPos);
	}
	
	m_pPath[actor].Update(myBot);
	
	int primary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Primary);
	
	if (primary != -1)
		TF2Util_SetPlayerActiveWeapon(actor, primary);
	
	return action.Continue();
}

/* public void CTFBotMedicRevive_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	CBaseNPC_GetNextBotOfEntity(actor).GetBodyInterface().ClearPendingAimReply();
} */

BehaviorAction CTFBotEvadeBuster()
{
	BehaviorAction action = ActionsManager.Create("DefenderEvadeBuster");
	
	action.OnStart = CTFBotEvadeBuster_OnStart;
	action.Update = CTFBotEvadeBuster_Update;
	
	return action;
}

public Action CTFBotEvadeBuster_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_NO);
	
	return action.Continue();
}

public Action CTFBotEvadeBuster_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidClientIndex(g_iDetonatingPlayer))
		return action.Done("No buster");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
	float pathGoalPosition[3];
	int mySentry = TF2_GetPlayerClass(actor) == TFClass_Engineer ? TF2_GetObject(actor, TFObject_Sentry) : -1;
	
	if (mySentry != -1 && !TF2_IsCarryingObject(actor) && myBot.IsRangeLessThan(mySentry, 500.0))
	{
		//I should go get my sentry
		pathGoalPosition = WorldSpaceCenter(mySentry);
		
		if (myBot.IsRangeLessThanEx(pathGoalPosition, 100.0))
		{
			SnapViewToPosition(actor, pathGoalPosition);
			VS_PressAltFireButton(actor);
		}
	}
	else
	{
		//Find areas to escape the sentry buster
		AreasCollector hAreas = TheNavMesh.CollectAreasInRadius(myOrigin, 1000.0);
		
		for (int i = 0; i < hAreas.Count(); i++)
		{
			CNavArea area = hAreas.Get(i);
			float center[3]; area.GetCenter(center);
			
			//It can't be too close to me
			if (myBot.IsRangeLessThanEx(center, 500.0))
				continue;
			
			pathGoalPosition = center;
			break;
		}
		
		delete hAreas;
	}
	
	if (IsZeroVector(pathGoalPosition))
		return action.Done("No escape route");
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.3, 0.4);
		m_pPath[actor].ComputeToPos(myBot, pathGoalPosition);
	}
	
	m_pPath[actor].Update(myBot);
	
	return action.Continue();
}

BehaviorAction CTFBotCampBomb()
{
	BehaviorAction action = ActionsManager.Create("DefenderCampBomb");
	
	action.OnStart = CTFBotCampBomb_OnStart;
	action.Update = CTFBotCampBomb_Update;
	
	return action;
}

public Action CTFBotCampBomb_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	BaseMultiplayerPlayer_SpeakConceptIfAllowed(actor, MP_CONCEPT_PLAYER_SENTRYHERE);
	
	return action.Continue();
}

public Action CTFBotCampBomb_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	switch (TF2_GetPlayerClass(actor))
	{
		case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
		{
			//Tank is more important
			if (CTFBotAttackTank_SelectTarget(actor))
				return action.ChangeTo(CTFBotAttackTank(), "Tank inbound");
		}
	}
	
	int flag = FindBombNearestToHatch();
	
	if (flag == -1)
		return action.Done("No bomb");
	
	if (BaseEntity_GetOwnerEntity(flag) != -1)
	{
		//Someone picked up the bomb!
		return action.ChangeTo(CTFBotDefenderAttack(), "Bomb is taken");
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float bombPosition[3]; bombPosition = WorldSpaceCenter(flag);
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(actor);
	
	//Close-range has to get up and personal with them
	if (myWeapon != -1 && (TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_FLAMETHROWER || IsMeleeWeapon(myWeapon)))
	{
		int nearest = GetEnemyPlayerNearestToPosition(actor, bombPosition, BOMB_GUARD_RADIUS);
		
		if (nearest != -1)
		{
			if (m_flRepathTime[actor] <= GetGameTime())
			{
				m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.5, 1.0);
				m_pPath[actor].ComputeToTarget(myBot, nearest);
			}
			
			m_pPath[actor].Update(myBot);
			
			return action.Continue();
		}
	}
	
	//Move towards the bomb's current area if we're too far or can't see it
	if (myBot.IsRangeGreaterThanEx(bombPosition, BOMB_GUARD_RADIUS) || !TF2_IsLineOfFireClear2(actor, bombPosition))
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			m_pPath[actor].ComputeToPos(myBot, bombPosition);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	return action.Continue();
}

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
	if (!IsValidEntity(m_iTeleporterTarget[actor]) || TF2_HasSapper(m_iTeleporterTarget[actor]))
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
	if (iThreat1 == m_iTeleporterTarget[me] && TF2_IsLineOfFireClear4(me, iThreat1))
	{
		knownEntity = threat1;
		return Plugin_Changed;
	}
	
	if (iThreat2 == m_iTeleporterTarget[me] && TF2_IsLineOfFireClear4(me, iThreat2))
	{
		knownEntity = threat2;
		return Plugin_Changed;
	}
	
	//We probably can't see it right now
	knownEntity = NULL_KNOWN_ENTITY;
	
	return Plugin_Changed;
}

Action GetDesiredBotAction(int client, BehaviorAction action)
{
	RoundState state = GameRules_GetRoundState();
	
	if (state == RoundState_BetweenRounds)
	{
		if (CTFBotCollectMoney_IsPossible(client))
		{
			//Collect any leftover money that my team didn't collect
			return action.SuspendFor(CTFBotCollectMoney(), "Is possible");
		}
		else if (!TF2_IsInUpgradeZone(client) && !IsPlayerReady(client) && ActionsManager.GetAction(client, "DefenderMoveToFront") == INVALID_ACTION)
		{
			if (redbots_manager_bot_use_upgrades.BoolValue)
			{
				return action.SuspendFor(CTFBotGotoUpgrade(), "!IsInUpgradeZone && RoundState_BetweenRounds");
			}
			else
			{
				FakeClientCommand(client, "tournament_player_readystate 1");
				return action.SuspendFor(CTFBotMoveToFront(), "Skip upgrading");
			}
		}
	}
	else if (state == RoundState_RoundRunning)
	{
		if (redbots_manager_bot_use_upgrades.BoolValue && (g_bHasUpgraded[client] == false || ShouldUpgradeMidRound(client)) && !TF2_IsInUpgradeZone(client))
		{
			//We probably just joined in the middle of an active game, or we want to buy upgrades again right now
			g_iBuyUpgradesNumber[client] = 0;
			
			return action.SuspendFor(CTFBotGotoUpgrade(), "Buy upgrades now");
		}
		
		//NOTE: Health and ammo is moved to CTFBotTacticalMonitor_Update as it takes precedence over ScenarioMonitor
		
		switch (TF2_GetPlayerClass(client))
		{
			case TFClass_Medic:
			{
				//Medics automatically start healing
				return Plugin_Continue;
			}
			case TFClass_Scout:
			{
				if (CTFBotCollectMoney_IsPossible(client))
					return action.SuspendFor(CTFBotCollectMoney(), "Collecting money");
				else if (CTFBotMarkGiant_IsPossible(client))
					return action.SuspendFor(CTFBotMarkGiant(), "Marking giant");
				else if (CTFBotAttackTank_SelectTarget(client))
					return action.SuspendFor(CTFBotAttackTank(), "Scout: Attacking tank");
				else if (CTFBotDefenderAttack_SelectTarget(client))
					return action.SuspendFor(CTFBotDefenderAttack(), "Scout: Attacking robots");
			}
			case TFClass_Sniper:
			{
				if (HasSniperRifle(client))
				{
					//NOTE: we set the sniping behavior manually in Timer_PlayerSpawn
					return Plugin_Continue;
				}
				else
				{
					return action.SuspendFor(CTFBotDefenderAttack(), "Sniper Attacking robots");
				}
			}
			case TFClass_Engineer:
			{
				return action.SuspendFor(CTFBotEngineerIdle(), "Engineer Start building");
			}
			case TFClass_Spy:
			{
				return action.SuspendFor(CTFBotSpyLurkMvM(), "Spy do be lurking");
			}
			case TFClass_Heavy:
			{
				if (CTFBotDefenderAttack_SelectTarget(client))
					return action.SuspendFor(CTFBotDefenderAttack(), "CTFBotAttack_IsPossible");
				else if (CTFBotAttackTank_SelectTarget(client))
					return action.SuspendFor(CTFBotAttackTank(), "Attacking tank");
				else if (CTFBotCollectMoney_IsPossible(client))
					return action.SuspendFor(CTFBotCollectMoney(), "CTFBotCollectMoney_IsPossible");
			}
			case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
			{
				if (CTFBotAttackTank_SelectTarget(client))
					return action.SuspendFor(CTFBotAttackTank(), "Attacking tank");
				else if (CTFBotDefenderAttack_SelectTarget(client))
					return action.SuspendFor(CTFBotDefenderAttack(), "CTFBotAttack_IsPossible");
				else if (CTFBotCollectMoney_IsPossible(client))
					return action.SuspendFor(CTFBotCollectMoney(), "CTFBotCollectMoney_IsPossible");
			}
		}
	}
	
	return Plugin_Continue;
}

Action GetUpgradePostAction(int client, BehaviorAction action)
{
	if (GameRules_GetRoundState() == RoundState_BetweenRounds)
	{
		if (TF2_GetPlayerClass(client) == TFClass_Engineer)
			return action.ChangeTo(CTFBotEngineerIdle(), "Start building");
		else if (TF2_GetPlayerClass(client) == TFClass_Medic)
			return action.Done("Start heal mission");
		else if (TF2_GetPlayerClass(client) == TFClass_Spy)
			return action.ChangeTo(CTFBotSpyLurkMvM(), "Start spy lurking");
		else if (HasSniperRifle(client))
			return action.Done("Start lurking");
		else
			return action.ChangeTo(CTFBotMoveToFront(), "Finished upgrading; Move to front and press F4");
	}
	
	//The round's probably already running
	//CTFBotScenarioMonitor_Update will assign the appropriate task
	return action.Done("I finished upgrading");
}

public bool NextBotTraceFilterIgnoreActors(int entity, int contentsMask, any iExclude)
{
	char class[64]; GetEntityClassname(entity, class, sizeof(class));
	
	if (StrEqual(class, "entity_medigun_shield"))
		return false;
	else if (StrEqual(class, "func_respawnroomvisualizer"))
		return false;
	else if (StrContains(class, "tf_projectile_", false) != -1)
		return false;
	else if (StrContains(class, "obj_", false) != -1)
		return false;
	else if (StrEqual(class, "entity_revive_marker"))
		return false;
	else if (StrEqual(class, "tank_boss"))
		return false;
	else if (StrEqual(class, "func_forcefield"))
		return false;
	
	return !CBaseEntity(entity).IsCombatCharacter();
}

float GetDesiredPathLookAheadRange(int client)
{
	return tf_bot_path_lookahead_range.FloatValue * BaseAnimating_GetModelScale(client);
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
		m_iAttackTarget[actor] = target;
		return true;
	}
	
	return false;
}

int GetMarkForDeathWeapon(int player)
{
	for (int i = 0; i < 8; i++) 
	{
		int weapon = GetPlayerWeaponSlot(player, i);
		
		if (!IsValidEntity(weapon)) 
			continue;
		
		int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")
		
		if (m_iItemDefinitionIndex == 355) //Fan O'War
			return weapon;
	}
	
	return INVALID_ENT_REFERENCE;
}

bool IsPlayerMarkable(int bot, int victim)
{
	if (m_flNextMarkTime[bot] < GetGameTime())
		return false;

	/* must be ingame */
	if (!IsClientInGame(victim))
		return false;

	/* must be alive */
	if (!IsPlayerAlive(victim)) 
		return false;
	
	/* must be an enemy */
	if (BaseEntity_GetTeamNumber(bot) == BaseEntity_GetTeamNumber(victim)) 
		return false;
	
	/* must be a giant */
	if (!TF2_IsMiniBoss(victim)) 
		return false;
	
	/* must not be a sentry buster */
	if (IsSentryBusterRobot(victim))
		return false;
	
	/* must not already be marked for death */
	if (TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeath)) 
		return false;
	
	/* must not be invulnerable */
	if (TF2_IsInvulnerable(victim))
		return false;
	
	return true;
}

bool CTFBotMarkGiant_IsPossible(int actor)
{
	if (GetMarkForDeathWeapon(actor) == INVALID_ENT_REFERENCE) 
		return false;
	
	bool victim_exists = false;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == actor)
			continue;

		if(!IsClientConnected(i))
			continue;
		
		if (IsPlayerMarkable(actor, i)) 
			victim_exists = true;
	}
	
	return victim_exists;
}

float GetTimeUntilRemoved(int powerup)
{
	return (GetNextThink(powerup, "PowerupRemoveThink") - GetGameTime());
}

int SelectCurrencyPack(int actor)
{
	int iBestPack = INVALID_ENT_REFERENCE;
	float flLowestTime = 30.0;
	
	int x = INVALID_ENT_REFERENCE; 
	while ((x = FindEntityByClassname(x, "item_currency*")) != -1)
	{
		bool bDistributed = !!GetEntProp(x, Prop_Send, "m_bDistributed");
		
		if (bDistributed)
			continue;
		
		if (!(GetEntityFlags(x) & FL_ONGROUND))
			continue;
		
		float flTimeUntilRemoved = GetTimeUntilRemoved(x);
		
		if (flLowestTime > flTimeUntilRemoved)
		{
			flLowestTime = flTimeUntilRemoved;
			iBestPack = x;
		}
	}

	m_iCurrencyPack[actor] = iBestPack;
	return iBestPack;
}

bool IsValidCurrencyPack(int pack)
{
	if (!IsValidEntity(pack))
		return false;

	char class[64]; GetEntityClassname(pack, class, sizeof(class));
	
	if (StrContains(class, "item_currency", false) == -1)
		return false;
	
	return true;
}

bool CTFBotCollectMoney_IsPossible(int actor)
{	
	if (!IsValidCurrencyPack(SelectCurrencyPack(actor)))
		return false;
	
	return true;
}

int FindClosestUpgradeStation(int actor)
{
	int stations[MAXPLAYERS + 1];
	int stationcount;
	
	int i = -1;
	while ((i = FindEntityByClassname(i, "func_upgradestation")) != -1)
	{
		if (GetEntProp(i, Prop_Data, "m_bDisabled") == 1)
			continue;
		
		CNavArea area = TheNavMesh.GetNearestNavArea(WorldSpaceCenter(i), true, 8000.0, false, false, TEAM_ANY);
		
		if (area == NULL_AREA)
			continue;
		
		float center[3]; area.GetCenter(center);
		
		center[2] += 50.0;
		
		TR_TraceRay(center, WorldSpaceCenter(i), MASK_PLAYERSOLID, RayType_EndPoint);
		TR_GetEndPosition(center);
		
		if (!IsPathToVectorPossible(actor, center))
			continue;
		
		stations[stationcount] = i;
		stationcount++;
	}
	
	return stations[GetRandomInt(0, stationcount - 1)];
}

bool GetMapUpgradeStationGoal(float buffer[3])
{
	char map[PLATFORM_MAX_PATH]; GetCurrentMap(map, PLATFORM_MAX_PATH);
	
	if (StrContains(map, "mvm_mannworks") != -1)
	{
		buffer = {-643.9, -2635.2, 384.0};
		return true;
	}
	else if (StrContains(map, "mvm_teien") != -1)
	{
		buffer = {4613.1, -6561.9, 260.0};
		return true;
	}
	else if (StrContains(map, "mvm_sequoia") != -1)
	{
		buffer = {-5117.0, -377.3, 4.5};
		return true;
	}
	else if (StrContains(map, "mvm_highground") != -1)
	{
		buffer = {-2013.0, 4561.0, 448.0};
		return true;
	}
	else if (StrContains(map, "mvm_newnormandy") != -1)
	{
		buffer = {-345.0, 4178.0, 205.0};
		return true;
	}
	else if (StrContains(map, "mvm_snowfall") != -1)
	{
		buffer = {-26.0, 792.0, -159.0};
		return true;
	}
	
	return false;
}

//CNavArea::GetRandomPoint
void CNavArea_GetRandomPoint(CNavArea area, float buffer[3])
{
	float eLo[3], eHi[3];
	area.GetExtent(eLo, eHi);
	
	float spot[3];
	spot[0] = GetRandomFloat(eLo[0], eHi[0]);
	spot[1] = GetRandomFloat(eLo[1], eHi[1]);
	spot[2] = area.GetZ(spot[0], spot[1]);
	
	buffer = spot;
}

void CollectUpgrades(int client)
{
	if (CTFPlayerUpgrades[client] != null)
		delete CTFPlayerUpgrades[client];
		
	CTFPlayerUpgrades[client] = new JSONArray();
	
	ArrayList iArraySlots = new ArrayList();
	
	iArraySlots.Push(-1); //Always buy player upgrades
	
	bool bDemoKnight = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary) == -1;
	bool bEngineer = TF2_GetPlayerClass(client) == TFClass_Engineer;
	
	if (bEngineer)
	{
		iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		iArraySlots.Push(TF_LOADOUT_SLOT_BUILDING);
		iArraySlots.Push(TF_LOADOUT_SLOT_PDA);
	}
	else
	{
		if (TF2_GetPlayerClass(client) == TFClass_Sniper)
		{
			iArraySlots.Push(TF_LOADOUT_SLOT_PRIMARY);
			iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		}
		else if (TF2_GetPlayerClass(client) == TFClass_Medic)
		{
			//Buy upgrades for our medigun
			iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
		}
		else if (TF2_GetPlayerClass(client) == TFClass_Spy)
		{
			//Buy upgrades for our sapper and knife
			iArraySlots.Push(TF_LOADOUT_SLOT_BUILDING);
			iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		}

		//Demoknight doesn't buy primary weapon upgrades.
		iArraySlots.Push(bDemoKnight ? TF_LOADOUT_SLOT_MELEE : TF_LOADOUT_SLOT_PRIMARY);
		
		if (TF2_IsShieldEquipped(client))
		{
			iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
		}
		else
		{
			int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
			int weaponID = secondary != -1 ? TF2Util_GetWeaponID(secondary) : -1;
			
			switch (weaponID)
			{
				case TF_WEAPON_JAR, TF_WEAPON_JAR_MILK, TF_WEAPON_BUFF_ITEM, TF_WEAPON_JAR_GAS:
				{
					//Secondary items that have some use
					iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
				}
				case TF_WEAPON_PIPEBOMBLAUNCHER:
				{
					//If we don't have an actual primary, then we rely on our secondary
					if (bDemoKnight)
						iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
				}
			}
		}
	}

	for (int i = 0; i < iArraySlots.Length; i++)
	{
		int slot = iArraySlots.Get(i);
	
		for (int index = 0; index < MAX_UPGRADES; index++)
		{
			CMannVsMachineUpgrades upgrades = CMannVsMachineUpgradeManager().GetUpgradeByIndex(index);
			
			if (upgrades.m_iUIGroup() == UIGROUP_UPGRADE_ATTACHED_TO_PLAYER && slot != -1) 
				continue;
			
			CEconItemAttributeDefinition attr = CEIAD_GetAttributeDefinitionByName(upgrades.m_szAttribute());
			if (attr.Address == Address_Null)
				continue;
			
			if (!CanUpgradeWithAttrib(client, slot, attr.GetIndex(), upgrades.Address))
				continue;
			
			JSONObject UpgradeInfo = new JSONObject();
			UpgradeInfo.SetInt("pclass", view_as<int>(TF2_GetPlayerClass(client)));
			UpgradeInfo.SetInt("slot", slot);
			UpgradeInfo.SetInt("index", index);
			UpgradeInfo.SetInt("random", GetRandomInt(MIN_INT, MAX_INT));
			UpgradeInfo.SetInt("priority", GetUpgradePriority(UpgradeInfo));
			
			CTFPlayerUpgrades[client].Push(UpgradeInfo);
			
			delete UpgradeInfo;
		}
	}
	
	delete iArraySlots;
	
	/*PrintToServer("Unsorted upgrades for #%d \"%N\": %i total\n", client, client, CTFPlayerUpgrades[client].Length);
	PrintToServer("%3s %4s %-5s %-8s\n", "#", "SLOT", "INDEX", "PRIORITY");
	
	for (int i = 0; i < CTFPlayerUpgrades[client].Length; i++) 
	{
		JSONObject UpgradeInfo = view_as<JSONObject>(CTFPlayerUpgrades[client].Get(i));
		
		PrintToServer("%3d %4d %-5d %-8d", i, UpgradeInfo.GetInt("slot"), UpgradeInfo.GetInt("index"), UpgradeInfo.GetInt("priority"));
		
		delete UpgradeInfo;
	}*/
	
	
	//NEW!
	JSONArray new_json = new JSONArray();
	/////
	
	while (CTFPlayerUpgrades[client].Length > 0)
	{	
		JSONObject mObj = view_as<JSONObject>(CTFPlayerUpgrades[client].Get(0));
		int minimum = mObj.GetInt("priority"); // arbitrary number in list
		
		//NEW!
		JSONObject tempObj = new JSONObject();
		tempObj.SetInt("pclass",   mObj.GetInt("pclass"));
		tempObj.SetInt("slot",     mObj.GetInt("slot"));
		tempObj.SetInt("index",    mObj.GetInt("index"));
		tempObj.SetInt("random",   mObj.GetInt("random"));
		tempObj.SetInt("priority", mObj.GetInt("priority"));
		/////
		
		delete mObj;
		
		for (int x = 0; x < CTFPlayerUpgrades[client].Length; x++)
		{
			JSONObject xObj = view_as<JSONObject>(CTFPlayerUpgrades[client].Get(x)); // arbitrary number in list
			
			if (xObj.GetInt("priority") > minimum)
			{
				minimum = xObj.GetInt("priority");
				
				//NEW!
				tempObj.SetInt("pclass",   xObj.GetInt("pclass"));
				tempObj.SetInt("slot",     xObj.GetInt("slot"));
				tempObj.SetInt("index",    xObj.GetInt("index"));
				tempObj.SetInt("random",   xObj.GetInt("random"));
				tempObj.SetInt("priority", xObj.GetInt("priority"));
				/////
			}

			delete xObj;
		}
		
		//NEW!
		new_json.Push(tempObj);
		delete tempObj;
		/////
		
		int index = FindPriorityIndex(CTFPlayerUpgrades[client], "priority", minimum);
		CTFPlayerUpgrades[client].Remove(index);
	}
    
	if (redbots_manager_debug_actions.BoolValue)
	{
		PrintToServer("\nPreferred upgrades for #%d \"%N\"\n", client, client);
		PrintToServer("%3s %4s %4s %5s %-64s\n", "#", "SLOT", "COST", "INDEX", "ATTRIBUTE");
	}
	
	for (int i = 0; i < new_json.Length; i++) 
	{
		JSONObject info = view_as<JSONObject>(new_json.Get(i));
		CTFPlayerUpgrades[client].Push(info);
		
		if (redbots_manager_debug_actions.BoolValue)
		{
			CMannVsMachineUpgradeManager manager = CMannVsMachineUpgradeManager();
			int cost = GetCostForUpgrade(manager.GetUpgradeByIndex(info.GetInt("index")).Address, info.GetInt("slot"), info.GetInt("pclass"), client);
			PrintToServer("%3d %4d %4d %5d %-64s", i, info.GetInt("slot"), cost, info.GetInt("index"), manager.GetUpgradeByIndex(info.GetInt("index")).m_szAttribute());
		}
		
		delete info;
	}
	
	delete new_json;
}

int GetUpgradePriority(JSONObject info)
{
	CMannVsMachineUpgrades upgrade = CMannVsMachineUpgradeManager().GetUpgradeByIndex(info.GetInt("index"));
	
/*	if (info.GetInt("pclass") == view_as<int>(TFClass_Sniper)) {
		if (info.GetInt("slot") == TF_LOADOUT_SLOT_PRIMARY && StrEqual(upgrade.m_szAttribute(), "explosive sniper shot")) {
			return 100;
		}
	}
	
	if (info.GetInt("pclass") == view_as<int>(TFClass_Medic)) {
		if (info.GetInt("slot") == TF_LOADOUT_SLOT_SECONDARY && StrEqual(upgrade.m_szAttribute(), "generate rage on heal")) {
			return 100;
		}
	}
	
	if (info.GetInt("pclass") == view_as<int>(TFClass_Soldier)) {
		if (info.GetInt("slot") == TF_LOADOUT_SLOT_PRIMARY)
		{
			if(StrEqual(upgrade.m_szAttribute(), "heal on kill")) 
				return 90;
			
			if(StrEqual(upgrade.m_szAttribute(), "rocket specialist")) 
				return 80;
		}
	}
	*/
	if (info.GetInt("pclass") == view_as<int>(TFClass_Spy)) 
	{
		if (info.GetInt("slot") == TF_LOADOUT_SLOT_MELEE) 
		{
			if (StrEqual(upgrade.m_szAttribute(), "armor piercing"))
				return 100;
				
			if (StrEqual(upgrade.m_szAttribute(), "melee attack rate bonus"))
				return 90;
				
			if (StrEqual(upgrade.m_szAttribute(), "robo sapper"))
				return 80;
		}
	}
	/*
	if (info.GetInt("pclass") == view_as<int>(TFClass_Heavy)) {
		if (info.GetInt("slot") == TF_LOADOUT_SLOT_PRIMARY && StrEqual(upgrade.m_szAttribute(), "attack projectiles")) {
			return 100;
		}
	}
	
	if (info.GetInt("pclass") == view_as<int>(TFClass_Scout)) {
		if (info.GetInt("slot") == TF_LOADOUT_SLOT_SECONDARY && StrEqual(upgrade.m_szAttribute(), "applies snare effect")) {
			return 100;
		}
	}*/
	
	// low priority for canteen upgrades
	if (info.GetInt("slot") == TF_LOADOUT_SLOT_ACTION) 
		return -10;
	
	// default priority
	return GetRandomInt(50, 100);
}

int FindPriorityIndex(JSONArray array, const char[] key, int value)
{
	int index = -1;
	
	for (int i = 0; i < array.Length; i++)
	{
		JSONObject iObj = view_as<JSONObject>(array.Get(i));
		if (value == iObj.GetInt(key))
		{
			index = i;
			
			delete iObj;
			break;
		}
		
		delete iObj;
	}
	
	return index;
}

void KV_MvM_UpgradesBegin(int client)
{
	m_nPurchasedUpgrades[client] = 0;

	KeyValues kv = new KeyValues("MvM_UpgradesBegin");
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

float GetUpgradeInterval()
{
	float customInterval = redbots_manager_bot_upgrade_interval.FloatValue;
	
	if (customInterval >= 0.0)
		return customInterval;
	
	//Upgrading during an active round, buy upgrades fast
	if (GameRules_GetRoundState() == RoundState_RoundRunning)
		return GetRandomFloat(0.1, 0.75);
	
	const float interval = 1.25;
	const float variance = 0.3;
	
	return GetRandomFloat(interval - variance, interval + variance);
}

JSONObject CTFBotPurchaseUpgrades_ChooseUpgrade(int actor)
{
	int currency = TF2_GetCurrency(actor);
	
	CollectUpgrades(actor);
	
	for (int i = 0; i < CTFPlayerUpgrades[actor].Length; i++) 
	{
		JSONObject info = view_as<JSONObject>(CTFPlayerUpgrades[actor].Get(i));
		
		CMannVsMachineUpgrades upgrades = CMannVsMachineUpgradeManager().GetUpgradeByIndex(info.GetInt("index"));
		if (upgrades.Address == Address_Null)
		{
			if (redbots_manager_debug_actions.BoolValue)
				PrintToServer("CMannVsMachineUpgrades is NULL");
			
			delete info;
			return null;
		}
		
		char attrib[MAX_ATTRIBUTE_DESCRIPTION_LENGTH]; attrib = upgrades.m_szAttribute();
		CEconItemAttributeDefinition attr = CEIAD_GetAttributeDefinitionByName(attrib);
		if (attr.Address == Address_Null)
			continue;
		
		int iAttribIndex = attr.GetIndex();
		if (!CanUpgradeWithAttrib(actor, info.GetInt("slot"), iAttribIndex, upgrades.Address))
		{
			//PrintToServer("upgrade %d/%d: cannot be upgraded with", info.GetInt("slot"), info.GetInt("index"));
			delete info;
			continue;
		}
		
		int iCost = GetCostForUpgrade(upgrades.Address, info.GetInt("slot"), info.GetInt("pclass"), actor);
		if (iCost > currency)
		{
			//PrintToServer("upgrade %d/%d: cost $%d > $%d", info.GetInt("slot"), info.GetInt("index"), iCost, currency);
			
			delete info;
			continue;
		}
	
		int tier = GetUpgradeTier(info.GetInt("index"));
		if (tier != 0) 
		{
			if (!IsUpgradeTierEnabled(actor, info.GetInt("slot"), tier))
			{
				//PrintToServer("upgrade %d/%d: tier %d isn't enabled", info.GetInt("slot"), info.GetInt("index"), tier);
				
				delete info;
				continue;
			}
		}
		
		return info;
	}
	
	return null;
}

void CTFBotPurchaseUpgrades_PurchaseUpgrade(int actor, JSONObject info)
{
	KV_MVM_Upgrade(actor, 1, info.GetInt("slot"), info.GetInt("index"));
	++m_nPurchasedUpgrades[actor];
}

void KV_MVM_Upgrade(int client, int count, int slot, int index)
{
	KeyValues kv = new KeyValues("MVM_Upgrade");
	kv.JumpToKey("upgrade", true);
	kv.SetNum("itemslot", slot);
	kv.SetNum("upgrade", index);
	kv.SetNum("count", count);
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

void KV_MvM_UpgradesDone(int client)
{
	KeyValues kv = new KeyValues("MvM_UpgradesDone");
	kv.SetNum("num_upgrades", m_nPurchasedUpgrades[client]);
	FakeClientCommandKeyValues(client, kv);
	delete kv;
}

void ComputeHealthAndAmmoVectors(int client, JSONArray array, float max_range)
{
	for (int i = 0; i < sizeof(g_strHealthAndAmmoEntities); i++)
	{
		int ammo = -1;
		while ((ammo = FindEntityByClassname(ammo, g_strHealthAndAmmoEntities[i])) != -1)
		{
			if (BaseEntity_GetTeamNumber(ammo) == view_as<int>(GetEnemyTeamOfPlayer(client)))
				continue;
		
			if (GetVectorDistance(WorldSpaceCenter(client), WorldSpaceCenter(ammo)) > max_range)
				continue;
			
			if (BaseEntity_IsBaseObject(ammo))
			{
				//Can't get anything from still building buildings.
				if (TF2_IsBuilding(ammo))
					continue;
				
				if (TF2_GetObjectType(ammo) == TFObject_Dispenser)
				{
					//Skip empty dispenser.
					if (GetEntProp(ammo, Prop_Send, "m_iAmmoMetal") <= 0)
						continue;
				}
			}
			
			float length;
			
			if (!IsPathToVectorPossible(client, WorldSpaceCenter(ammo), length))
				continue;
			
			if (length < max_range)
			{
				JSONObject entity = new JSONObject();
				entity.SetFloat("path_length", length);
				entity.SetInt("entity_index", ammo);
				
				array.Push(entity);
				
				delete entity;
			}
		}
	}
}

bool IsPathToVectorPossible(int bot_entidx, const float vec[3], float &length = -1.0)
{
	CBaseCombatCharacter(bot_entidx).UpdateLastKnownArea();
	
	PathFollower temp_path = PathFollower(_, Path_FilterIgnoreActors, Path_FilterOnlyActors);
	
	bool success = temp_path.ComputeToPos(CBaseNPC_GetNextBotOfEntity(bot_entidx), vec);
	
	length = temp_path.GetLength();
	
	temp_path.Destroy();
	
	return success;
}

bool IsPathToEntityPossible(int bot_entidx, int goal_entidx, float &length = -1.0)
{
	CBaseCombatCharacter(bot_entidx).UpdateLastKnownArea();
	
	CBaseCombatCharacter(goal_entidx).UpdateLastKnownArea();
	
	PathFollower temp_path = PathFollower(_, Path_FilterIgnoreActors, Path_FilterOnlyActors);
	
	bool success = temp_path.ComputeToTarget(CBaseNPC_GetNextBotOfEntity(bot_entidx), goal_entidx);
	
	length = temp_path.GetLength();
	
	temp_path.Destroy();
	
	return success;
}

bool IsValidAmmo(int pack)
{
	if (!IsValidEntity(pack))
		return false;

	if (!HasEntProp(pack, Prop_Send, "m_fEffects"))
		return false;

	//It has been taken.
	if (GetEntProp(pack, Prop_Send, "m_fEffects") != 0)
		return false;

	char class[64]; GetEntityClassname(pack, class, sizeof(class));
	
	if (StrContains(class, "tf_ammo_pack", false) == -1 
	&& StrContains(class, "item_ammo", false) == -1 
	&& StrContains(class, "obj_dispenser", false) == -1
	&& StrContains(class, "func_regen", false) == -1)
	{
		return false;
	}
	
	//Can't use a disabled dispenser
	if (StrContains(class, "obj_dispenser", false) != -1 && TF2_HasSapper(pack))
		return false;
	
	return true;
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

void CTFBotEngineerIdle_FindNestAreaAroundVec(int client, float vec[3])
{
	AreasCollector hAreas = TheNavMesh.CollectAreasInRadius(vec, SENTRY_WATCH_BOMB_RANGE - 1.0);
	
	for (int i = 0; i < hAreas.Count(); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(hAreas.Get(i));
		
		//Can't build in spawn rooms
		if (area.HasAttributeTF(RED_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		float center[3]; area.GetCenter(center);
		
		//Not too close...
		if (GetVectorDistance(vec, center) < 100.0)
			continue;
		
		m_vecNestArea[client] = center;
		break;
	}
	
	delete hAreas;
}

void CTFBotEngineerIdle_FindNestAreaNearTeamSpawnroom(int client, TFTeam team)
{
	int iAreaCount = TheNavMesh.GetNavAreaCount();
	CTFNavArea foundArea;
	
	for (int i = 0; i < iAreaCount; i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		//Area must be a spawn room exit
		if (!area.HasAttributeTF(SPAWN_ROOM_EXIT))
			continue;
		
		//Area should be in the team's spawn room
		if (team == TFTeam_Blue && !area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		if (team == TFTeam_Red && !area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		//Found a spawn room exit area
		foundArea = area;
		break;
	}
	
	AreasCollector hAreas = TheNavMesh.CollectSurroundingAreas(foundArea, 1500.0, 18.0);
	CTFNavArea buildArea;
	
	for (int i = 0; i < hAreas.Count(); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(hAreas.Get(i));
		
		//Our build area should not actually be on an exit
		if (area.HasAttributeTF(SPAWN_ROOM_EXIT))
			continue;
		
		//We can't build in spawn rooms
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		if (area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		buildArea = area;
		break;
	}
	
	delete hAreas;
	
	buildArea.GetCenter(m_vecNestArea[client]);
}

/* bool CNavArea_IsVisible(CNavArea area, float eye[3], float visSpot[3] = NULL_VECTOR)
{
	float offset = 0.75 * 71;

	float center[3]; area.GetCenter(center); center[2] += offset;
	
	// check center first
	Handle result = TR_TraceRayEx(eye, center, MASK_OPAQUE|CONTENTS_MONSTER, RayType_EndPoint);
	
	if (TR_GetFraction(result) == 1.0)
	{
		// we can see this area
		if (!IsNullVector(visSpot))
			area.GetCenter(visSpot);
		
		delete result;
		return true;
	}
	
	delete result;
	
	float corner[3];
	
	for (NavCornerType c = NORTH_WEST; c < NUM_CORNERS; ++c)
	{
		area.GetCorner(c, corner);
		corner[2] += offset;
		
		result = TR_TraceRayEx(eye, corner, MASK_OPAQUE|CONTENTS_MONSTER, RayType_EndPoint);
		
		if (TR_GetFraction(result) == 1.0)
		{
			// we can see this area
			if (!IsNullVector(visSpot))
				visSpot = corner;
			
			delete result;
			return true;
		}
		
		delete result;
	}
	
	delete result;
	return false;
} */

bool CTFBotGetAmmo_IsPossible(int actor)
{
	//Skip lag.
	if (m_iAmmoPack[actor] != -1 && IsValidAmmo(m_iAmmoPack[actor]))
		return true;

	JSONArray ammo = new JSONArray();
	ComputeHealthAndAmmoVectors(actor, ammo, tf_bot_ammo_search_range.FloatValue);
	
	if (ammo.Length <= 0)
	{
		delete ammo;
		return false;
	}

	bool bPossible = false;
	
	for (int i = 0; i < ammo.Length; i++)
	{
		JSONObject entity = view_as<JSONObject>(ammo.Get(i));
		
		if (!IsValidAmmo(entity.GetInt("entity_index")))
		{
			delete entity;
			continue;
		}
		
		bPossible = true;
		delete entity;
		break;
	}
	
	delete ammo;

	return bPossible;
}

bool CTFBotGetHealth_IsPossible(int actor)
{
	if (IsHealedByMedic(actor) || TF2_IsInvulnerable(actor))
		return false;
	
	float health_ratio = float(GetClientHealth(actor)) / float(TF2Util_GetEntityMaxHealth(actor));
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

bool CTFBotAttackTank_SelectTarget(int actor)
{
	m_iTankTarget[actor] = GetTankToTarget(actor);
	
	return m_iTankTarget[actor] != -1;
}

#if defined EXTRA_PLUGINBOT
void SetGoalVector(int bot_entidx, float vec[3])
{
	pb_iPathGoalEntity[bot_entidx] = -1; //Can't have both
	pb_vecPathGoal[bot_entidx] = vec;
}

void SetGoalEntity(int bot_entidx, int goal_entidx)
{
	pb_vecPathGoal[bot_entidx] = NULL_VECTOR;
	pb_iPathGoalEntity[bot_entidx] = goal_entidx;
}
#endif

bool IsAmmoLow(int client)
{
	int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);

	if (IsValidEntity(primary) && !HasAmmo(primary))
		return true;
	
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) != TF_WEAPON_WRENCH)
	{
		if (!IsMeleeWeapon(myWeapon))
		{
			float flAmmoRation = float(GetAmmoCount(client, TF_AMMO_PRIMARY)) / float(GetMaxAmmo(client, TF_AMMO_PRIMARY));
			return flAmmoRation < 0.2;
		}
		
		return false;
	}
	
	return GetAmmoCount(client, TF_AMMO_METAL) <= 0;
}

bool IsAmmoFull(int client)
{
	bool isPrimaryFull = GetAmmoCount(client, TF_AMMO_PRIMARY) >= GetMaxAmmo(client, TF_AMMO_PRIMARY);
	bool isSecondaryFull = GetAmmoCount(client, TF_AMMO_SECONDARY) >= GetMaxAmmo(client, TF_AMMO_SECONDARY);
	
	if (TF2_GetPlayerClass(client) == TFClass_Engineer)
	{
		//In addition, I want some metal as well
		return GetAmmoCount(client, TF_AMMO_METAL) >= 200 && isPrimaryFull && isSecondaryFull;
	}
	
	return isPrimaryFull && isSecondaryFull;
}

void ResetIntentionInterface(int bot_entidx)
{
	INextBot bot = CBaseNPC_GetNextBotOfEntity(bot_entidx);
	bot.GetIntentionInterface().Reset();
}

void UpdateLookAroundForEnemies(int client, bool bVal)
{
	//Method 1
	SetLookingAroundForEnemies(client, bVal);
	
	//Method 2
	/* if (bVal)
	{
		VS_ClearBotAttributes(client);
		
		//Restore things defender bots should have
		if (TF2_GetPlayerClass(client) == TFClass_Medic)
			VS_AddBotAttribute(client, PROJECTILE_SHIELD);
	}
	else
	{
		VS_AddBotAttribute(client, IGNORE_ENEMIES);
	} */
}

bool IsCombatWeapon(int client, int weapon)
{
	if (!IsValidEntity(weapon))
		weapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (IsValidEntity(weapon))
	{
		switch (TF2Util_GetWeaponID(weapon))
		{
			case TF_WEAPON_MEDIGUN, TF_WEAPON_PDA, TF_WEAPON_PDA_ENGINEER_BUILD, TF_WEAPON_PDA_ENGINEER_DESTROY, TF_WEAPON_PDA_SPY, TF_WEAPON_BUILDER, TF_WEAPON_DISPENSER, TF_WEAPON_INVIS, TF_WEAPON_LUNCHBOX, TF_WEAPON_BUFF_ITEM, TF_WEAPON_PUMPKIN_BOMB:
			{
				return false;
			}
		}
    }
	
	return true;
}

float GetDesiredAttackRange(int client)
{
	int weapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (weapon < 1)
		return 0.0;
	
	int weaponID = TF2Util_GetWeaponID(weapon);
	
	if (weaponID == TF_WEAPON_KNIFE)
		return 70.0;
	
	if (IsMeleeWeapon(weapon) || weaponID == TF_WEAPON_FLAMETHROWER)
		return 100.0;
	
	if (HasSniperRifle(client))
		return FLT_MAX;
	
	if (weaponID == TF_WEAPON_ROCKETLAUNCHER)
		return 1250.0;
	
	return 500.0;
}

int GetTankToTarget(int actor, float max_distance = 999999.0)
{
	//TODO: We should be targetting the closest tank that has the farthest progress
	//to the hatch instead of going for the closest one to us
	
	float flOrigin[3]; GetClientAbsOrigin(actor, flOrigin);
	
	float flBestDistance = 999999.0;
	int iBestEntity = -1;
	
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "tank_boss")) != -1)
	{
		//Ignore tanks on our team
		if (GetClientTeam(actor) == BaseEntity_GetTeamNumber(iEnt))
			continue;
		
		float flDistance = GetVectorDistance(flOrigin, WorldSpaceCenter(iEnt));
		
		if (flDistance <= flBestDistance && flDistance <= max_distance)
		{
			flBestDistance = flDistance;
			iBestEntity = iEnt;
		}
	}
	
	return iBestEntity;
}

float GetIdealTankAttackRange(int client)
{
	int weapon = BaseCombatCharacter_GetActiveWeapon(client);
	
	if (weapon > 0)
	{
		if (IsMeleeWeapon(weapon))
		{
			//TODO: factor in other factors for melee
			//GetSwingRange
			//melee_bounds_multiplier
			//melee_range_multiplier
			
			return TANK_ATTACK_RANGE_MELEE;
		}
		
		switch (TF2Util_GetWeaponID(weapon))
		{
			case TF_WEAPON_ROCKETLAUNCHER, TF_WEAPON_GRENADELAUNCHER, TF_WEAPON_FLAREGUN, TF_WEAPON_DIRECTHIT, TF_WEAPON_PARTICLE_CANNON, TF_WEAPON_CANNON:
			{
				return TANK_ATTACK_RANGE_SPLASH;
			}
		}
	}
	
	return TANK_ATTACK_RANGE_DEFAULT;
}

/* void ForgetAllEnemies(int bot_entidx)
{
	INextBot bot = CBaseNPC_GetNextBotOfEntity(bot_entidx);
	IVision vis = bot.GetVisionInterface();
		
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == GetEnemyTeamOfPlayer(bot_entidx))
			vis.ForgetEntity(i);
} */

//Extension of the original function
bool OpportunisticallyUseWeaponAbilities(int client, int activeWeapon, INextBot bot, const CKnownEntity threat)
{
	if (threat == NULL_KNOWN_ENTITY)
		return false;
	
	if (activeWeapon == -1)
		return false;
	
	int weaponID = TF2Util_GetWeaponID(activeWeapon);
	
	//Hitmans Heatmaker
	if (weaponID == TF_WEAPON_SNIPERRIFLE && TF2_IsPlayerInCondition(client, TFCond_Slowed))
	{
		if (TF2_GetRageMeter(client) >= 0.0 && !TF2_IsRageDraining(client))
		{
			g_iAdditionalButtons[client] |= IN_RELOAD;
			return true;
		}
	}
	
	//Phlogistinator
	if (weaponID == TF_WEAPON_FLAMETHROWER && bot.IsRangeLessThan(threat.GetEntity(), 750.0) && !TF2_IsCritBoosted(client))
	{
		if (TF2_GetRageMeter(client) >= 100.0 && !TF2_IsRageDraining(client))
		{
			VS_PressAltFireButton(client);
			return true;
		}
	}
	
	return false;
}

bool OpportunisticallyUsePowerupBottle(int client, int activeWeapon, INextBot bot, const CKnownEntity threat)
{
	if (m_flNextBottleUseTime[client] > GetGameTime())
		return false;
	
	int bottle = GetPowerupBottle(client);
	
	if (bottle == -1)
		return false;
	
	if (PowerupBottle_GetNumCharges(bottle) < 1)
		return false;
	
	switch (m_nCurrentPowerupBottle[client])
	{
		case POWERUP_BOTTLE_CRITBOOST:
		{
			//Can't do anything useful without a weapon
			if (activeWeapon == -1)
				return false;
			
			//No threat to tactually use it against
			if (threat == NULL_KNOWN_ENTITY)
				return false;
			
			//Medic would rather share this than use it for himself
			if (TF2_GetPlayerClass(client) == TFClass_Medic)
				return false;
			
			//Already have crits
			if (TF2_IsCritBoosted(client) || TF2_IsPlayerInCondition(client, TFCond_CritMmmph))
				return false;
			
			int iThreat = threat.GetEntity();
			
			if (!TF2_IsLineOfFireClear4(client, iThreat))
				return false;
			
			int weaponID = TF2Util_GetWeaponID(activeWeapon);
			
			if (weaponID == TF_WEAPON_FLAMETHROWER && bot.IsRangeGreaterThan(iThreat, FLAMETHROWER_REACH_RANGE))
				return false;
			
			if (weaponID == TF_WEAPON_FLAME_BALL && bot.IsRangeGreaterThan(iThreat, FLAMEBALL_REACH_RANGE))
				return false;
			
			if (IsMeleeWeapon(activeWeapon) && bot.IsRangeGreaterThan(iThreat, 100.0))
				return false;
			
			if (BaseEntity_IsPlayer(iThreat))
			{
				/* So basically here we determine based on a few factors
				if our threat is giant and has a lot of health, they're probably a boss
				if we're close to failing and they have a lot of health left, we want to kill them fast
				i really want this to be done better, but we probably need people that actually know what the optimal use of this canteen is */
				if ((TF2_IsMiniBoss(iThreat) && GetClientHealth(iThreat) > 5000) || (IsFailureImminent(client) && GetClientHealth(iThreat) > 900))
				{
					UseActionSlotItem(client);
					return true;
				}
			}
			else if (IsBaseBoss(iThreat) && BaseEntity_GetHealth(iThreat) > 1000)
			{
				//Crit against the tank
				UseActionSlotItem(client);
				return true;
			}
		}
		case POWERUP_BOTTLE_UBERCHARGE:
		{
			//I'm invincible already
			if (TF2_IsInvulnerable(client))
				return false;
			
			//Only when there's a threat nearby, otherwise we could just go heal ourselves
			if (!threat || !threat.IsVisibleRecently())
				return false;
			
			float healthRatio = float(GetClientHealth(client)) / float(TF2Util_GetEntityMaxHealth(client));
			
			if (healthRatio < tf_bot_health_critical_ratio.FloatValue)
			{
				//I'm about to die
				UseActionSlotItem(client);
				m_flNextBottleUseTime[client] = GetGameTime() + GetRandomFloat(10.0, 30.0);
				return true;
			}
			
			if (TF2_IsPlayerInCondition(client, TFCond_Gas))
			{
				//This gas might be explosive
				UseActionSlotItem(client);
				m_flNextBottleUseTime[client] = GetGameTime() + GetRandomFloat(20.0, 30.0);
				return true;
			}
		}
		case POWERUP_BOTTLE_RECALL:
		{
			//TODO: medic can't share this, but he could use it for himself in an attempt to defend the hatch
			if (TF2_GetPlayerClass(client) == TFClass_Medic)
				return false;
			
			float myPosition[3]; myPosition = WorldSpaceCenter(client);
			
			//I'm already in my spawn room
			if (TF2Util_IsPointInRespawnRoom(myPosition, client, true))
				return false;
			
			float hatchPosition[3]; hatchPosition = GetBombHatchPosition();
			
			//We're already close enough to the hatch
			if (GetVectorDistance(myPosition, hatchPosition) <= 1000.0)
				return false;
			
			int flag = FindBombNearestToHatch();
			
			//No bomb active
			if (flag == -1)
				return false;
			
			float bombPosition[3]; bombPosition = WorldSpaceCenter(flag);
			
			//Bomb is far and not a threat
			if (GetVectorDistance(bombPosition, hatchPosition) > BOMB_HATCH_RANGE_CRITICAL)
				return false;
			
			int closestToHatch = FindBotNearestToBombNearestToHatch(client);
			
			//No robot near the bomb close to the hatch
			if (closestToHatch == -1)
				return false;
			
			float threatPosition[3]; GetClientAbsOrigin(closestToHatch, threatPosition);
			
			//Nearest robot isn't that close to the bomb
			if (GetVectorDistance(threatPosition, bombPosition) > 800.0)
				return false;
			
			//We are already close enough to deal with it
			if (GetVectorDistance(myPosition, threatPosition) <= 500.0)
				return false;
			
			UseActionSlotItem(client);
			return true;
		}
		case POWERUP_BOTTLE_REFILL_AMMO:
		{
			int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
			
			if (primary != -1 && !HasAmmo(primary))
			{
				//I got no ammo
				UseActionSlotItem(client);
				return true;
			}
		}
		case POWERUP_BOTTLE_BUILDINGS_INSTANT_UPGRADE:
		{
			//TODO
		}
	}
	
	return false;
}

void EquipBestWeaponForThreat(int client, const CKnownEntity threat)
{
	//Don't care about any weapon restrictions here
	
	int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	
	if (!IsCombatWeapon(client, primary))
		primary = -1;
	
	int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	
	if (!IsCombatWeapon(client, secondary))
		secondary = -1;
	
	//Don't care about mvm-specific rules here
	
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	
	if (!IsCombatWeapon(client, melee))
		melee = -1;
	
	int gun = -1;
	
	if (primary != -1)
		gun = primary;
	else if (secondary != -1)
		gun = secondary;
	else
		gun = melee;
	
	//TODO: not accurate, should be using offset of variable m_difficulty instead
	/* if (GetEntProp(client, Prop_Send, "m_nBotSkill") == CTFBot_EASY)
	{
		if (gun != -1)
			TF2Util_SetPlayerActiveWeapon(client, gun);
		
		return;
	} */
	
	if (threat == NULL_KNOWN_ENTITY || !threat.WasEverVisible() || threat.GetTimeSinceLastSeen() > 5.0)
	{
		if (gun != -1)
			TF2Util_SetPlayerActiveWeapon(client, gun);
		
		return;
	}
	
	if (GetAmmoCount(client, TF_AMMO_PRIMARY) <= 0)
		primary = -1;
	
	if (GetAmmoCount(client, TFWeaponSlot_Secondary) <= 0)
		secondary = -1;
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(client);
	
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_DemoMan, TFClass_Heavy, TFClass_Spy, TFClass_Medic, TFClass_Engineer:
		{
			//Uses primary
		}
		case TFClass_Scout:
		{
			if (secondary != -1)
				if (gun != -1 && !Clip1(gun))
					gun = secondary;
		}
		case TFClass_Soldier:
		{
			if (gun != -1 && !Clip1(gun))
			{
				if (secondary != -1 && Clip1(secondary))
				{
					const float closeSoldierRange = 500.0;
					
					float lastKnownPos[3]; threat.GetLastKnownPosition(lastKnownPos);
					
					if (myBot.IsRangeLessThanEx(lastKnownPos, closeSoldierRange))
						gun = secondary;
				}
			}
		}
		case TFClass_Sniper:
		{
			if (primary != -1 && TF2Util_GetWeaponID(primary) == TF_WEAPON_COMPOUND_BOW)
			{
				//Always use the bow, unless it has no ammo
				gun = primary;
			}
			else
			{
				const float closeSniperRange = 750.0;
				
				float lastKnownPos[3]; threat.GetLastKnownPosition(lastKnownPos);
				
				if (secondary != -1 && myBot.IsRangeLessThanEx(lastKnownPos, closeSniperRange))
					gun = secondary;
			}
		}
		case TFClass_Pyro:
		{
			const float flameRange = 750.0;
			
			float lastKnownPos[3]; threat.GetLastKnownPosition(lastKnownPos);
			
			if (secondary != -1 && myBot.IsRangeGreaterThanEx(lastKnownPos, flameRange))
				gun = secondary;
			
			int threatEnt = threat.GetEntity();
			
			if (BaseEntity_IsPlayer(threatEnt))
			{
				TFClassType threatClass = TF2_GetPlayerClass(threatEnt);
				
				if (threatClass == TFClass_Soldier || threatClass == TFClass_DemoMan)
					gun = primary;
			}
		}
	}
	
	if (gun != -1)
		TF2Util_SetPlayerActiveWeapon(client, gun);
}

int EvalTankWeapon_Scout(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_SCATTERGUN, TF_WEAPON_PEP_BRAWLER_BLASTER, TF_WEAPON_SODA_POPPER, TF_WEAPON_HANDGUN_SCOUT_PRIMARY:
		{
			return 100;
		}
		case TF_WEAPON_BAT, TF_WEAPON_BAT_FISH, TF_WEAPON_BAT_WOOD:
		{
			return 80;
		}
		case TF_WEAPON_PISTOL, TF_WEAPON_PISTOL_SCOUT, TF_WEAPON_HANDGUN_SCOUT_SEC:
		{
			return 60;
		}
		case TF_WEAPON_BAT_GIFTWRAP:
		{
			return 20;
		}
		case TF_WEAPON_CLEAVER, TF_WEAPON_LUNCHBOX, TF_WEAPON_JAR, TF_WEAPON_JAR_MILK:
		{
			return 0;
		}
	}
	
	//Fallback for unknown weapon IDs
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 60;
		case TFWeaponSlot_Melee:	return 80;
		default:	return 10;
	}
}

int EvalTankWeapon_Soldier(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_ROCKETLAUNCHER, TF_WEAPON_PARTICLE_CANNON, TF_WEAPON_DIRECTHIT:
		{
			return 100;
		}
		case TF_WEAPON_SHOVEL, TF_WEAPON_BOTTLE, TF_WEAPON_SWORD:
		{
			return 80;
		}
		case TF_WEAPON_SHOTGUN_PRIMARY, TF_WEAPON_SHOTGUN_SOLDIER, TF_WEAPON_SHOTGUN_HWG, TF_WEAPON_SHOTGUN_PYRO, TF_WEAPON_RAYGUN:
		{
			return 60;
		}
		case TF_WEAPON_BUFF_ITEM, TF_WEAPON_PARACHUTE:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 60;
		case TFWeaponSlot_Melee:	return 80;
		default:	return 10;
	}
}

int EvalTankWeapon_Pyro(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_FLAMETHROWER, TF_WEAPON_FLAMETHROWER_ROCKET:
		{
			return 100;
		}
		case TF_WEAPON_FIREAXE:
		{
			return 80;
		}
		case TF_WEAPON_SHOTGUN_PRIMARY, TF_WEAPON_SHOTGUN_SOLDIER, TF_WEAPON_SHOTGUN_HWG, TF_WEAPON_SHOTGUN_PYRO:
		{
			return 60;
		}
		case TF_WEAPON_FLAREGUN, TF_WEAPON_RAYGUN_REVENGE:
		{
			return 20;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 20;
		case TFWeaponSlot_Melee:	return 80;
		default:	return 10;
	}
}

int EvalTankWeapon_Demo(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_GRENADELAUNCHER, TF_WEAPON_CANNON:
		{
			return 100;
		}
		case TF_WEAPON_BOTTLE, TF_WEAPON_SHOVEL, TF_WEAPON_SWORD, TF_WEAPON_STICKBOMB:
		{
			return 80;
		}
		case TF_WEAPON_BUFF_ITEM, TF_WEAPON_PARACHUTE, TF_WEAPON_PIPEBOMBLAUNCHER, TF_WEAPON_STICKY_BALL_LAUNCHER:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 0;
		case TFWeaponSlot_Melee:	return 80;
		default:	return 10;
	}
}

int EvalTankWeapon_Heavy(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_MINIGUN:
		{
			return 100;
		}
		case TF_WEAPON_FISTS, TF_WEAPON_FIREAXE:
		{
			return 80;
		}
		case TF_WEAPON_SHOTGUN_PRIMARY, TF_WEAPON_SHOTGUN_SOLDIER, TF_WEAPON_SHOTGUN_HWG, TF_WEAPON_SHOTGUN_PYRO:
		{
			return 60;
		}
		case TF_WEAPON_LUNCHBOX:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 0;
		case TFWeaponSlot_Melee:	return 60;
		default:	return 10;
	}
}

int EvalTankWeapon_Engie(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_WRENCH, TF_WEAPON_MECHANICAL_ARM:
		{
			return 100;
		}
		case TF_WEAPON_SHOTGUN_PRIMARY, TF_WEAPON_SHOTGUN_SOLDIER, TF_WEAPON_SHOTGUN_HWG, TF_WEAPON_SHOTGUN_PYRO, TF_WEAPON_SENTRY_REVENGE, TF_WEAPON_DRG_POMSON:
		{
			return 80;
		}
		case TF_WEAPON_SHOTGUN_BUILDING_RESCUE:
		{
			return 60;
		}
		case TF_WEAPON_PISTOL, TF_WEAPON_PISTOL_SCOUT, TF_WEAPON_REVOLVER:
		{
			return 40;
		}
		case TF_WEAPON_PDA, TF_WEAPON_PDA_ENGINEER_BUILD, TF_WEAPON_PDA_ENGINEER_DESTROY, TF_WEAPON_PDA_SPY, TF_WEAPON_PDA_SPY_BUILD, TF_WEAPON_BUILDER, TF_WEAPON_LASER_POINTER, TF_WEAPON_DISPENSER, TF_WEAPON_DISPENSER_GUN:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 80;
		case TFWeaponSlot_Secondary:	return 0;
		case TFWeaponSlot_Melee:	return 100;
		default:	return 10;
	}
}

int EvalTankWeapon_Medic(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_BONESAW, TF_WEAPON_HARVESTER_SAW:
		{
			return 100;
		}
		case TF_WEAPON_SYRINGEGUN_MEDIC, TF_WEAPON_NAILGUN:
		{
			return 80;
		}
		case TF_WEAPON_CROSSBOW:
		{
			return 60;
		}
		case TF_WEAPON_MEDIGUN:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 80;
		case TFWeaponSlot_Secondary:	return 0;
		case TFWeaponSlot_Melee:	return 100;
		default:	return 10;
	}
}

int EvalTankWeapon_Sniper(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_SNIPERRIFLE, TF_WEAPON_SNIPERRIFLE_DECAP, TF_WEAPON_SNIPERRIFLE_CLASSIC:
		{
			return 100;
		}
		case TF_WEAPON_COMPOUND_BOW:
		{
			return 80;
		}
		case TF_WEAPON_CLUB:
		{
			return 60;
		}
		case TF_WEAPON_CHARGED_SMG, TF_WEAPON_SMG:
		{
			return 40;
		}
		case TF_WEAPON_JAR, TF_WEAPON_JAR_MILK:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 40;
		case TFWeaponSlot_Melee:	return 60;
		default:	return 10;
	}
}

int EvalTankWeapon_Spy(int slot, int weapon)
{
	switch (TF2Util_GetWeaponID(weapon))
	{
		case TF_WEAPON_REVOLVER:
		{
			return 100;
		}
		case TF_WEAPON_KNIFE:
		{
			return 80;
		}
		case TF_WEAPON_PDA, TF_WEAPON_PDA_ENGINEER_BUILD, TF_WEAPON_PDA_ENGINEER_DESTROY, TF_WEAPON_PDA_SPY, TF_WEAPON_PDA_SPY_BUILD, TF_WEAPON_BUILDER, TF_WEAPON_INVIS:
		{
			return 0;
		}
	}
	
	switch (slot)
	{
		case TFWeaponSlot_Primary:	return 100;
		case TFWeaponSlot_Secondary:	return 0;
		case TFWeaponSlot_Melee:	return 80;
		default:	return 10;
	}
}

//Uses a score-based system to determine what weapon the bot should be using against a tank boss
void EquipBestTankWeapon(int client)
{
	int best_weapon = -1;
	int best_score = 0;
	
	for (int slot = TFWeaponSlot_Primary; slot <= TFWeaponSlot_Melee; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		
		if (weapon == -1)
			continue;
		
		// int id = TF2Util_GetWeaponID(weapon);
		
		int score;
		
		switch (TF2_GetPlayerClass(client))
		{
			case TFClass_Scout:	score = EvalTankWeapon_Scout(slot, weapon);
			case TFClass_Sniper:	score = EvalTankWeapon_Sniper(slot, weapon);
			case TFClass_Soldier:	score = EvalTankWeapon_Soldier(slot, weapon);
			case TFClass_DemoMan:	score = EvalTankWeapon_Demo(slot, weapon);
			case TFClass_Medic:	score = EvalTankWeapon_Medic(slot, weapon);
			case TFClass_Heavy:	score = EvalTankWeapon_Heavy(slot, weapon);
			case TFClass_Pyro:	score = EvalTankWeapon_Pyro(slot, weapon);
			case TFClass_Spy:	score = EvalTankWeapon_Spy(slot, weapon);
			case TFClass_Engineer:	score = EvalTankWeapon_Engie(slot, weapon);
		}
		
		if (best_weapon == -1 || score > best_score)
		{
			best_weapon = weapon;
			best_score = score;
		}
	}
	
	if (best_weapon == -1)
	{
		LogError("EquipBestTankWeapon: no valid weapons!");
		return;
	}
	
	TF2Util_SetPlayerActiveWeapon(client, best_weapon);
}

//Get the medic healing this threat
//If we don't know about him yet or he has no healer, then we return the original threat
CKnownEntity GetHealerOfThreat(INextBot bot, const CKnownEntity threat)
{
	if (!threat)
		return NULL_KNOWN_ENTITY;
	
	int threatEnt = threat.GetEntity();
	
	for (int i = 0; i < TF2_GetNumHealers(threatEnt); i++)
	{
		int healer = TF2_GetHealerByIndex(threatEnt, i);
		
		if (healer != -1 && BaseEntity_IsPlayer(healer))
		{
			CKnownEntity knownHealer = bot.GetVisionInterface().GetKnown(threatEnt);
			
			if (knownHealer && knownHealer.IsVisibleInFOVNow())
				return knownHealer;
		}
	}
	
	return threat;
}

CKnownEntity SelectCloserThreat(INextBot bot, const CKnownEntity threat1, const CKnownEntity threat2)
{
	float rangeSq1 = bot.GetRangeSquaredTo(threat1.GetEntity());
	float rangeSq2 = bot.GetRangeSquaredTo(threat2.GetEntity());
	
	if (rangeSq1 < rangeSq2)
		return threat1;
	
	return threat2;
}

void MonitorKnownEntities(int client, IVision vision)
{
	static int maxEntCount = 0;
	
	if (maxEntCount == 0)
		maxEntCount = GetMaxEntities();
	
	int myTeam = GetClientTeam(client);
	
	for (int i = 1; i <= maxEntCount; i++)
	{
		if (!IsValidEntity(i))
			continue;
		
		if (i == client)
			continue;
		
		if (BaseEntity_IsPlayer(i) && !IsPlayerAlive(i))
			continue;
		
		if (CBaseEntity(i).IsCombatCharacter() == false)
			continue;
		
		if (BaseEntity_GetTeamNumber(i) == myTeam)
			continue;
		
		//If the threat is within our visible sightline, we will know about it
		if (TF2_IsLineOfFireClear4(client, i))
			vision.AddKnownEntity(i);
	}
}

bool CTFBotSpySap_SelectTarget(int actor)
{
	m_iSapTarget[actor] = GetNearestSappableObject(actor, 2000.0);
	
	return m_iSapTarget[actor] != -1;
}

bool CTFBotSpySapPlayers_SelectTarget(int actor)
{
	if (!CanUseSapper(actor))
		return false;
	
	m_iPlayerSapTarget[actor] = GetNearestSappablePlayer(actor, 1000.0, true, 230.0);
	
	if (m_iPlayerSapTarget[actor] == -1)
	{
		int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
		
		if (secondary != -1 && TF2Util_GetWeaponID(secondary) == TF_WEAPON_BUILDER && TF2Attrib_GetByName(secondary, "robo sapper") != Address_Null)
		{
			const float groupRadius = 600.0;
			
			//If there's a group of enemies near us, let's put a sapper on one of them
			if (GetNearestEnemyCount(actor, groupRadius) >= 4)
				m_iPlayerSapTarget[actor] = GetFarthestSappablePlayer(actor, groupRadius);
		}
	}
	
	return m_iPlayerSapTarget[actor] != -1;
}

bool CanUseSapper(int client)
{
	if (m_flSapperCooldown[client] > GetGameTime())
		return false;
	
	return true;
}

void SetSapperCooldown(int client, float duration)
{
	m_flSapperCooldown[client] = duration <= 0.0 ? duration : GetGameTime() + duration;
}

bool CTFBotCampBomb_IsPossible(int client)
{
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Scout, TFClass_Medic:
		{
			//We're not very useful for this
			return false;
		}
	}
	
	int flag = FindBombNearestToHatch();
	
	if (flag == -1)
		return false;
	
	if (BaseEntity_GetOwnerEntity(flag) != -1)
	{
		//No point in camping since DefenderAttack goes for the bomb carrier
		return false;
	}
	
	// float hatchPosition[3]; hatchPosition = GetBombHatchPosition();
	float bombPosition[3]; bombPosition = WorldSpaceCenter(flag);
	
	/* if (GetVectorDistance(hatchPosition, bombPosition) > BOMB_HATCH_RANGE_OKAY)
	{
		//The bomb is stil pretty far from the hatch
		return false;
	} */
	
	int iEnt = -1;
	const float maxWatchRadius = 1000.0;
	
	while ((iEnt = FindEntityByClassname(iEnt, "obj_sentrygun")) != -1)
	{
		if (BaseEntity_GetTeamNumber(iEnt) != GetClientTeam(client))
			continue;
		
		if (GetVectorDistance(bombPosition, WorldSpaceCenter(iEnt)) <= maxWatchRadius)
		{
			//There;s a sentry watching the bomb
			return false;
		}
	}
	
	//There;s too many of us doing this behavior
	if (GetBotBombCampCount() > 0)
		return false;
	
	return true;
}

int GetBotBombCampCount()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_bIsDefenderBot[i] && ActionsManager.GetAction(i, "DefenderCampBomb") != INVALID_ACTION)
			count++;
	
	return count;
}

void UtilizeCompressionBlast(int client, INextBot bot, const CKnownEntity threat, int enhancedStage = 0)
{
	if (threat == NULL_KNOWN_ENTITY)
		return;
	
	int iThreat = threat.GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat))
	{
		float threatOrigin[3]; GetClientAbsOrigin(iThreat, threatOrigin);
		
		//Make sure we're close enough to actually airblast them
		if (bot.IsRangeLessThanEx(threatOrigin, 250.0))
		{
			if (TF2_IsInvulnerable(iThreat))
			{
				//Shove ubers away from us
				VS_PressAltFireButton(client);
				return;
			}
			
			if (TF2_HasTheFlag(iThreat) && GetVectorDistance(threatOrigin, GetBombHatchPosition()) <= 100.0)
			{
				//Shove the bomb carrier off the hatch
				VS_PressAltFireButton(client);
				return;
			}
		}
	}
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

bool CTFBotEvadeBuster_IsPossible(int client)
{
	//Nobody is detonating themselves
	if (!IsValidClientIndex(g_iDetonatingPlayer))
		return false;
	
	float myOrigin[3]; GetClientAbsOrigin(client, myOrigin);
	float theirOrigin[3]; GetClientAbsOrigin(g_iDetonatingPlayer, theirOrigin);
	
	//Not a threat to me
	if (GetVectorDistance(myOrigin, theirOrigin) > tf_bot_suicide_bomb_range.FloatValue)
		return false;
	
	return true;
}

void PurchaseAffordableCanteens(int client, int count = 3)
{
	int bottle = GetPowerupBottle(client);
	
	if (bottle == -1)
	{
		LogError("PurchaseAffordableCanteens: %N (%d) tried to upgrade canteen, but he don't have a powerup bottle!", client, client);
		return;
	}
	
	int currentCharges = PowerupBottle_GetNumCharges(bottle);
	int desiredType = POWERUP_BOTTLE_NONE;
	
	if (currentCharges > 0)
	{
		//We buy less if we already have charges on it
		//We also only want to buy more of that canteen type
		count = PowerupBottle_GetMaxNumCharges(bottle) - currentCharges;
		desiredType = PowerupBottle_GetType(bottle);
		
		if (redbots_manager_debug.BoolValue)
			PrintToChatAll("[PurchaseAffordableCanteens] %N desires %d more charges of canteen type %d", client, count, desiredType);
	}
	
	int currency = TF2_GetCurrency(client);
	const int slot = TF_LOADOUT_SLOT_ACTION;
	int iClass = view_as<int>(TF2_GetPlayerClass(client));
	ArrayList adtAffordableCanteens = new ArrayList();
	
	for (int i = 0; i < MAX_UPGRADES; i++)
	{
		CMannVsMachineUpgrades upgrades = CMannVsMachineUpgradeManager().GetUpgradeByIndex(i);
		
		if (upgrades.m_iUIGroup() != UIGROUP_POWERUPBOTTLE) 
			continue;
		
		char attributeName[MAX_ATTRIBUTE_DESCRIPTION_LENGTH]; attributeName = upgrades.m_szAttribute();
		
		//We desire a specific type of canteen if we currently have a charge on it
		switch (desiredType)
		{
			case POWERUP_BOTTLE_CRITBOOST:
			{
				if (!StrEqual(attributeName, "critboost"))
					continue;
			}
			case POWERUP_BOTTLE_UBERCHARGE:
			{
				if (!StrEqual(attributeName, "ubercharge"))
					continue;
			}
			case POWERUP_BOTTLE_RECALL:
			{
				if (!StrEqual(attributeName, "recall"))
					continue;
			}
			case POWERUP_BOTTLE_REFILL_AMMO:
			{
				if (!StrEqual(attributeName, "refill_ammo"))
					continue;
			}
			case POWERUP_BOTTLE_BUILDINGS_INSTANT_UPGRADE:
			{
				if (!StrEqual(attributeName, "building instant upgrade"))
					continue;
			}
		}
		
		CEconItemAttributeDefinition attr = CEIAD_GetAttributeDefinitionByName(attributeName);
		
		//Attribute doesn't exist
		if (attr.Address == Address_Null)
			continue;
		
		int attribDefinitionIndex = attr.GetIndex();
		
		//Likely a class that can't use this upgrade
		if (!CanUpgradeWithAttrib(client, slot, attribDefinitionIndex, upgrades.Address))
			continue;
		
		int cost = GetCostForUpgrade(upgrades.Address, slot, iClass, client);
		
		//I can't afford this upgrade
		if (cost > currency)
			continue;
		
		adtAffordableCanteens.Push(i);
	}
	
	if (adtAffordableCanteens.Length == 0)
	{
		//We could not afford anything at this time
		delete adtAffordableCanteens;
		return;
	}
	
	//Randomly pick an affordable charge type
	int selectedUpgradeIndex = adtAffordableCanteens.Get(GetRandomInt(0, adtAffordableCanteens.Length - 1));
	delete adtAffordableCanteens;
	
	CMannVsMachineUpgrades selectedUpgrade = CMannVsMachineUpgradeManager().GetUpgradeByIndex(selectedUpgradeIndex);
	int selectedCost = GetCostForUpgrade(selectedUpgrade.Address, slot, iClass, client);
	int purchaseAmount = 0;
	
	//Now how many charges can we actually afford of the selected type?
	for (int i = 0; i < count; i++)
	{
		if (currency < selectedCost)
			break;
		
		currency -= selectedCost;
		purchaseAmount++;
	}
	
	KV_MVM_Upgrade(client, purchaseAmount, slot, selectedUpgradeIndex);
	
	//Update our current bottle type so we're aware of what we have
	m_nCurrentPowerupBottle[client] = PowerupBottle_GetType(bottle);
	
	if (redbots_manager_debug.BoolValue)
		PrintToChatAll("PurchaseAffordableCanteens: %N purchased %d charges (upgrade %d) and wanted %d charges", client, purchaseAmount, selectedUpgradeIndex, count);
}

void UpgradeMidRoundPostActivity(int client)
{
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_Medic:
		{
			int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
			
			if (secondary != -1)
				SetEntPropFloat(secondary, Prop_Send, "m_flChargeLevel", 1.0);
			
			SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
		}
	}
}

bool ShouldBuybackIntoGame(int client)
{
	//Scouts respawn very quickly
	if (TF2_GetPlayerClass(client) == TFClass_Scout)
		return false;
	
	//Can't afford a buyback
	if (TF2_GetCurrency(client) < MVM_BUYBACK_COST_PER_SEC)
		return false;
	
	//Not opportunistic if we're about to fail
	if (IsFailureImminent(client))
		return true;
	
	//We're being revived
	if (g_bIsBeingRevived[client])
		return false;
	
	return g_iBuybackNumber[client] <= redbots_manager_bot_buyback_chance.IntValue;
}

bool ShouldUpgradeMidRound(int client)
{
	return g_iBuyUpgradesNumber[client] > 0 && g_iBuyUpgradesNumber[client] <= redbots_manager_bot_buy_upgrades_chance.IntValue;
}

bool CanBuyUpgradesNow(int client)
{
	if (TF2_GetCurrency(client) < 25)
		return false;
	
	if (IsFailureImminent(client))
		return false;
	
	return true;
}

/* float TransientlyConsistentRandomValue(int client, float period = 10.0, int seedValue = 0)
{
	CNavArea area = CBaseCombatCharacter(client).GetLastKnownArea();
	
	if (!area)
		return 0.0;
	
	int timeMod = RoundToFloor(GetGameTime() / period) + 1;
	
	return FloatAbs(Cosine(float(seedValue + (client * area.GetID() * timeMod))));
} */

bool IsFailureImminent(int client)
{
	//TODO: factor in tank closest to hatch for certain classes
	
	int flag = FindBombNearestToHatch();
	
	if (flag == -1)
		return false;
	
	float bombPosition[3]; bombPosition = WorldSpaceCenter(flag);
	
	//Bomb is far and not a threat
	if (GetVectorDistance(bombPosition, GetBombHatchPosition()) > BOMB_HATCH_RANGE_CRITICAL)
		return false;
	
	int closestToHatch = FindBotNearestToBombNearestToHatch(client);
	
	//No robot near the bomb close to the hatch, we're probably okay for now
	if (closestToHatch == -1)
		return false;
	
	float threatOrigin[3]; GetClientAbsOrigin(closestToHatch, threatOrigin);
	
	//Robot about to pick up a bomb very close to the hatch, we're in danger!
	return GetVectorDistance(threatOrigin, bombPosition) <= 800.0;
}

bool CTFBotDestroyTeleporter_SelectTarget(int actor)
{
	m_iTeleporterTarget[actor] = GetNearestEnemyTeleporter(actor);
	
	return m_iTeleporterTarget[actor] != -1;
}

int GetTeleporterKillerCount()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_bIsDefenderBot[i] && ActionsManager.GetAction(i, "DefenderKillTeleporter") != INVALID_ACTION)
			count++;
	
	return count;
}