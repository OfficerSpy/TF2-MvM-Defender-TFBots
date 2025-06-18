#define SENTRY_WATCH_BOMB_RANGE	400.0

float m_ctSentrySafe[MAXPLAYERS + 1];
float m_ctSentryCooldown[MAXPLAYERS + 1];

float m_ctDispenserSafe[MAXPLAYERS + 1]; 
float m_ctDispenserCooldown[MAXPLAYERS + 1];

float m_ctFindNestHint[MAXPLAYERS + 1]; 
float m_ctAdvanceNestSpot[MAXPLAYERS + 1]; 

float m_ctRecomputePathMvMEngiIdle[MAXPLAYERS + 1];

CNavArea m_aNestArea[MAXPLAYERS + 1] = {NULL_AREA, ...};

bool g_bGoingToGrabBuilding[MAXPLAYERS + 1];
int m_hBuildingToGrab[MAXPLAYERS + 1];

BehaviorAction CTFBotMvMEngineerIdle()
{
	BehaviorAction action = ActionsManager.Create("DefenderMvMEngineerIdle");
	
	action.OnStart = CTFBotMvMEngineerIdle_OnStart;
	action.Update = CTFBotMvMEngineerIdle_Update;
	action.OnEnd = CTFBotMvMEngineerIdle_OnEnd;
	
	return action;
}

static Action CTFBotMvMEngineerIdle_OnStart(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	m_pPath[actor].SetMinLookAheadDistance(GetDesiredPathLookAheadRange(actor));
	
	CTFBotMvMEngineerIdle_ResetProperties(actor);
	
	return action.Continue();
}

static Action CTFBotMvMEngineerIdle_Update(BehaviorAction action, int actor, float interval, ActionResult result)
{
	int sentry    = GetObjectOfType(actor, TFObject_Sentry);
	int dispenser = GetObjectOfType(actor, TFObject_Dispenser);
	
	bool bShouldAdvance = CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(actor);
	
	if (bShouldAdvance && !g_bGoingToGrabBuilding[actor])
	{
		//TF2_DetonateObjectsOfType(actor, TFObject_Sentry);
		//TF2_DetonateObjectsOfType(actor, TFObject_Dispenser);
		
		PrintToServer("CTFBotMvMEngineerIdle_Update: ADVANCE");
		
		//RIGHT NOW
		CTFBotMvMEngineerIdle_ResetProperties(actor);
		
		m_aNestArea[actor] = PickBuildArea(actor);
	}
	
	return action.Continue();
}

static void CTFBotMvMEngineerIdle_OnEnd(BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result)
{
	
}

static void CTFBotMvMEngineerIdle_ResetProperties(int actor)
{
	m_hBuildingToGrab[actor] = INVALID_ENT_REFERENCE;
	g_bGoingToGrabBuilding[actor] = false;
	
	m_ctRecomputePathMvMEngiIdle[actor] = -1.0;
	
	m_ctSentrySafe[actor] = -1.0;
	m_ctSentryCooldown[actor] = -1.0;
	
	m_ctDispenserSafe[actor] = -1.0;
	m_ctDispenserCooldown[actor] = -1.0;

	m_ctFindNestHint[actor] = -1.0;
	m_ctAdvanceNestSpot[actor] = -1.0;
	
	g_arrPluginBot[actor].bPathing = true;
}

bool CTFBotMvMEngineerIdle_ShouldAdvanceNestSpot(int actor)
{
	if (m_aNestArea[actor] == NULL_AREA)
		return false;
	
	if (m_ctAdvanceNestSpot[actor] <= 0.0)
	{
		m_ctAdvanceNestSpot[actor] = GetGameTime() + 5.0;
		return false;
	}
	
	int obj = GetObjectOfType(actor, TFObject_Sentry);
	
	if (obj != INVALID_ENT_REFERENCE && BaseEntity_GetHealth(obj) < TF2Util_GetEntityMaxHealth(obj))
	{
		m_ctAdvanceNestSpot[actor] = GetGameTime() + 5.0;
		return false;
	}
	
	//IsElapsed
	if (GetGameTime() > m_ctAdvanceNestSpot[actor])
	{
		m_ctAdvanceNestSpot[actor] = -1.0;
	}
	
	BombInfo_t bombinfo;
	
	if (!GetBombInfo(bombinfo)) 
	{
		return false;
	}
	
	float m_flBombTargetDistance = GetTravelDistanceToBombTarget(m_aNestArea[actor]);
	
	//No point in advancing now.
	if (m_flBombTargetDistance <= 1000.0)
	{
		return false;
	}
	
	bool bigger = (m_flBombTargetDistance > bombinfo.flMaxBattleFront);
	
	//PrintToServer("m_flBombTargetDistance %f > bombinfo.hatch_dist_back %f = %s", m_flBombTargetDistance, bombinfo.GetFloat("hatch_dist_back"), bigger ? "Yes" : "No");
	
	return bigger;
}