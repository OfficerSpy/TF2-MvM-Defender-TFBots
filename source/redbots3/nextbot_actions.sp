#define TANK_ATTACK_RANGE_MELEE	1.0
#define TANK_ATTACK_RANGE_SPLASH	400.0
#define TANK_ATTACK_RANGE_DEFAULT	100.0
#define BOMB_TOO_CLOSE_RANGE	1000.0

static char g_strHealthAndAmmoEntities[][] = 
{
	"func_regenerate",
	"item_ammopack*",
	"item_health*",
	"obj_dispenser",
	"tf_ammo_pack"
}

static int MAX_INT = 99999999;
static int MIN_INT = -99999999;

static float m_flNextSnipeFireTime[MAXPLAYERS + 1];

PathFollower m_pPath[MAXPLAYERS + 1];
// ChasePath m_chasePath[MAXPLAYERS + 1];
static float m_flRepathTime[MAXPLAYERS + 1];

static int m_iAttackTarget[MAXPLAYERS + 1];
// float g_flRevalidateTarget[MAXPLAYERS + 1];
static int m_iTarget[MAXPLAYERS + 1];
static float m_flNextMarkTime[MAXPLAYERS + 1];
static int m_iCurrencyPack[MAXPLAYERS + 1];
static int m_iStation[MAXPLAYERS + 1];
static JSONArray CTFPlayerUpgrades[MAXPLAYERS + 1];
static float m_flNextUpgrade[MAXPLAYERS + 1];
static int m_nPurchasedUpgrades[MAXPLAYERS + 1];
static int m_iAmmoPack[MAXPLAYERS + 1];
static float m_vecGoalArea[MAXPLAYERS + 1][3];
static float m_ctMoveTimeout[MAXPLAYERS + 1];
static int m_iHealthPack[MAXPLAYERS + 1];
static float m_ctSentrySafe[MAXPLAYERS + 1];
static float m_ctSentryCooldown[MAXPLAYERS + 1];
static float m_ctDispenserSafe[MAXPLAYERS + 1]; 
static float m_ctDispenserCooldown[MAXPLAYERS + 1];
static float m_ctFindNestHint[MAXPLAYERS + 1]; 
static float m_ctAdvanceNestSpot[MAXPLAYERS + 1]; 
static float m_ctRecomputePathMvMEngiIdle[MAXPLAYERS + 1];
static CNavArea m_aNestArea[MAXPLAYERS + 1] = {NULL_AREA, ...};
static bool g_bGoingToGrabBuilding[MAXPLAYERS + 1];
static int m_iBuildingToGrab[MAXPLAYERS + 1];

//Replicate behavior of PathFollower's PluginBot
bool pb_bPath[MAXPLAYERS + 1];
float pb_vecPathGoal[MAXPLAYERS + 1][3];
int pb_iPathGoalEntity[MAXPLAYERS + 1];

void InitNextBotPathing()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		m_pPath[i] = PathFollower(_, Path_FilterIgnoreActors, Path_FilterOnlyActors);
		// m_chasePath[i] = ChasePath(_, _, Path_FilterIgnoreActors, Path_FilterOnlyActors);
	}
}

void ResetNextBot(int client)
{
	m_flRepathTime[client] = 0.0;
	m_iAttackTarget[client] = -1;
	m_iTarget[client] = -1;
	m_flNextMarkTime[client] = 0.0;
	m_iCurrencyPack[client] = -1;
	m_iStation[client] = -1;
	m_flNextUpgrade[client] = 0.0;
	m_nPurchasedUpgrades[client] = 0;
	m_iAmmoPack[client] = -1;
	m_vecGoalArea[client] = NULL_VECTOR;
	m_ctMoveTimeout[client] = 0.0;
	m_iHealthPack[client] = -1;
	m_ctSentrySafe[client] = 0.0;
	m_ctSentryCooldown[client] = 0.0;
	m_ctDispenserSafe[client] = 0.0;
	m_ctDispenserCooldown[client] = 0.0;
	m_ctFindNestHint[client] = 0.0;
	m_ctAdvanceNestSpot[client] = 0.0;
	m_ctRecomputePathMvMEngiIdle[client] = 0.0;
	m_aNestArea[client] = NULL_AREA;
	g_bGoingToGrabBuilding[client] = false;
	m_iBuildingToGrab[client] = -1;
	
	pb_bPath[client] = false;
	pb_vecPathGoal[client] = NULL_VECTOR;
	pb_iPathGoalEntity[client] = -1;
}

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
				
				m_flRepathTime[client] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			}
			
			//I don't see a reason to use UpdateLastKnownArea again
			
			m_pPath[client].Update(myBot);
		}
	}
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	//TFBots are players, ignore all other nextbots
	if (actor <= MaxClients)
	{
		if (StrEqual(name, "TacticalMonitor"))
		{
			action.Update = CTFBotTacticalMonitor_Update;
		}
		else if (StrEqual(name, "ScenarioMonitor"))
		{
			action.Update = CTFBotScenarioMonitor_Update;
			action.InitialContainedAction = CTFBotScenarioMonitor_InitialContainedAction;
			action.InitialContainedActionPost = CTFBotScenarioMonitor_InitialContainedActionPost;
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
			action.Update = CTFBotSniperLurk_Update;
			action.SelectMoreDangerousThreat = CTFBotSniperLurk_SelectMoreDangerousThreat;
		}
		else if (StrEqual(name, "SpyAttack"))
		{
			action.SelectMoreDangerousThreat = CTFBotSpyAttack_SelectMoreDangerousThreat;
		}
	}
}

public Action CTFBotTacticalMonitor_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor])
	{
		MonitorKnownEntities(actor, CBaseNPC_GetNextBotOfEntity(actor).GetVisionInterface());
		
		if (GameRules_GetRoundState() == RoundState_RoundRunning)
		{
			bool low_health = false;
			
			float health_ratio = view_as<float>(GetClientHealth(actor)) / view_as<float>(BaseEntity_GetMaxHealth(actor));
			
			if ((GetTimeSinceWeaponFired(actor) > 2.0 || TF2_GetPlayerClass(actor) == TFClass_Sniper) && health_ratio < tf_bot_health_critical_ratio.FloatValue)
				low_health = true;
			else if (health_ratio < tf_bot_health_ok_ratio.FloatValue)
				low_health = true;
			
			if (low_health && CTFBotGetHealth_IsPossible(actor) && !TF2_IsInvulnerable(actor))
				return action.SuspendFor(CTFBotGetHealth(), "Getting health");
			else if (IsAmmoLow(actor) && CTFBotGetAmmo_IsPossible(actor))
				return action.SuspendFor(CTFBotGetAmmo(), "Getting ammo");
			
			OpportunisticallyUseWeaponAbilities(actor);
			//TODO: use canteens
		}
	}
	
	return Plugin_Continue;
}

public Action CTFBotScenarioMonitor_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	//Suspend for the action we desire
	//Once it has ended, we will return here and suspend for another one
	if (g_bIsDefenderBot[actor])
		return GetDesiredBotAction(actor, action);
		
	return Plugin_Continue;
}

public Action CTFBotScenarioMonitor_InitialContainedAction(BehaviorAction action, int actor, BehaviorAction& child)
{
	if (g_bIsDefenderBot[actor] && TF2_GetPlayerClass(actor) == TFClass_Spy)
	{
		//Force CTFBotSpyInfiltrate
		GameRules_SetProp("m_bPlayingMannVsMachine", false);
	}
	
	return Plugin_Continue;
}

public Action CTFBotScenarioMonitor_InitialContainedActionPost(BehaviorAction action, int actor, BehaviorAction& child)
{
	if (g_bIsDefenderBot[actor] && TF2_GetPlayerClass(actor) == TFClass_Spy)
	{
		//We still play mvm
		GameRules_SetProp("m_bPlayingMannVsMachine", true);
	}
	
	return Plugin_Continue;
}

public Action CTFBotMedicHeal_UpdatePost(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor])
	{
		//In mvm mode, medic bots will go for the flag when there's no patient available
		//Let's be smarter about it instead
		if (result.type == CHANGE_TO)
		{
			BehaviorAction resultingAction = result.action;
			char name[ACTION_NAME_LENGTH]; resultingAction.GetName(name);
			
			if (StrEqual(name, "FetchFlag"))
				return action.Continue(); //TODO: SuspendFor our custom action
		}
		
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
	}
	
	return Plugin_Continue;
}

public Action CTFBotFetchFlag_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (g_bIsDefenderBot[actor])
		return action.Done();
	
	return Plugin_Continue;
}

public Action CTFBotMvMEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (g_bIsDefenderBot[actor])
		return action.Done();
	
	return Plugin_Continue;
}

public Action CTFBotSniperLurk_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor])
	{
		if (TF2_IsPlayerInCondition(actor, TFCond_Zoomed))
		{
			INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
			CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
			
			if (threat != NULL_KNOWN_ENTITY && threat.IsVisibleInFOVNow())
			{
				int threatEnt = threat.GetEntity();
				
				if (BaseEntity_IsPlayer(threatEnt))
				{
					//Help aim towards the desired target point
					float aimPos[3]; myBot.GetIntentionInterface().SelectTargetPoint(threatEnt, aimPos);
					SnapViewToPosition(actor, aimPos);
					
					if (m_flNextSnipeFireTime[actor] <= GetGameTime())
						VS_PressFireButton(actor);
				}
			}
		}
		else
		{
			//Delay before we fire again
			m_flNextSnipeFireTime[actor] = GetGameTime() + 1.0;
		}
	}
	
	return Plugin_Continue;
}

public Action CTFBotSniperLurk_SelectMoreDangerousThreat(BehaviorAction action, Address nextbot, int entity, Address threat1, Address threat2, Address& knownEntity)
{
	//Return NULL so the normal threat targetting happens
	knownEntity = Address_Null;
	
	return Plugin_Changed;
}

public Action CTFBotSpyAttack_SelectMoreDangerousThreat(BehaviorAction action, Address nextbot, int entity, Address threat1, Address threat2, Address& knownEntity)
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
}

BehaviorAction CTFBotDefenderAttack()
{
	BehaviorAction action = ActionsManager.Create("DefenderAttack");
	
	action.OnStart = CTFBotDefenderAttack_OnStart;
	action.Update = CTFBotDefenderAttack_Update;
	action.OnEnd = CTFBotDefenderAttack_OnEnd;
	action.SelectMoreDangerousThreat = CTFBotDefenderAttack_SelectMoreDangerousThreat;
	
	return action;
}

public Action CTFBotDefenderAttack_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	m_iAttackTarget[actor] = SelectRandomReachableEnemy(actor);
	
	if (m_iAttackTarget[actor] == -1)
		return action.Done("Invalid attack target");
	
	// g_flRevalidateTarget[actor] = GetGameTime() + 3.0;
	
	UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

public Action CTFBotDefenderAttack_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidClientIndex(m_iAttackTarget[actor])
	|| !IsPlayerAlive(m_iAttackTarget[actor])
	|| TF2_GetClientTeam(m_iAttackTarget[actor]) != GetEnemyTeamOfPlayer(actor)
	|| !IsPathToEntityPossible(actor, m_iAttackTarget[actor]))
	{
		return action.Done("Target is not valid");
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
			if (CTFBotAttackTank_IsPossible(actor))
				return action.ChangeTo(CTFBotAttackTank(), "Changing threat to tank");
		}
	}
	
	if (ShouldCampBomb(actor))
		return action.ChangeTo(CTFBotCampBomb(), "Camp bomb");
	
	//TODO: Other classes should go for money, but only when there isn't a threat around
	
	int closesttoh = FindBotNearestToBombNearestToHatch(actor);
	
	if (closesttoh > 0)
		m_iAttackTarget[actor] = closesttoh;
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	float threatOrigin[3]; GetClientAbsOrigin(m_iAttackTarget[actor], threatOrigin);
	float myEyePos[3]; GetClientEyePosition(actor, myEyePos);
	IVision myVision = myBot.GetVisionInterface();
	
	CKnownEntity threat = myVision.GetPrimaryKnownThreat(false);
	
	if (threat)
	{
		//We have a threat, prepare to fight it
		EquipBestWeaponForThreat(actor, threat);
	}
	
	//Path if out of range or cannot see target
	if (myBot.IsRangeGreaterThanEx(threatOrigin, GetDesiredAttackRange(actor)) || !TF2_IsLineOfFireClear(actor, myEyePos, threatOrigin))
	{
		m_pPath[actor].Update(myBot);
		
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.5, 1.0);
			m_pPath[actor].ComputeToTarget(myBot, m_iAttackTarget[actor]);
		}
	}
	
	return action.Continue();
}

public void CTFBotDefenderAttack_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iAttackTarget[actor] = -1;
}

public Action CTFBotDefenderAttack_SelectMoreDangerousThreat(BehaviorAction action, Address nextbot, int entity, Address threat1, Address threat2, Address& knownEntity)
{
	int me = action.Actor;
	
	CKnownEntity knownThreat1 = view_as<CKnownEntity>(threat1);
	int iThreat1 = knownThreat1.GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat1) && iThreat1 == m_iAttackTarget[me] && knownThreat1.IsVisibleInFOVNow())
	{
		//Our own current chase target is a high priority, unless they're being healed by a medic
		knownEntity = view_as<Address>(GetHealerOfThreat(view_as<INextBot>(nextbot), view_as<CKnownEntity>(threat1)));
		
		return Plugin_Changed;
	}
	
	CKnownEntity knownThreat2 = view_as<CKnownEntity>(threat2);
	int iThreat2 = knownThreat2.GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat2) && iThreat2 == m_iAttackTarget[me] && knownThreat2.IsVisibleInFOVNow())
	{
		knownEntity = view_as<Address>(GetHealerOfThreat(view_as<INextBot>(nextbot), view_as<CKnownEntity>(threat2)));
		
		return Plugin_Changed;
	}
	
	//Use standard threat selection
	knownEntity = Address_Null;
	
	return Plugin_Changed;
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
	m_pPath[actor].Update(myBot);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToTarget(myBot, m_iTarget[actor]);
	}
	
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
	
	m_pPath[actor].Update(myBot);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iCurrencyPack[actor]));
	}
	
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
	
	m_pPath[actor].Update(myBot);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, center);
	}
	
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
	
	// UpdateLookAroundForEnemies(actor, false);
	
	//Due to CTFBot::AvoidPlayers, other players can push us
	SetEntityMoveType(actor, MOVETYPE_NONE);
	
	return action.Continue();
}

public Action CTFBotUpgrade_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!TF2_IsInUpgradeZone(actor)) 
		return action.ChangeTo(CTFBotGotoUpgrade(), "Not standing at an upgrade station!");
	
	float flNextTime = m_flNextUpgrade[actor] - GetGameTime();
	
	if (flNextTime <= 0.0)
	{
		m_flNextUpgrade[actor] = GetGameTime() + GetUpgradeInterval();
		
		JSONObject info = CTFBotPurchaseUpgrades_ChooseUpgrade(actor);
		
		if (info != null) 
		{
			CTFBotPurchaseUpgrades_PurchaseUpgrade(actor, info);
		}
		else 
		{
			// g_flNextUpdate[actor] = 0.0;
			
			FakeClientCommand(actor, "tournament_player_readystate 1");
			
			delete info;
			
			if (TF2_GetPlayerClass(actor) == TFClass_Engineer)
				return action.ChangeTo(CTFBotEngineerIdle(), "Start building");
			else if (TF2_GetPlayerClass(actor) == TFClass_Medic)
				return action.Done("Start heal mission");
			else if (TF2_GetPlayerClass(actor) == TFClass_Spy)
				return action.Done("Start spy lurking");
			else if (HasSniperRifle(actor))
				return action.Done("Start lurking");
			else
				return action.ChangeTo(CTFBotMoveToFront(), "Finished upgrading; Move to front and press F4");
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
	KV_MvM_UpgradesDone(actor);
	
	TF2_DetonateObjectsOfType(actor, TFObject_Sentry);
	TF2_DetonateObjectsOfType(actor, TFObject_Dispenser);
	
	// UpdateLookAroundForEnemies(actor, true);
	
	SetEntityMoveType(actor, MOVETYPE_WALK);
	
	Command_BoughtUpgrades(actor, 0); //Remember this bot's upgrades
}

BehaviorAction CTFBotGetAmmo()
{
	BehaviorAction action = ActionsManager.Create("DefenderGetAmmo");
	
	action.OnStart = CTFBotGetAmmo_OnStart;
	action.Update = CTFBotGetAmmo_Update;
	action.OnEnd = CTFBotGetAmmo_OnEnd;
	action.ShouldHurry = CTFBotGetAmmo_ShouldHurry;
	
	return action;
}

public Action CTFBotGetAmmo_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	//Disable constant pathing cause we don't need it here
	//Will cause conflcting pathing issues otherwise
	pb_bPath[actor] = false;
	
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
		// UpdateLookAroundForEnemies(actor, true);
		return action.Continue();
	}
	
	// UpdateLookAroundForEnemies(actor, true);
	return action.Done("Could not find ammo");
}

public Action CTFBotGetAmmo_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidAmmo(m_iAmmoPack[actor]))
		return action.Done("ammo is not valid");
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	m_pPath[actor].Update(myBot);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iAmmoPack[actor]));
	}
	
	CKnownEntity threat = myBot.GetVisionInterface().GetPrimaryKnownThreat(false);
	
	if (threat)
		EquipBestWeaponForThreat(actor, threat);
	
	return action.Continue();
}

public Action CTFBotGetAmmo_ShouldHurry(BehaviorAction action, Address nextbot, QueryResultType& result)
{
	if (redbots_manager_debug_actions.BoolValue)
		PrintToChatAll("CTFBotGetAmmo HURRY");
	
	//This disables dodging, but more importantly stops us from revving the minigun
	result = ANSWER_YES;
	return Plugin_Handled;
}

public void CTFBotGetAmmo_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iAmmoPack[actor] = -1;
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
	
	m_pPath[actor].Update(myBot);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(3.0, 4.0);
		m_pPath[actor].ComputeToPos(myBot, m_vecGoalArea[actor]);
	}
	
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
	
	return action;
}

public Action CTFBotGetHealth_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	pb_bPath[actor] = false;
	
	float health_ratio = view_as<float>(GetClientHealth(actor)) / view_as<float>(BaseEntity_GetMaxHealth(actor));
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
		return action.Continue();
	
	return action.Done("Could not find health");
}

public Action CTFBotGetHealth_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidHealth(m_iHealthPack[actor]))
		return action.Done("Health is not valid");
	
	//Drop our building or we cant defend ourselves
	if (TF2_IsCarryingObject(actor))
	{
		VS_PressFireButton(actor);
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	m_pPath[actor].Update(myBot);
	
	if (m_flRepathTime[actor] <= GetGameTime())
	{
		m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
		m_pPath[actor].ComputeToPos(myBot, WorldSpaceCenter(m_iHealthPack[actor]));
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

public Action CTFBotGetHealth_ShouldHurry(BehaviorAction action, Address nextbot, QueryResultType& result)
{
	result = ANSWER_YES;
	return Plugin_Changed;
}

BehaviorAction CTFBotEngineerIdle()
{
	BehaviorAction action = ActionsManager.Create("DefenderEngineerIdle");
	
	action.OnStart = CTFBotEngineerIdle_OnStart;
	action.Update = CTFBotEngineerIdle_Update;
	action.OnEnd = CTFBotEngineerIdle_OnEnd;
	
	return action;
}

public Action CTFBotEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	CTFBotEngineerIdleResetVars(actor);
	
	return action.Continue();
}

public Action CTFBotEngineerIdle_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	int sentry    = TF2_GetObject(actor, TFObject_Sentry);
	int dispenser = TF2_GetObject(actor, TFObject_Dispenser);
	
	bool bShouldAdvance = CTFBotEngineerIdle_ShouldAdvanceNestSpot(actor);
	
	if (bShouldAdvance && !g_bGoingToGrabBuilding[actor])
	{
		//TF2_DetonateObjectsOfType(actor, TFObject_Sentry);
		//TF2_DetonateObjectsOfType(actor, TFObject_Dispenser);
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToServer("ADVANCE");
		
		CTFBotEngineerIdleResetVars(actor);
		
		m_aNestArea[actor] = PickBuildArea(actor);
		
		if (sentry != INVALID_ENT_REFERENCE && m_aNestArea[actor] != NULL_AREA)
		{
			g_bGoingToGrabBuilding[actor] = true;
			
			m_iBuildingToGrab[actor] = EntIndexToEntRef(sentry);
			
			SetGoalEntity(actor, sentry);
		}
	}
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	ILocomotion myLoco = myBot.GetLocomotionInterface();
	
	if (g_bGoingToGrabBuilding[actor])
	{
		int building = EntRefToEntIndex(m_iBuildingToGrab[actor]);
		
		if (building == INVALID_ENT_REFERENCE)
		{
			g_bGoingToGrabBuilding[actor] = false;
			m_iBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
			
			if (redbots_manager_debug_actions.BoolValue)
				PrintToServer("g_bGoingToGrabBuilding : building %i | m_aNestArea %x", building, m_aNestArea[actor]);
			
			TF2_DetonateObjectsOfType(actor, TFObject_Sentry);
			TF2_DetonateObjectsOfType(actor, TFObject_Dispenser);
			
			pb_bPath[actor] = false;
			
			return action.Continue();
		}
		
		UpdateLookAroundForEnemies(actor, false);
		
		if (!TF2_IsCarryingObject(actor))
		{
			float flDistanceToBuilding = GetVectorDistance(GetAbsOrigin(actor), GetAbsOrigin(building));
			
			if (flDistanceToBuilding < 90.0)
			{
				EquipWeaponSlot(actor, TFWeaponSlot_Melee);
				
				//TODO: replace both of these with IBody AimHeadTowards, whenever it gets exposed that is
				//Do it for all usage of FaceTowards
				// myLoco.FaceTowards(WorldSpaceCenter(building));
				SnapViewToPosition(actor, WorldSpaceCenter(building));
				
				VS_PressAltFireButton(actor);
				
				//PrintToServer("Grab");
			}
		}
		else
		{
			if (m_aNestArea[actor] != NULL_AREA)
			{
				float center[3]; m_aNestArea[actor].GetCenter(center);
				SetGoalVector(actor, center);
				
				float flDistanceToGoal = GetVectorDistance(GetAbsOrigin(actor), center);
				
				if (flDistanceToGoal < 200.0)
				{	
					//Crouch when closer than 200 hu
					if (!myLoco.IsStuck())
					{
						g_iAdditionalButtons[actor] |= IN_DUCK;
					}
					
					if (flDistanceToGoal < 70.0)
					{
						//Try placing building when closer than 70 hu
						int objBeingBuilt = TF2_GetCarriedObject(actor);
						
						if (!IsValidEntity(objBeingBuilt))
							return action.Continue();
						
						bool m_bPlacementOK = !!GetEntData(objBeingBuilt, FindSendPropInfo("CObjectSentrygun", "m_iKills") - 4);
						
						VS_PressFireButton(actor);
						
						IBody myBody = myBot.GetBodyInterface();
						
						if (!m_bPlacementOK && myBody.IsHeadAimingOnTarget() && myBody.GetHeadSteadyDuration() > 0.6 )
						{
							//That spot was no good.
							//Time to pick a new spot.
							m_aNestArea[actor] = PickBuildArea(actor);
						}
						else
						{
							g_bGoingToGrabBuilding[actor] = false;
							m_iBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
							
							pb_bPath[actor] = false;
						}
					}
				}
				
				//PrintToServer("Travel");
			}
		}
		
		pb_bPath[actor] = true;
		
		return action.Continue();
	}
	
	if ((m_aNestArea[actor] == NULL_AREA || bShouldAdvance) || sentry == INVALID_ENT_REFERENCE)
	{
		//HasStarted && !IsElapsed
		if (m_ctFindNestHint[actor] > 0.0 && m_ctFindNestHint[actor] > GetGameTime()) 
			return action.Continue();
		
		//Start
		m_ctFindNestHint[actor] = GetGameTime() + (GetRandomFloat(1.0, 2.0));
		
		m_aNestArea[actor] = PickBuildArea(actor);
		
		if (redbots_manager_debug_actions.BoolValue)
			PrintToServer("DEBUG: SEARCHING AREA: 0x%X", m_aNestArea[actor]);
	}
	
	if (bShouldAdvance)
		return action.Continue();
	
	if (m_aNestArea[actor] != NULL_AREA)
	{
		if (sentry != INVALID_ENT_REFERENCE)
		{
			if (GetEntProp(sentry, Prop_Send, "m_iHealth") >= GetEntProp(sentry, Prop_Send, "m_iMaxHealth") 
			&& !TF2_IsBuilding(sentry)
			&& TF2_GetUpgradeLevel(sentry) >= 3
			&& GetEntProp(sentry, Prop_Send, "m_iAmmoShells") > 0)
			{
				m_ctSentrySafe[actor] = GetGameTime() + 3.0;
			}
			
			m_ctSentryCooldown[actor] = GetGameTime() + 3.0;	
		}
		else 
		{
			/* do not have a sentry; retreat for a few seconds if we had a
			 * sentry before this; then build a new sentry */
			if (m_ctSentryCooldown[actor] < GetGameTime()) 
			{
				m_ctSentryCooldown[actor] = GetGameTime() + 3.0;
				
				return action.SuspendFor(CTFBotBuildSentrygun(), "No sentry - building a new one");
			}
		}
		
		//Don't build a dispenser if we don't have a sentry...
		if (sentry != INVALID_ENT_REFERENCE)
		{
			if (dispenser != INVALID_ENT_REFERENCE)
			{
				//sentry is not safe.
				if(m_ctSentrySafe[actor] < GetGameTime())
				{
					m_ctDispenserCooldown[actor] = GetGameTime() + 3.0;
				}
				
				//m_ctDispenserCooldown[actor] = GetGameTime() + 3.0;	
			}
			else 
			{
				/* do not have a dispenser; retreat for a few seconds if we had a
				 * dispenser before this; then build a new dispenser */
				if (m_ctDispenserCooldown[actor] < GetGameTime() && m_ctSentrySafe[actor] > GetGameTime())
				{
					m_ctDispenserCooldown[actor] = GetGameTime() + 3.0;
					
					return action.SuspendFor(CTFBotBuildDispenser(), "Sentry safe, No dispenser - building one");
				}
			}
		}
	}
	
	if (dispenser != INVALID_ENT_REFERENCE && m_ctSentrySafe[actor] > GetGameTime())
	{
		if (TF2_GetUpgradeLevel(dispenser) < 3 || GetEntProp(dispenser, Prop_Send, "m_iHealth") < GetEntProp(dispenser, Prop_Send, "m_iMaxHealth"))
		{
			float dist = GetVectorDistance(GetAbsOrigin(actor), GetAbsOrigin(dispenser));
			
			if (m_ctRecomputePathMvMEngiIdle[actor] < GetGameTime()) 
			{
				m_ctRecomputePathMvMEngiIdle[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
				
				float dir[3];
				SubtractVectors(GetAbsAngles(dispenser), GetAbsOrigin(actor), dir);
				NormalizeVector(dir, dir);
				
				float goal[3]; goal = GetAbsOrigin(dispenser);
				goal[0] -= (50.0 * dir[0]);
				goal[1] -= (50.0 * dir[1]);
				goal[2] -= (50.0 * dir[2]);
				
				if (IsPathToVectorPossible(actor, goal, _))
				{
					SetGoalVector(actor, goal);
				}
				else
				{
					SetGoalEntity(actor, sentry);
				}
				
				pb_bPath[actor] = true;
			}
			
			if (dist < 90.0) 
			{
				if (!myLoco.IsStuck())
				{
					g_iAdditionalButtons[actor] |= IN_DUCK;
				}
				
				EquipWeaponSlot(actor, TFWeaponSlot_Melee);
				
				UpdateLookAroundForEnemies(actor, false);
				
				// myLoco.FaceTowards(WorldSpaceCenter(dispenser));
				SnapViewToPosition(actor, WorldSpaceCenter(dispenser));
				VS_PressFireButton(actor);				
			}
			
			return action.Continue();
		}
	}
	
	if (sentry != INVALID_ENT_REFERENCE) 
	{
		float dist = GetVectorDistance(GetAbsOrigin(actor), GetAbsOrigin(sentry));
		
		if (m_ctRecomputePathMvMEngiIdle[actor] < GetGameTime()) 
		{
			m_ctRecomputePathMvMEngiIdle[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			
			float dir[3];
			GetAngleVectors(GetTurretAngles(sentry), dir, NULL_VECTOR, NULL_VECTOR);
			
			float goal[3]; goal = GetAbsOrigin(sentry);
			goal[0] -= (50.0 * dir[0]);
			goal[1] -= (50.0 * dir[1]);
			goal[2] -= (50.0 * dir[2]);
			
			if (IsPathToVectorPossible(actor, goal))
			{
				SetGoalVector(actor, goal);
			}
			else
			{
				SetGoalEntity(actor, sentry);
			}
			
			pb_bPath[actor] = true;
		}
		
		if (dist < 90.0) 
		{
			if (!myLoco.IsStuck())
			{
				g_iAdditionalButtons[actor] |= IN_DUCK;
			}
			
			EquipWeaponSlot(actor, TFWeaponSlot_Melee);
			
			UpdateLookAroundForEnemies(actor, false);
			
			// myLoco.FaceTowards(WorldSpaceCenter(sentry));
			SnapViewToPosition(actor, WorldSpaceCenter(sentry));
			VS_PressFireButton(actor);
		}
	}
	
	return action.Continue();
}

public void CTFBotEngineerIdle_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	pb_bPath[actor] = false;
	pb_vecPathGoal[actor] = NULL_VECTOR;
	pb_iPathGoalEntity[actor] = false;
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
	UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

public Action CTFBotBuildSentrygun_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_aNestArea[actor] == NULL_AREA) 
		return action.Done("No hint entity");
	
	if (CTFBotEngineerIdle_ShouldAdvanceNestSpot(actor))
	{
		//And you.
		
		return action.Done("No sentry");
	}
	
	float areaCenter[3]; m_aNestArea[actor].GetCenter(areaCenter);
	
	float range_to_hint = GetVectorDistance(GetAbsOrigin(actor), areaCenter);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	if (range_to_hint < 200.0) 
	{
		//Start building a sentry
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 2");
		
		UpdateLookAroundForEnemies(actor, false);
		
		ILocomotion myLoco = myBot.GetLocomotionInterface();
		
		if (!myLoco.IsStuck())
		{
			g_iAdditionalButtons[actor] |= IN_DUCK;
		}
		
		// myLoco.FaceTowards(areaCenter);
		SnapViewToPosition(actor, areaCenter);
	}
	
	if (range_to_hint > 70.0)
	{
		//PrintToServer("%f %f %f", areaCenter[0], areaCenter[1], areaCenter[2]);
	
		SetGoalVector(actor, areaCenter);
		pb_bPath[actor] = true;
	
		if (range_to_hint > 300.0)
		{
			//Fuck em up.
			EquipWeaponSlot(actor, TFWeaponSlot_Primary);
		}
	
		UpdateLookAroundForEnemies(actor, true);
		
		return action.Continue();
	}
	
	pb_bPath[actor] = false;
	
	if (IsWeapon(actor, TF_WEAPON_BUILDER))
	{
		int objBeingBuilt = GetEntPropEnt(BaseCombatCharacter_GetActiveWeapon(actor), Prop_Send, "m_hObjectBeingBuilt");
		
		if (!IsValidEntity(objBeingBuilt))
			return action.Continue();
		
		bool m_bPlacementOK = !!GetEntData(objBeingBuilt, FindSendPropInfo("CObjectSentrygun", "m_iKills") - 4);
		
		VS_PressFireButton(actor);
		
		IBody myBody = myBot.GetBodyInterface();
		
		if (!m_bPlacementOK && myBody.IsHeadAimingOnTarget() && myBody.GetHeadSteadyDuration() > 0.6)
		{
			//That spot was no good.
			//Time to pick a new spot.
			m_aNestArea[actor] = PickBuildArea(actor);
			
			return action.Continue();
		}
	}
	
	int sentry = TF2_GetObject(actor, TFObject_Sentry);
	
	if (sentry == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	FakeClientCommandThrottled(actor, "tournament_player_readystate 1");
	return action.Done("Built a sentry");
}

public void CTFBotBuildSentrygun_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	pb_bPath[actor] = false;
	pb_vecPathGoal[actor] = NULL_VECTOR;
	pb_iPathGoalEntity[actor] = false;
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
	UpdateLookAroundForEnemies(actor, true);
	
	return action.Continue();
}

public Action CTFBotBuildDispenser_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (m_aNestArea[actor] == NULL_AREA) 
		return action.Done("No hint entity");
	
	if (TF2_GetObject(actor, TFObject_Sentry) == INVALID_ENT_REFERENCE)
	{
		//Fuck you.
		
		return action.Done("No sentry");
	}
	else
	{
		//sentry is not safe.
		if (m_ctSentrySafe[actor] < GetGameTime())
			return action.Done("Sentry not safe");
	}
	
	if (CTFBotEngineerIdle_ShouldAdvanceNestSpot(actor))
	{
		//Fuck you too.
		
		return action.Done("Need to advance nest");
	}
	
	float areaCenter[3]; CNavArea_GetRandomPoint(m_aNestArea[actor], areaCenter);
	
	float range_to_hint = GetVectorDistance(GetAbsOrigin(actor), areaCenter);
	
	if (range_to_hint < 200.0) 
	{
		//Start building a dispenser
		if (!IsWeapon(actor, TF_WEAPON_BUILDER))
			FakeClientCommandThrottled(actor, "build 0");
		
		//Look in "random" directions in an attempt to find a place to fit a dispenser.
		UpdateLookAroundForEnemies(actor, true);
		
	//	if(g_flNextLookTime[actor] > GetGameTime())
	//		return false;
		
	//	g_flNextLookTime[actor] = GetGameTime() + GetRandomFloat(0.3, 1.0);
		
		// UpdateLookingAroundForIncomingPlayers(actor, false);
		
		//BotAim(actor).AimHeadTowards(areaCenter, OVERRIDE_ALL, 0.1, "Placing sentry");
	}
	
	if (range_to_hint > 70.0)
	{
		//PrintToServer("%f %f %f", areaCenter[0], areaCenter[1], areaCenter[2]);
	
		SetGoalVector(actor, areaCenter);
		pb_bPath[actor] = true;
	
		//if(range_to_hint > 300.0)
		//{
			//Fuck em up.
			//EquipWeaponSlot(actor, TFWeaponSlot_Melee);
		//}
		
		return action.Continue();
	}
	
	pb_bPath[actor] = false;
	
	VS_PressFireButton(actor);
	
	int sentry = TF2_GetObject(actor, TFObject_Dispenser);
	
	if (sentry == INVALID_ENT_REFERENCE)
		return action.Continue();
	
	//DispatchKeyValueVector(sentry, "origin", areaCenter);
	//DispatchKeyValueVector(sentry, "angles", GetAbsAngles(EntRefToEntIndex(m_hintEntity[actor])));
	
	FakeClientCommandThrottled(actor, "tournament_player_readystate 1");
	return action.Done("Built a dispenser");
}

public void CTFBotBuildDispenser_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	UpdateLookAroundForEnemies(actor, true);
	
	pb_bPath[actor] = false;
	pb_vecPathGoal[actor] = NULL_VECTOR;
	pb_iPathGoalEntity[actor] = false;
}

BehaviorAction CTFBotAttackTank()
{
	BehaviorAction action = ActionsManager.Create("DefenderAttackTank");
	
	action.OnStart = CTFBotAttackTank_OnStart;
	action.Update = CTFBotAttackTank_Update;
	action.OnEnd = CTFBotAttackTank_OnEnd;
	action.SelectMoreDangerousThreat = CTFBotAttackTank_SelectMoreDangerousThreat;
	
	return action;
}

public Action CTFBotAttackTank_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	if ((m_iAttackTarget[actor] = GetTankToTarget(actor)) < 1)
		return action.Done("Tank is no longer valid.");
	
	return action.Continue();
}

public Action CTFBotAttackTank_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (!IsValidEntity(m_iAttackTarget[actor]))
		return action.Done("Tank is no longer valid.");
	
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
			if (CTFBotDefenderAttack_IsPossible(actor))
				return action.ChangeTo(CTFBotDefenderAttack(), "Robot priority");
		}
	}
	
	EquipBestTankWeapon(actor);
	
	float myEyePos[3]; GetClientEyePosition(actor, myEyePos);
	float targetOrigin[3]; targetOrigin = WorldSpaceCenter(m_iAttackTarget[actor]);
	float dist_to_tank = GetVectorDistance(myEyePos, targetOrigin);
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
	
	//Always be aware of our target
	myBot.GetVisionInterface().AddKnownEntity(m_iAttackTarget[actor]);
	
	bool canSeeTarget = TF2_IsLineOfFireClear3(actor, myEyePos, m_iAttackTarget[actor]);
	float attackRange = GetIdealTankAttackRange(actor);
	
	if (!canSeeTarget || dist_to_tank > attackRange)
	{
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(0.4, 1.0);
			m_pPath[actor].ComputeToPos(myBot, GetAbsOrigin(m_iAttackTarget[actor]), 0.0, true);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	return action.Continue();
}

public void CTFBotAttackTank_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iAttackTarget[actor] = -1;
}

public Action CTFBotAttackTank_SelectMoreDangerousThreat(BehaviorAction action, Address nextbot, int entity, Address threat1, Address threat2, Address& knownEntity)
{
	int me = action.Actor;
	
	int iThreat1 = view_as<CKnownEntity>(threat1).GetEntity();
	int iThreat2 = view_as<CKnownEntity>(threat2).GetEntity();
	float myOrigin[3]; GetClientAbsOrigin(me, myOrigin);
	float threatOrigin[3];
	const float notSafeRange = 200.0;
	
	if (BaseEntity_IsPlayer(iThreat1))
	{
		GetClientAbsOrigin(iThreat1, threatOrigin);
		
		if (GetVectorDistance(myOrigin, threatOrigin) <= notSafeRange)
		{
			//This threat is too close, prioritize it!
			knownEntity = threat1;
			return Plugin_Changed;
		}
	}
	
	if (BaseEntity_IsPlayer(iThreat2))
	{
		GetClientAbsOrigin(iThreat2, threatOrigin);
		
		if (GetVectorDistance(myOrigin, threatOrigin) <= notSafeRange)
		{
			knownEntity = threat2;
			return Plugin_Changed;
		}
	}
	
	//Our most dangerous threat should be the tank
	if (iThreat1 == m_iAttackTarget[me] && TF2_IsLineOfFireClear4(me, iThreat1))
	{
		knownEntity = threat1;
		return Plugin_Changed;
	}
	
	if (iThreat2 == m_iAttackTarget[me] && TF2_IsLineOfFireClear4(me, iThreat2))
	{
		knownEntity = threat2;
		return Plugin_Changed;
	}
	
	//We probably can't see it right now
	knownEntity = Address_Null;
	
	return Plugin_Changed;
}

BehaviorAction CTFBotSpyLurkMvM()
{
	BehaviorAction action = ActionsManager.Create("DefenderSpyLurk");
	
	action.OnStart = CTFBotSpyLurkMvM_OnStart;
	action.Update = CTFBotSpyLurkMvM_Update;
	action.OnEnd = CTFBotSpyLurkMvM_OnEnd;
	
	return action;
}

public Action CTFBotSpyLurkMvM_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	/* if (!TF2_IsStealthed(actor))
		VS_PressAltFireButton(actor); */
	
	return action.Continue();
}

public Action CTFBotSpyLurkMvM_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	//TODO: make a good spy ai
	
	return action.Continue();
}

public void CTFBotSpyLurkMvM_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_iAttackTarget[actor] = -1;
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
	
	return action.Continue();
}

public Action CTFBotCampBomb_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	int bomb = FindBombNearestToHatch();
	
	if (bomb == -1)
		return action.Done("No bomb");
	
	if (BaseEntity_GetOwnerEntity(bomb) != -1)
	{
		//Someone picked up the bomb!
		return action.ChangeTo(CTFBotDefenderAttack(), "Bomb is taken");
	}
	
	float myOrigin[3]; GetClientAbsOrigin(actor, myOrigin);
	float bombPosition[3]; bombPosition = WorldSpaceCenter(bomb);
	
	//Move towards the bomb's current area if we're too far or can't see it
	if (GetVectorDistance(myOrigin, bombPosition) > 500.0 || !TF2_IsLineOfFireClear2(actor, bombPosition))
	{
		INextBot myBot = CBaseNPC_GetNextBotOfEntity(actor);
		
		if (m_flRepathTime[actor] <= GetGameTime())
		{
			m_flRepathTime[actor] = GetGameTime() + GetRandomFloat(1.0, 2.0);
			m_pPath[actor].ComputeToPos(myBot, bombPosition);
		}
		
		m_pPath[actor].Update(myBot);
	}
	
	return action.Continue();
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
		if (redbots_manager_bot_use_upgrades.BoolValue && redbots_manager_mode.IntValue == MANAGER_MODE_AUTO_BOTS && g_bHasBoughtUpgrades[client] == false && !TF2_IsInUpgradeZone(client))
		{
			//Bots are added during the round, so we must upgrade now if haven't before
			return action.SuspendFor(CTFBotGotoUpgrade(), "Buy upgrades now");
		}
		
		//Health and ammo is moved to CTFBotTacticalMonitor_Update as it takes precedence over ScenarioMonitor
		
		switch(TF2_GetPlayerClass(client))
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
				else if (CTFBotAttackTank_IsPossible(client))
					return action.SuspendFor(CTFBotAttackTank(), "Scout: Attacking tank");
				else if (CTFBotDefenderAttack_IsPossible(client))
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
					return action.SuspendFor(CTFBotDefenderAttack(), "Sniper: Attacking robots");
				}
			}
			case TFClass_Engineer:
			{
				return action.SuspendFor(CTFBotEngineerIdle(), "Engineer: Start building");
			}
			case TFClass_Spy:
			{
				//InitialContainedAction is overriden to assign CTFBotSpyInfiltrate
				return Plugin_Continue;
			}
			case TFClass_Heavy:
			{
				if (CTFBotDefenderAttack_IsPossible(client))
					return action.SuspendFor(CTFBotDefenderAttack(), "CTFBotAttack_IsPossible");
				else if (CTFBotAttackTank_IsPossible(client))
					return action.SuspendFor(CTFBotAttackTank(), "Attacking tank");
				else if (CTFBotCollectMoney_IsPossible(client))
					return action.SuspendFor(CTFBotCollectMoney(), "CTFBotCollectMoney_IsPossible");
			}
			case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
			{
				if (CTFBotAttackTank_IsPossible(client))
					return action.SuspendFor(CTFBotAttackTank(), "Attacking tank");
				else if (CTFBotDefenderAttack_IsPossible(client))
					return action.SuspendFor(CTFBotDefenderAttack(), "CTFBotAttack_IsPossible");
				else if (CTFBotCollectMoney_IsPossible(client))
					return action.SuspendFor(CTFBotCollectMoney(), "CTFBotCollectMoney_IsPossible");
			}
		}
	}
	
	return Plugin_Continue;
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

bool CTFBotDefenderAttack_IsPossible(int actor)
{
	return SelectRandomReachableEnemy(actor) != -1;
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
	
	bool bDemoKnight = (!IsCombatWeapon(GetPlayerWeaponSlot(client, TFWeaponSlot_Primary)));
	bool bEngineer = (TF2_GetPlayerClass(client) == TFClass_Engineer);
	
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
			iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
			iArraySlots.Push(TF_LOADOUT_SLOT_MELEE);
		}

		//Demoknight doesn't buy primary weapon upgrades.
		iArraySlots.Push(bDemoKnight ? TF_LOADOUT_SLOT_MELEE : TF_LOADOUT_SLOT_PRIMARY);
	
		if (TF2_IsShieldEquipped(client))
		{
			iArraySlots.Push(TF_LOADOUT_SLOT_SECONDARY);
		}
	}

	for (int i = 0; i < iArraySlots.Length; i++)
	{
		int slot = iArraySlots.Get(i);
	
		for (int index = 0; index < MAX_UPGRADES; index++)
		{
			CMannVsMachineUpgrades upgrades = CMannVsMachineUpgradeManager().GetUpgradeByIndex(index);
			
			if (upgrades.m_iUIGroup() == 1 && slot != -1) 
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
	
	if (redbots_manager_mode.IntValue == MANAGER_MODE_AUTO_BOTS)
	{
		//Since we're joining in the middle of a round, we want to upgrade fast
		return GetRandomFloat(0.3, 0.75);
	}
	
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
		
		char attrib[128]; attrib = upgrades.m_szAttribute();
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
	kv.SetNum("upgrade",  index);
	kv.SetNum("count",    count);
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
	
	return true;
}

bool CTFBotEngineerIdle_ShouldAdvanceNestSpot(int actor)
{
	if (m_aNestArea[actor] == NULL_AREA)
		return false;
	
	if (m_ctAdvanceNestSpot[actor] <= 0.0)
	{
		m_ctAdvanceNestSpot[actor] = GetGameTime() + 5.0;
		return false;
	}
	
	int obj = TF2_GetObject(actor, TFObject_Sentry);
	if (obj != INVALID_ENT_REFERENCE && GetEntProp(obj, Prop_Send, "m_iHealth") < GetEntProp(obj, Prop_Send, "m_iMaxHealth"))
	{
		m_ctAdvanceNestSpot[actor] = GetGameTime() + 5.0;
		return false;
	}
	
	//IsElapsed
	if (GetGameTime() > m_ctAdvanceNestSpot[actor])
	{
		m_ctAdvanceNestSpot[actor] = -1.0;
	}
	
	JSONObject bombinfo = new JSONObject();
	if (!GetBombInfo(bombinfo)) 
	{
		delete bombinfo;
		return false;
	}
	
	float m_flBombTargetDistance = GetBombTargetDistance(m_aNestArea[actor]);
	
	//No point in advancing now.
	if (m_flBombTargetDistance <= 1000.0)
	{
		delete bombinfo;
		return false;
	}
	
	bool bigger = (m_flBombTargetDistance > bombinfo.GetFloat("hatch_dist_back"));
	
	//PrintToServer("m_flBombTargetDistance %f > bombinfo.hatch_dist_back %f = %s", m_flBombTargetDistance, bombinfo.GetFloat("hatch_dist_back"), bigger ? "Yes" : "No");

	delete bombinfo;
	return bigger;
}

bool GetBombInfo(JSONObject info)
{
	int iAreaCount = TheNavMesh.GetNavAreaCount();

	//Check that this map has any nav areas
	if (iAreaCount <= 0)
		return false;

	float hatch_dist = 0.0;
	
	for (int i = 0; i < (iAreaCount - 1); i++)
	{
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i)); //NOTE: does this work?
		
		//Skip spawn areas		
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
		{
			//PrintToServer("Skip spawn area.. #%i", area.GetID());
			continue;
		}
		
		float m_flBombTargetDistance = GetBombTargetDistance(area);
		
		hatch_dist = MaxFloat(MaxFloat(m_flBombTargetDistance, hatch_dist), 0.0);
	}
	
	int closest_flag = INVALID_ENT_REFERENCE;
	float closest_flag_pos[3];
	
	int flag = -1;
	while ((flag = FindEntityByClassname(flag, "item_teamflag")) != -1)
	{
		//Ignore bombs not in play
		if (GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 0)
			continue;
		
		//Ignore bombs not on our team
		//if (GetEntProp(flag, Prop_Send, "m_iTeamNum") != view_as<int>(TFTeam_Blue))
			//continue;
			
		float flag_pos[3];
		
		int owner = BaseEntity_GetOwnerEntity(flag);
		
		if (IsValidClientIndex(owner))
			flag_pos = GetAbsOrigin(owner);
		else
			flag_pos = WorldSpaceCenter(flag);
		
		CTFNavArea area = view_as<CTFNavArea>(TheNavMesh.GetNearestNavArea(flag_pos));
		
		if (area == NULL_AREA)
			continue;
			
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		float m_flBombTargetDistance = GetBombTargetDistance(area);
		
		if (m_flBombTargetDistance < hatch_dist) 
		{
			closest_flag = flag;
			hatch_dist = m_flBombTargetDistance;
			closest_flag_pos = flag_pos;
		}
	}
	
	//float range_back = FindConVar("tf_bot_engineer_mvm_sentry_hint_bomb_backward_range").FloatValue;
	//float range_fwd  = FindConVar("tf_bot_engineer_mvm_sentry_hint_bomb_forward_range").FloatValue;
	
	float range_fwd   = 2300.0;
	float range_back  = 1000.0;
	
	info.SetFloat("closest_pos_x", closest_flag_pos[0]);
	info.SetFloat("closest_pos_y", closest_flag_pos[1]);
	info.SetFloat("closest_pos_z", closest_flag_pos[2]);
	info.SetFloat("hatch_dist_back", hatch_dist + range_back);
	info.SetFloat("hatch_dist_fwd",  hatch_dist - range_fwd);
	
	return (closest_flag != INVALID_ENT_REFERENCE);
}

//TODO Gamedata me
const int g_iBombTargetDistance = 548;	//windows 0x224h | 0x228h linux

float GetBombTargetDistance(CNavArea area)
{
	float m_flBombTargetDistance = view_as<float>(LoadFromAddress(view_as<Address>(area) + view_as<Address>(g_iBombTargetDistance), NumberType_Int32));
	
	return m_flBombTargetDistance;
}

CNavArea PickBuildArea(int client, float SentryRange = 1300.0)
{
	int iAreaCount = TheNavMesh.GetNavAreaCount();

	//Check that this map has any nav areas
	if (iAreaCount <= 0)
		return NULL_AREA;
	
	JSONObject bombinfo = new JSONObject();
	
	if (!GetBombInfo(bombinfo)) 
	{	
		delete bombinfo;
		return PickBuildAreaPreRound(client);
	}
	
	float vecTargetPos[3];
	vecTargetPos[0] = bombinfo.GetFloat("closest_pos_x");
	vecTargetPos[1] = bombinfo.GetFloat("closest_pos_y");
	vecTargetPos[2] = bombinfo.GetFloat("closest_pos_z") + 40.0;
	
	CTFNavArea bombArea = view_as<CTFNavArea>(TheNavMesh.GetNearestNavArea(vecTargetPos, false, 90000.0, false, true, TEAM_ANY));
	
	if (bombArea == NULL_AREA)
		return NULL_AREA;
	
	if (bombArea.HasAttributeTF(BLUE_SPAWN_ROOM) || bombArea.HasAttributeTF(RED_SPAWN_ROOM))
		return NULL_AREA;

	//Areas forward of the bomb within some distance and visible to bomb.
	ArrayList ForwardVisibleAreas = new ArrayList();
	//Areas forward of the bomb but not necessarily visible.
	ArrayList ForwardAreas        = new ArrayList();
	//Areas visible to the bomb but not nescessarily forward of it.
	ArrayList VisibleAreasAround  = new ArrayList();
	
	//Loop all nav areas
	for (int i = 0; i < iAreaCount; i++)
	{	
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		if (area == NULL_AREA)
			continue;
		
		//Area in spawn
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(RED_SPAWN_ROOM))		
			continue;
		
		//TODO
		//Better solution because this will break on all non mvm maps.
		//Most likely areachable area
		if (!area.HasAttributeTF(BOMB_DROP))
			continue;
		
		float m_flBombTargetDistanceAtArea = GetBombTargetDistance(area);
		float m_flBombTargetDistanceAtBomb = GetBombTargetDistance(bombArea);
		
		if (m_flBombTargetDistanceAtArea < 180.0)
			continue;
		
		float areaCenter[3]; area.GetCenter(areaCenter);
		areaCenter[2] += 50.0;
		
		float flAreaDistanceToBomb = GetVectorDistance(areaCenter, vecTargetPos);
		
		if (flAreaDistanceToBomb >= SentryRange)
			continue;

		bool bAreaVisibleToBomb = CNavArea_IsVisible(area, vecTargetPos);
		
		if (bAreaVisibleToBomb)
			VisibleAreasAround.Push(area);
		
		if (m_flBombTargetDistanceAtBomb > m_flBombTargetDistanceAtArea)
		{
			if (flAreaDistanceToBomb <= SentryRange * GetRandomFloat(0.8, 1.75) && bAreaVisibleToBomb)
				ForwardVisibleAreas.Push(area);
			
			ForwardAreas.Push(area);
		}
	}
	
	if (redbots_manager_debug.BoolValue)
		PrintToServer("PickBuildArea %i ForwardVisibleAreas | %i ForwardAreas | %i VisibleAreasAroundBomb", ForwardVisibleAreas.Length, ForwardAreas.Length, VisibleAreasAround.Length);
	
	CNavArea randomArea = NULL_AREA;
	
	if (ForwardVisibleAreas.Length > 0)
		randomArea = ForwardVisibleAreas.Get(GetRandomInt(0, ForwardVisibleAreas.Length - 1));
	else if (ForwardAreas.Length > 0)
		randomArea = ForwardAreas.Get(GetRandomInt(0, ForwardAreas.Length - 1));
	else if (VisibleAreasAround.Length > 0)
		randomArea = VisibleAreasAround.Get(GetRandomInt(0, VisibleAreasAround.Length - 1));
	
	delete ForwardVisibleAreas;
	delete ForwardAreas;
	delete VisibleAreasAround;
	
	delete bombinfo;
	
	return randomArea;
}

CNavArea PickBuildAreaPreRound(int client, float SentryRange = 1300.0)
{
	int iAreaCount = TheNavMesh.GetNavAreaCount();
	
	//Check that this map has any nav areas
	if (iAreaCount <= 0)
		return NULL_AREA;
	
	ArrayList EnemySpawnExits = new ArrayList();	

	//Collect enemy exit areas after spawn door.
	for (int i = 0; i < iAreaCount; i++)
	{	
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		if (area == NULL_AREA)
			continue;
			
		//BLOCKED
		if (area.HasAttributeTF(BLOCKED))
			continue;
		
		//BLOCKED
		if (area.HasAttributeTF(BLOCKED_AFTER_POINT_CAPTURE))
			continue;
		
		//BLOCKED
		if (area.HasAttributeTF(BLOCKED_UNTIL_POINT_CAPTURE))
			continue;
		
		//Area in spawn but not an exit
		if (GetBombTargetDistance(area) <= 0.0 && !area.HasAttributeTF(SPAWN_ROOM_EXIT))
			continue;
		
		//Area not an enemy spawn room exit
		if (GetEnemyTeamOfPlayer(client) == TFTeam_Blue && !area.HasAttributeTF(BLUE_SPAWN_ROOM))
			continue;
		
		//Area not an enemy spawn room exit
		if (GetEnemyTeamOfPlayer(client) == TFTeam_Red && !area.HasAttributeTF(RED_SPAWN_ROOM))
			continue;
		
		float flLowestBombTargetDistance = 999999.0;
		CNavArea bestConnection = NULL_AREA;
		
		//Check spawn exit connections 
		for (NavDirType dir = NORTH; dir < NUM_DIRECTIONS; dir++)
		{
			//Only connections with BOMB_DROP attribute are considered good.
			for (int iConnection = 0; iConnection < area.GetAdjacentCount(dir); iConnection++)
			{			
				CTFNavArea adjArea = view_as<CTFNavArea>(area.GetAdjacentArea(dir, iConnection));
				
				//Area still in spawn... BAD
				if (area.HasAttributeTF(BLUE_SPAWN_ROOM) || area.HasAttributeTF(RED_SPAWN_ROOM))
					continue;
				
				float flBombTargetDistance = GetBombTargetDistance(adjArea);
				
				//Area most likely in spawn
				if (flBombTargetDistance <= 0.0)
					continue;
				
				if (flBombTargetDistance <= flLowestBombTargetDistance)
				{
					bestConnection = adjArea;
					flLowestBombTargetDistance = flBombTargetDistance;
				}
			}
		}
		
		if (bestConnection != NULL_AREA)
		{
			EnemySpawnExits.Push(bestConnection);
			//g_hAreasToDraw.Push(bestConnection);
		}
	}
	
	//We've failed men.
	if (EnemySpawnExits.Length <= 0)
	{
		delete EnemySpawnExits;
		return NULL_AREA;
	}
	
	//Random valid exit point.
	CNavArea RandomEnemySpawnExit = EnemySpawnExits.Get(GetRandomInt(0, EnemySpawnExits.Length - 1));

	//Search outward of the random exit untill we are some distance away.
	float vecExitCenter[3];
	RandomEnemySpawnExit.GetCenter(vecExitCenter);
	vecExitCenter[2] += 45.0;
	
	if (redbots_manager_debug.BoolValue)
		PrintToServer("%f %f %f", vecExitCenter[0], vecExitCenter[1], vecExitCenter[2]);
	
	ArrayList AreasCloser = new ArrayList();	//Not necessarily visible but still <= 3000.0
	ArrayList VisibleAreas = new ArrayList();
	ArrayList VisibleAreasAfterSentryRange = new ArrayList();	//>= SentryRange
	
	for (int i = 0; i < iAreaCount; i++)
	{	
		CTFNavArea area = view_as<CTFNavArea>(TheNavAreas.Get(i));
		
		if (area == NULL_AREA)
			continue;
		
		if (area.HasAttributeTF(BLUE_SPAWN_ROOM | RED_SPAWN_ROOM))
			continue;
			
		//TODO
		//Better solution because this will break on all non mvm maps.
		if (!area.HasAttributeTF(BOMB_DROP))
			continue;
			
		float center[3]; area.GetCenter(center);
		
		float flDistance = GetVectorDistance(center, vecExitCenter);
		
		if (flDistance <= SentryRange)
			AreasCloser.Push(area);
		
		if (!CNavArea_IsVisible(area, vecExitCenter))
			continue;
		
		if (flDistance > (SentryRange * 0.75) && flDistance <= SentryRange * 1.25)
		{
			VisibleAreasAfterSentryRange.Push(area);
			//g_hAreasToDraw.Push(area);
		}
		
		if (flDistance <= SentryRange)
			VisibleAreasAfterSentryRange.Push(area);	
		
		VisibleAreas.Push(area);
	}
	
	if (redbots_manager_debug.BoolValue)
		PrintToServer("PickBuildAreaPreRound %i VisibleAreas | %i VisibleAreasAfterSentryRange | %i AreasCloser", VisibleAreas.Length, VisibleAreasAfterSentryRange.Length, AreasCloser.Length);
	
	CNavArea bestArea = NULL_AREA;
	
	if (VisibleAreasAfterSentryRange.Length > 0)
		bestArea = VisibleAreasAfterSentryRange.Get(GetRandomInt(0, VisibleAreasAfterSentryRange.Length - 1));
	else if (VisibleAreas.Length > 0)
		bestArea = VisibleAreas.Get(GetRandomInt(0, VisibleAreas.Length - 1));
	else if (AreasCloser.Length > 0)
		bestArea = AreasCloser.Get(GetRandomInt(0, AreasCloser.Length - 1));
	
	delete AreasCloser;
	delete VisibleAreas;
	delete VisibleAreasAfterSentryRange;
	
	//DrawArea(bestArea, false, 6.0);
	return bestArea;
}

bool CNavArea_IsVisible(CNavArea area, float eye[3], float visSpot[3] = NULL_VECTOR)
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
}

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
	
	float health_ratio = view_as<float>(GetClientHealth(actor)) / view_as<float>(BaseEntity_GetMaxHealth(actor));
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

//	PrintToServer("ratio %f max_range %f", ratio, max_range);

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

void CTFBotEngineerIdleResetVars(int actor)
{
	m_iBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
	g_bGoingToGrabBuilding[actor] = false;
	
	m_ctRecomputePathMvMEngiIdle[actor] = -1.0;
	
	m_ctSentrySafe[actor] = -1.0;
	m_ctSentryCooldown[actor] = -1.0;
	
	m_ctDispenserSafe[actor] = -1.0;
	m_ctDispenserCooldown[actor] = -1.0;

	m_ctFindNestHint[actor] = -1.0;
	m_ctAdvanceNestSpot[actor] = -1.0;
	
	pb_bPath[actor] = true;
}

bool CTFBotAttackTank_IsPossible(int actor)
{
	return GetTankToTarget(actor) != -1;
}

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

bool IsAmmoLow(int client)
{
	/* if(g_iCurrentAction[client] == ACTION_MVM_ENGINEER_BUILD_SENTRYGUN && !CTFBotMvMEngineerBuildSentryGun_IsPossible(client)
	|| g_iCurrentAction[client] == ACTION_MVM_ENGINEER_BUILD_DISPENSER && !CTFBotMvMEngineerBuildDispenser_IsPossible(client))
		return true; */

	int Primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);

	if (IsValidEntity(Primary) && !HasAmmo(Primary))
	{
		return true;
	}

	if (!IsWeapon(client, TF_WEAPON_WRENCH))
	{
		if (!IsMeleeWeapon(client))
		{
			float flAmmoRation = float(GetAmmoCount(client, TF_AMMO_PRIMARY)) / float(GetMaxAmmo(client, TF_AMMO_PRIMARY));
			return flAmmoRation < 0.2;
		}
		
		return false;
	}
	
	return GetAmmoCount(client, TF_AMMO_METAL) <= 0;
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

bool IsCombatWeapon(int iWeapon)
{
	if (IsValidEntity(iWeapon))
	{
		switch(TF2Util_GetWeaponID(iWeapon))
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
bool OpportunisticallyUseWeaponAbilities(int client)
{
	//The Hitmans Heatmaker
	if (HasSniperRifle(client) && TF2_IsPlayerInCondition(client, TFCond_Slowed))
	{
		if (TF2_GetRageMeter(client) >= 0.0 && !TF2_IsRageDraining(client))
		{
			g_iAdditionalButtons[client] |= IN_RELOAD;
			return true;
		}
	}
	
	//Phlogistinator
	if (IsWeapon(client, TF_WEAPON_FLAMETHROWER))
	{
		if (TF2_GetRageMeter(client) >= 100.0 && !TF2_IsRageDraining(client))
		{
			VS_PressAltFireButton(client);
			return true;
		}
	}
	
	return false;
}

void EquipBestWeaponForThreat(int client, const CKnownEntity threat)
{
	//Don't care about any weapon restrictions here
	
	int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	
	if (!IsCombatWeapon(primary))
		primary = -1;
	
	int secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	
	if (!IsCombatWeapon(secondary))
		secondary = -1;
	
	//Don't care about mvm-specific rules here
	
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	
	if (!IsCombatWeapon(melee))
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
	
	switch (TF2_GetPlayerClass(client))
	{
		case TFClass_DemoMan, TFClass_Heavy, TFClass_Spy, TFClass_Medic, TFClass_Engineer:
		{
			//Uses primary
		}
		case TFClass_Scout:
		{
			if (secondary != -1)
			{
				//TODO: Clip1?
			}
		}
		case TFClass_Soldier:
		{
			//TODO: Clip1?
		}
		case TFClass_Sniper:
		{
			const float closeSniperRange = 750.0;
			
			float lastKnownPos[3]; threat.GetLastKnownPosition(lastKnownPos);
			
			if (secondary != -1 && CBaseNPC_GetNextBotOfEntity(client).IsRangeLessThanEx(lastKnownPos, closeSniperRange))
				gun = secondary;
		}
		case TFClass_Pyro:
		{
			const float flameRange = 750.0;
			
			float lastKnownPos[3]; threat.GetLastKnownPosition(lastKnownPos);
			
			if (secondary != -1 && CBaseNPC_GetNextBotOfEntity(client).IsRangeGreaterThanEx(lastKnownPos, flameRange))
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

void MonitorKnownEntities(int client, IVision vision)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		
		if (!IsClientInGame(i))
			continue;
		
		if (GetClientTeam(i) == GetClientTeam(client))
			continue;
		
		if (!IsPlayerAlive(i))
			continue;
		
		if (TF2_IsLineOfFireClear4(client, i))
		{
			//If the threat is within our visible sightline, we will know about it
			vision.AddKnownEntity(i);
		}
	}
}

bool ShouldCampBomb(int client)
{
	int bomb = FindBombNearestToHatch();
	
	if (bomb == -1)
		return false;
	
	float hatchPosition[3]; hatchPosition = GetBombHatchPosition();
	float bombPosition[3]; bombPosition = WorldSpaceCenter(bomb);
	
	if (GetVectorDistance(hatchPosition, bombPosition) > BOMB_TOO_CLOSE_RANGE)
	{
		//The bomb is stil pretty far from the hatch
		return false;
	}
	
	int iEnt = -1;
	
	while ((iEnt = FindEntityByClassname(iEnt, "obj_sentrygun")) != -1)
	{
		if (BaseEntity_GetTeamNumber(iEnt) != GetClientTeam(client))
			continue;
		
		const float maxWatchRadius = 1000.0;
		
		if (GetVectorDistance(bombPosition, WorldSpaceCenter(iEnt)) <= maxWatchRadius)
		{
			//There;s a sentry watching the bomb
			return false;
		}
	}
	
	if (GetBombCamperCount() > 0)
	{
		//There;s too many of us doing this behavior
		return false;
	}
	
	return true;
}

int GetBombCamperCount()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (!g_bIsDefenderBot[i])
			continue;
		
		if (ActionsManager.GetAction(i, "DefenderCampBomb") != INVALID_ACTION)
			count++;
	}
	
	return count;
}