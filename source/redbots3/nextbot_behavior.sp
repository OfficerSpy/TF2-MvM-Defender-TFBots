#define FLAMETHROWER_REACH_RANGE	350.0
#define FLAMEBALL_REACH_RANGE	526.0

PathFollower m_pPath[MAXPLAYERS + 1];
ChasePath m_pChasePath[MAXPLAYERS + 1];
float m_flRepathTime[MAXPLAYERS + 1];

static int m_nCurrentPowerupBottle[MAXPLAYERS + 1];
static float m_flNextBottleUseTime[MAXPLAYERS + 1];

#if defined EXTRA_PLUGINBOT
//Replicate behavior of PathFollower's PluginBot
bool pb_bPath[MAXPLAYERS + 1];
float pb_vecPathGoal[MAXPLAYERS + 1][3];
int pb_iPathGoalEntity[MAXPLAYERS + 1];
#endif

#include "behavior/defenderattack.sp"
#include "behavior/markgiant.sp"
#include "behavior/collectmoney.sp"
#include "behavior/gotoupgrade.sp"
#include "behavior/upgrade.sp"
#include "behavior/getammo.sp"
#include "behavior/movetofront.sp"
#include "behavior/gethealth.sp"
#include "behavior/engineeridle.sp"
#include "behavior/engineerbuildsentrygun.sp"
#include "behavior/engineerbuilddispenser.sp"
#include "behavior/spylurk.sp"
#include "behavior/spysap.sp"
#include "behavior/spysapplayer.sp"
#include "behavior/medicrevive.sp"
#include "behavior/attackforuber.sp"
#include "behavior/evadebuster.sp"
#include "behavior/campbomb.sp"
#include "behavior/attacktank.sp"
#include "behavior/destroyteleporter.sp"
#include "behavior/guardpoint.sp"
#include "behavior/collectnearmoney.sp"

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
	m_iSapTarget[client] = -1;
	m_iPlayerSapTarget[client] = -1;
	m_vecStartArea[client] = NULL_VECTOR;
	m_iTankTarget[client] = -1;
	m_iTeleporterTarget[client] = -1;
	m_vecPointDefendArea[client] = NULL_VECTOR;
	
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
			// action.SelectMoreDangerousThreat = CTFBotMainAction_SelectMoreDangerousThreat;
			action.SelectTargetPoint = CTFBotMainAction_SelectTargetPoint;
			action.ShouldAttack = CTFBotMainAction_ShouldAttack;
		}
		else if (StrEqual(name, "TacticalMonitor"))
		{
			action.Update = CTFBotTacticalMonitor_Update;
			
			/* NOTE: I've noticed this seems to be very inconsistent at the MainAction level and it also seems to behave differently on windows vs linux
			Let's just override it at the TacticalMonitor level, though this one doesn't actually have a function for it in its class
			But since all nextbot callbacks are virtual i think this should work fine */
			action.SelectMoreDangerousThreat = CTFBotMainAction_SelectMoreDangerousThreat;
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
			action.Update = CTFBotSniperLurk_Update;
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
	
	int myWeapon = BaseCombatCharacter_GetActiveWeapon(me);
	
	if (myWeapon != -1 && (TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_FLAMETHROWER || IsMeleeWeapon(myWeapon)))
	{
		//Always target the closest one to us with these weapons
		knownEntity = SelectCloserThreat(nextbot, threat1, threat2);
		return Plugin_Changed;
	}
	
	int iThreat1 = threat1.GetEntity();
	int iThreat2 = threat2.GetEntity();
	
	//If we can only see one threat, then it's our best target
	int oneVisible = FindOnlyOneVisibleEntity(me, iThreat1, iThreat2);
	
	if (oneVisible == iThreat1)
	{
		knownEntity = threat1;
		return Plugin_Changed;
	}
	
	if (oneVisible == iThreat2)
	{
		knownEntity = threat2;
		return Plugin_Changed;
	}
	
	if (myWeapon != -1 && TF2Util_GetWeaponID(myWeapon) == TF_WEAPON_MINIGUN)
	{
		if (TF2_IsRageDraining(me))
		{
			//When using knockback rage, focus only on particular threats
			if (BaseEntity_IsPlayer(iThreat1) && (TF2_HasTheFlag(iThreat1) || TF2_IsMiniBoss(iThreat1)))
			{
				knownEntity = threat1;
				return Plugin_Changed;
			}
			
			if (BaseEntity_IsPlayer(iThreat2) && (TF2_HasTheFlag(iThreat2) || TF2_IsMiniBoss(iThreat2)))
			{
				knownEntity = threat2;
				return Plugin_Changed;
			}
		}
		
		//Minigun deals 75% less damage against tanks so prioritize them least
		if (IsBaseBoss(iThreat1) && !IsBaseBoss(iThreat2))
		{
			knownEntity = threat2;
			return Plugin_Changed;
		}
		
		if (!IsBaseBoss(iThreat1) && IsBaseBoss(iThreat2))
		{
			knownEntity = threat1;
			return Plugin_Changed;
		}
	}
	
	float rangeSq1 = nextbot.GetRangeSquaredTo(iThreat1);
	float rangeSq2 = nextbot.GetRangeSquaredTo(iThreat2);
	
	//Target the closest visible
	if (rangeSq1 < rangeSq2)
	{
		knownEntity = threat1;
	}
	else
	{
		knownEntity = threat2;
	}
	
	if (BaseEntity_IsPlayer(knownEntity.GetEntity()))
	{
		//Target the healer
		knownEntity = GetHealerOfThreat(nextbot, knownEntity);
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
			case TF_WEAPON_GRENADELAUNCHER, TF_WEAPON_PIPEBOMBLAUNCHER:
			{
				//TFBots can't compensate their arc if projectile speed differs, so we do our own calculation here
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
			case TF_WEAPON_PARTICLE_CANNON:
			{
				//TFBots won't do projectile prediciton with cow mangler 5000 since it's left out of the code, so we'll do it ourselves
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
					
					if (!IsLineOfFireClearPosition(me, GetEyePosition(me), target_point))
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
			case TF_WEAPON_SNIPERRIFLE, TF_WEAPON_SNIPERRIFLE_DECAP, TF_WEAPON_SNIPERRIFLE_CLASSIC:
			{
				//For sniper rifles, try to lookup their head bone to aim at
				int bone = LookupBone(entity, "bip_head");
				
				if (bone != -1)
				{
					float vEmpty[3];
					GetBonePosition(entity, bone, vec, vEmpty);
					vec[2] += 3.0;
					
					return Plugin_Changed;
				}
				
				//For sniper rifles, TFBots always try to aim at the entity's eye position on harder difficulties
			}
			case TF_WEAPON_REVOLVER:
			{
				//Try to aim for the head with ambassador
				if (CanRevolverHeadshot(myWeapon))
				{
					int bone = LookupBone(entity, "bip_head");
					
					if (bone != -1)
					{
						float vEmpty[3];
						GetBonePosition(entity, bone, vec, vEmpty);
						vec[2] += 3.0;
						
						return Plugin_Changed;
					}
					
					vec = GetEyePosition(entity);
					
					return Plugin_Changed;
				}
			}
			/* case TF_WEAPON_FLAMETHROWER:
			{
				if (IsBaseBoss(entity))
				{
					GetFlameThrowerAimForTank(entity, vec);
					PrintToChatAll("AIM AT: %f %f %f", vec[0], vec[1], vec[2]);
					
					return Plugin_Changed;
				}
			} */
		}
	}
	
	//Let the game do its default aiming
	return Plugin_Continue;
}

static Action CTFBotMainAction_ShouldAttack(BehaviorAction action, INextBot nextbot, CKnownEntity knownEntity, QueryResultType& result)
{
	int me = action.Actor;
	
	if (g_bIsDefenderBot[me] == false)
		return Plugin_Continue;
	
	//Always attack even in spawn room because we are not the invaders
	result = ANSWER_YES;
	return Plugin_Changed;
}

public Action CTFBotTacticalMonitor_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	if (GameRules_GetRoundState() == RoundState_RoundRunning)
	{
		bool low_health = false;
		
		float health_ratio = float(GetClientHealth(actor)) / float(TEMP_GetPlayerMaxHealth(actor));
		
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
	
	int secondary = GetPlayerWeaponSlot(actor, TFWeaponSlot_Secondary);
	
	if (secondary == -1)
		return action.SuspendFor(CTFBotDefenderAttack(), "No medigun");
	
	if (CTFBotAttackUber_IsPossible(actor, secondary))
		return action.SuspendFor(CTFBotAttackUber(), "Seek uber");
	
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
				g_arrExtraButtons[actor].PressButtons(IN_RELOAD);
			else if (iLastDmgType & DMG_BLAST && iResistType != MEDIGUN_BLAST_RESIST)
				g_arrExtraButtons[actor].PressButtons(IN_RELOAD);
			else if (iLastDmgType & DMG_BURN && iResistType != MEDIGUN_FIRE_RESIST)
				g_arrExtraButtons[actor].PressButtons(IN_RELOAD);
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

public Action CTFBotSniperLurk_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	if (!CanUsePrimayWeapon(actor))
	{
		//Where did my gun go?
		return action.SuspendFor(CTFBotDefenderAttack(), "Lost my rifle");
	}
	
	return Plugin_Continue;
}

public Action CTFBotSniperLurk_SelectMoreDangerousThreat(BehaviorAction action, INextBot nextbot, int entity, CKnownEntity threat1, CKnownEntity threat2, CKnownEntity& knownEntity)
{
	int me = action.Actor;
	
	if (g_bIsDefenderBot[me] == false)
		return Plugin_Continue;
	
	//Return NULL so the normal threat targetting happens
	knownEntity = NULL_KNOWN_ENTITY;
	
	int iThreat1 = threat1.GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat1) && IsLineOfFireClearEntity(me, GetEyePosition(me), iThreat1))
	{
		int enemyWeapon = BaseCombatCharacter_GetActiveWeapon(iThreat1);
		
		if (enemyWeapon != -1)
		{
			int enemyWepID = TF2Util_GetWeaponID(enemyWeapon);
			
			if (WeaponID_IsSniperRifle(enemyWepID))
			{
				//This sniper ain't gonna snipe me
				knownEntity = threat1;
				return Plugin_Changed;
			}
			else if (enemyWepID == TF_WEAPON_MEDIGUN)
			{
				if (GetEntPropEnt(enemyWeapon, Prop_Send, "m_hHealingTarget") != -1 || GetEntPropFloat(enemyWeapon, Prop_Send, "m_flChargeLevel") >= 1.0)
				{
					//Healers should die first, ideally before they pop
					knownEntity = threat1;
					return Plugin_Changed;
				}
			}
		}
	}
	
	int iThreat2 = threat2.GetEntity();
	
	if (BaseEntity_IsPlayer(iThreat2) && IsLineOfFireClearEntity(me, GetEyePosition(me), iThreat2))
	{
		int enemyWeapon = BaseCombatCharacter_GetActiveWeapon(iThreat2);
		
		if (enemyWeapon != -1)
		{
			int enemyWepID = TF2Util_GetWeaponID(enemyWeapon);
			
			if (WeaponID_IsSniperRifle(enemyWepID))
			{
				knownEntity = threat2;
				return Plugin_Changed;
			}
			else if (enemyWepID == TF_WEAPON_MEDIGUN)
			{
				if (GetEntPropEnt(enemyWeapon, Prop_Send, "m_hHealingTarget") != -1 || GetEntPropFloat(enemyWeapon, Prop_Send, "m_flChargeLevel") >= 1.0)
				{
					knownEntity = threat2;
					return Plugin_Changed;
				}
			}
		}
	}
	
	return Plugin_Changed;
}

public Action CTFBotSpyLeaveSpawnRoom_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	if (g_bIsDefenderBot[actor] == false)
		return Plugin_Continue;
	
	return action.Done();
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
				else if (CTFBotCollectNearMoney_SelectTarget(client))
					return action.SuspendFor(CTFBotCollectNearMoney(), "Nearby money");
			}
			case TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan:
			{
				if (CTFBotAttackTank_SelectTarget(client))
					return action.SuspendFor(CTFBotAttackTank(), "Attacking tank");
				else if (CTFBotDefenderAttack_SelectTarget(client))
					return action.SuspendFor(CTFBotDefenderAttack(), "CTFBotAttack_IsPossible");
				else if (CTFBotCollectNearMoney_SelectTarget(client))
					return action.SuspendFor(CTFBotCollectNearMoney(), "Nearby money");
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
	
	/* The round's probably already running
	CTFBotScenarioMonitor_Update will assign the appropriate task */
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
			float flAmmoRation = float(BaseCombatCharacter_GetAmmoCount(client, TF_AMMO_PRIMARY)) / float(TF2Util_GetPlayerMaxAmmo(client, TF_AMMO_PRIMARY));
			return flAmmoRation < 0.2;
		}
		
		return false;
	}
	
	return BaseCombatCharacter_GetAmmoCount(client, TF_AMMO_METAL) <= 0;
}

bool IsAmmoFull(int client)
{
	bool isPrimaryFull = BaseCombatCharacter_GetAmmoCount(client, TF_AMMO_PRIMARY) >= TF2Util_GetPlayerMaxAmmo(client, TF_AMMO_PRIMARY);
	bool isSecondaryFull = BaseCombatCharacter_GetAmmoCount(client, TF_AMMO_SECONDARY) >= TF2Util_GetPlayerMaxAmmo(client, TF_AMMO_SECONDARY);
	
	if (TF2_GetPlayerClass(client) == TFClass_Engineer)
	{
		//In addition, I want some metal as well
		return BaseCombatCharacter_GetAmmoCount(client, TF_AMMO_METAL) >= 200 && isPrimaryFull && isSecondaryFull;
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
	
	if (WeaponID_IsSniperRifle(weaponID))
		return FLT_MAX;
	
	if (weaponID == TF_WEAPON_ROCKETLAUNCHER)
		return 1250.0;
	
	return 500.0;
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
	if (weaponID == TF_WEAPON_SNIPERRIFLE && TF2_IsPlayerInCondition(client, TFCond_Slowed) && threat.IsVisibleRecently())
	{
		if (TF2_GetRageMeter(client) >= 0.0 && !TF2_IsRageDraining(client))
		{
			g_arrExtraButtons[client].PressButtons(IN_RELOAD);
			return true;
		}
	}
	
	int iThreat = threat.GetEntity();
	
	//Phlogistinator
	if (weaponID == TF_WEAPON_FLAMETHROWER && bot.IsRangeLessThan(iThreat, FLAMETHROWER_REACH_RANGE) && !TF2_IsCritBoosted(client))
	{
		if (TF2_GetRageMeter(client) >= 100.0 && !TF2_IsRageDraining(client))
		{
			VS_PressAltFireButton(client);
			return true;
		}
	}
	
	if (weaponID == TF_WEAPON_MINIGUN && BaseEntity_IsPlayer(iThreat) && TF2_GetRageMeter(client) >= 100.0)
	{
		if (TF2_HasTheFlag(iThreat))
		{
			float vThreatOrigin[3]; GetClientAbsOrigin(iThreat, vThreatOrigin);
			
			if (GetVectorDistance(vThreatOrigin, GetBombHatchPosition()) <= 100.0)
			{
				g_arrExtraButtons[client].PressButtons(IN_ATTACK3);
				return true;
			}
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
			
			if (!IsLineOfFireClearEntity(client, GetEyePosition(client), iThreat))
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
				if ((TF2_IsMiniBoss(iThreat) && GetClientHealth(iThreat) > 5000) || (IsFailureImminent(client) && GetClientHealth(iThreat) > 2000))
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
			
			float healthRatio = float(GetClientHealth(client)) / float(TEMP_GetPlayerMaxHealth(client));
			
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
			
			//TODO: engineer should probably only uses this if his sentry was destroyed
			if (TF2_GetPlayerClass(client) == TFClass_Engineer)
				return false;
			
			//We're busy going for the tank
			if (ActionsManager.GetAction(client, "DefenderAttackTank") != INVALID_ACTION)
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
	
	if (BaseCombatCharacter_GetAmmoCount(client, TF_AMMO_PRIMARY) <= 0)
		primary = -1;
	
	if (BaseCombatCharacter_GetAmmoCount(client, TFWeaponSlot_Secondary) <= 0)
		secondary = -1;
	
	INextBot myBot = CBaseNPC_GetNextBotOfEntity(client);
	int threatEnt = threat.GetEntity();
	
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
				int weaponID = TF2Util_GetWeaponID(secondary);
				
				if ((weaponID == TF_WEAPON_JAR_MILK || weaponID == TF_WEAPON_CLEAVER) && HasAmmo(secondary) && BaseEntity_IsPlayer(threatEnt) && !TF2_IsInvulnerable(threatEnt))
				{
					//Always throw milk at them if we can
					gun = secondary;
				}
				else if (gun != -1 && !Clip1(gun))
				{
					gun = secondary;
				}
			}
		}
		case TFClass_Soldier:
		{
			if (gun != -1 && !Clip1(gun))
			{
				/* NOTE: we do not want to switch off the rocket launcher against uber threats or else we will conflctingly ignore them
				on and off due to the detour callback that we do at DHookCallback_IsIgnored_Pre */
				if (secondary != -1 && Clip1(secondary) && (!BaseEntity_IsPlayer(threatEnt) || !TF2_IsInvulnerable(threatEnt)))
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
			if (secondary != -1 && TF2Util_GetWeaponID(secondary) == TF_WEAPON_JAR && HasAmmo(secondary) && BaseEntity_IsPlayer(threatEnt) && !TF2_IsInvulnerable(threatEnt))
			{
				//Always throw pee at them if we can
				gun = secondary;
			}
			else if (primary != -1 && TF2Util_GetWeaponID(primary) == TF_WEAPON_COMPOUND_BOW)
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
			if (secondary != -1 && TF2Util_GetWeaponID(secondary) == TF_WEAPON_JAR_GAS && HasAmmo(secondary) && BaseEntity_IsPlayer(threatEnt) && !TF2_IsInvulnerable(threatEnt))
			{
				//Always throw gas
				gun = secondary;
			}
			else
			{
				const float flameRange = 750.0;
				
				float lastKnownPos[3]; threat.GetLastKnownPosition(lastKnownPos);
				
				if (secondary != -1 && myBot.IsRangeGreaterThanEx(lastKnownPos, flameRange))
					gun = secondary;
				
				if (BaseEntity_IsPlayer(threatEnt))
				{
					TFClassType threatClass = TF2_GetPlayerClass(threatEnt);
					
					if (threatClass == TFClass_Soldier || threatClass == TFClass_DemoMan)
						gun = primary;
				}
			}
		}
	}
	
	if (gun != -1)
		TF2Util_SetPlayerActiveWeapon(client, gun);
}

/* Get the medic healing this threat only if we know about him and he's in our FOV
otherwise return the original threat if there is no known healer right now */
CKnownEntity GetHealerOfThreat(INextBot bot, const CKnownEntity threat)
{
	if (!threat)
		return NULL_KNOWN_ENTITY;
	
	int playerThreat = threat.GetEntity();
	
	for (int i = 0; i < TF2_GetNumHealers(playerThreat); i++)
	{
		int playerHealer = TF2Util_GetPlayerHealer(playerThreat, i);
		
		if (playerHealer != -1 && BaseEntity_IsPlayer(playerHealer))
		{
			CKnownEntity knownHealer = bot.GetVisionInterface().GetKnown(playerHealer);
			
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
	if (nb_blind.BoolValue)
		return;
	
	static int maxEntCount = -1;
	
	if (maxEntCount == -1)
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
		
		/* IVision::UpdateKnownEntities runs its own check for collecting potentially visible entities
		However it only seems to check for them only regarding the bot's FOV
		When the known entity leaves the bot's FOV, it would eventually become obsolete after 10 seconds
		And when it becomes obsolete, it gets removed from the list of known entities
		So here we are basically expanding the functionality using our own line-of-sight of check */
		if (IsLineOfFireClearEntity(client, GetEyePosition(client), i))
		{
			CKnownEntity known = vision.GetKnown(i);
			
			if (known)
			{
				//We already know about this entity and we can currently see it
				known.UpdatePosition();
			}
			else
			{
				//We didn't know about it but we can see it now, recognize it
				vision.AddKnownEntity(i);
			}
		}
	}
}

int GetCountOfBotsWithNamedAction(const char[] name, int ignore = -1)
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (i != ignore && IsClientInGame(i) && g_bIsDefenderBot[i] && ActionsManager.GetAction(i, name) != INVALID_ACTION)
			count++;
	
	return count;
}

void UtilizeCompressionBlast(int client, INextBot bot, const CKnownEntity threat, int enhancedStage = 0)
{
	if (threat == NULL_KNOWN_ENTITY)
		return;
	
	if (redbots_manager_bot_reflect_skill.IntValue < 1)
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
				g_arrExtraButtons[client].ReleaseButtons(IN_ATTACK);
				VS_PressAltFireButton(client);
				return;
			}
			
			if (TF2_IsPlayerInCondition(iThreat, TFCond_Charging))
			{
				//Shove chargers away from us
				g_arrExtraButtons[client].ReleaseButtons(IN_ATTACK);
				VS_PressAltFireButton(client);
				return;
			}
			
			if (TF2_HasTheFlag(iThreat) && GetVectorDistance(threatOrigin, GetBombHatchPosition()) <= 100.0)
			{
				//Shove the bomb carrier off the hatch
				g_arrExtraButtons[client].ReleaseButtons(IN_ATTACK);
				VS_PressAltFireButton(client);
				return;
			}
		}
	}
	
	if (redbots_manager_bot_reflect_skill.IntValue < 2)
		return;
	
	if (redbots_manager_bot_reflect_chance.FloatValue < 100.0 && TransientlyConsistentRandomValue(client, 1.0) > redbots_manager_bot_reflect_chance.FloatValue / 100.0)
		return;
	
	//Enhanced projectile airblast
	int myTeam = GetClientTeam(client);
	float myEyePos[3]; GetClientEyePosition(client, myEyePos);
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "tf_projectile_*")) != -1)
	{
		if (BaseEntity_GetTeamNumber(ent) == myTeam)
			continue;
		
		if (!CanBeReflected(ent))
			continue;
		
		float origin[3]; BaseEntity_GetLocalOrigin(ent, origin);
		float vec[3]; MakeVectorFromPoints(origin, myEyePos, vec);
		
		//Airblast the projectile if we are actually facing towards it
		if (GetVectorLength(vec) < 150.0)
		{
			g_arrExtraButtons[client].ReleaseButtons(IN_ATTACK);
			VS_PressAltFireButton(client);
			return;
		}
	}
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
		PrintToChatAll("[PurchaseAffordableCanteens] %N purchased %d charges (upgrade %d) and wanted %d charges", client, purchaseAmount, selectedUpgradeIndex, count);
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
	
	//Based on our rolled number, decide to buyback
	return g_iBuybackNumber[client] <= redbots_manager_bot_buyback_chance.IntValue;
}

bool ShouldUpgradeMidRound(int client)
{
	//If we were revived, we should not bother
	if (!TF2Util_IsPointInRespawnRoom(WorldSpaceCenter(client), client))
		return false;
	
	//Based on our rolled number from spawn, decide to buy upgrades now
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

float TransientlyConsistentRandomValue(int client, float period = 10.0, int seedValue = 0)
{
	CNavArea area = CBaseCombatCharacter(client).GetLastKnownArea();
	
	if (!area)
		return 0.0;
	
	int timeMod = RoundToFloor(GetGameTime() / period) + 1;
	
	return FloatAbs(Cosine(float(seedValue + (client * area.GetID() * timeMod))));
}

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

//Since March 28 2018 update, flamethrower damage is calculated based on the oldest particles
//Aim a bit higher on the tank for the highest damage output
void GetFlameThrowerAimForTank(int tank, float aimPos[3])
{
	aimPos = WorldSpaceCenter(tank);
	aimPos[2] += 90.0;
}