/* Defender Bot Team Manager
An experimental AI designed to tackle on blue team players */
static ArrayList m_adtBotLineup;
static int m_iSuccesses;
static int m_iFailures;
static int m_iTanksSpawned;

public void DBTM_OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tank_boss"))
		m_iTanksSpawned++;
}

void DBTM_Initialize()
{
	m_adtBotLineup = new ArrayList(TF2_CLASS_MAX_NAME_LENGTH);
}

void DBTM_UpdateBotLineup()
{
	m_adtBotLineup.Clear();
	
	int redTeamSize = redbots_manager_defender_team_size.IntValue;
	
	if (m_iFailures == 0)
	{
		//No fails, so we're gonna be casual about it
		for (int i = 0; i < redTeamSize; i++)
			m_adtBotLineup.PushString(g_sRawPlayerClassNames[GetRandomInt(1, 9)]);
		
		return;
	}
	
	float ratio = m_iSuccesses / m_iFailures;
	
	//TODO: other reatios in revrse oder
	
	if (ratio < 1.0)
	{
		//We're starting to a plummit a bit, let's ditch the potentially weaker link here
		const char strClasses[][] = { "scout", "sniper", "soldier", "demoman", "medic", "heavyweapons", "pyro", "engineer" };
		
		for (int i = 0; i < redTeamSize; i++)
			m_adtBotLineup.PushString(strClasses[GetRandomInt(1, sizeof(strClasses))]);
	}
	
	//Red is probably doing okay, so just be casual
	for (int i = 0; i < redTeamSize; i++)
		m_adtBotLineup.PushString(g_sRawPlayerClassNames[GetRandomInt(1, 9)]);
}