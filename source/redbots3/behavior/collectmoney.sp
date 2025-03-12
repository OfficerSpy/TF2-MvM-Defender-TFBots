int m_iCurrencyPack[MAXPLAYERS + 1];

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

float GetTimeUntilRemoved(int powerup)
{
	return CBaseEntity(powerup).GetNextThink("PowerupRemoveThink") - GetGameTime();
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
	//Only one of us needs to really be doing this
	if (GetCountOfBotsWithNamedAction("DefenderCollectMoney") > 0)
		return false;
	
	if (!IsValidCurrencyPack(SelectCurrencyPack(actor)))
		return false;
	
	return true;
}