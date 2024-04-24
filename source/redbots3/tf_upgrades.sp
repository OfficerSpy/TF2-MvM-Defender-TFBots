#if defined METHOD_MVM_UPGRADES

#define MAX_UPGRADES 59	//FAKE NEWS

methodmap CEconItemAttributeDefinition
{
	property Address Address
	{
		public get() { return view_as<Address>(this); }
	}

	public int GetIndex()
	{
		int iAttribIndex = LoadFromAddress(this.Address + view_as<Address>(4), NumberType_Int32);
		
		if (iAttribIndex > 3018 || iAttribIndex < 0)
			iAttribIndex = LoadFromAddress(this.Address - view_as<Address>(4), NumberType_Int32); 
	
		return iAttribIndex;
	}
}

public CEconItemAttributeDefinition CEIAD_GetAttributeDefinitionByName(const char[] szAttribute) 
{
	Address CEconItemSchema = GEconItemSchema();
	
	if (CEconItemSchema == Address_Null)
		return view_as<CEconItemAttributeDefinition>(Address_Null);
		
	return view_as<CEconItemAttributeDefinition>(GetAttributeDefinitionByName(CEconItemSchema, szAttribute));
}

enum //CMannVsMachineUpgradeManager
{
	m_Upgrades = 12, //0x000C
	
	CMannVsMachineUpgradeManager_Size = 28
}; //Size=0x001C

enum //CMannVsMachineUpgrades
{
	m_szAttribute = 0,   //0x0000
	m_szIcon = 128,      //0x0080
	m_flIncrement = 388, //0x0184
	m_flCap = 392,       //0x0188
	m_nCost = 396,       //0x018C
	m_iUIGroup = 400,    //0x0190
	m_iQuality = 404,    //0x0194
	m_iTier = 408,       //0x0198
	
	CMannVsMachineUpgrades_Size = 412
}; //Size=0x019C

methodmap CMannVsMachineUpgrades
{
	property Address Address
	{
		public get() 
		{
			return view_as<Address>(this);
		}
	}
	
	public char[] m_szAttribute()
	{
		char attribute[128];
		
		for (int i = 0; i < sizeof(attribute); i++)
			attribute[i] = (LoadFromAddress(this.Address + view_as<Address>(i), NumberType_Int32));
		
		return attribute;
	}
	
	public float m_flCap()
	{
		return float(LoadFromAddress(this.Address + view_as<Address>(m_flCap), NumberType_Int32));
	}
	
	public int m_iUIGroup()
	{
		return (LoadFromAddress(this.Address + view_as<Address>(m_iUIGroup), NumberType_Int32));
	}
}

methodmap CMannVsMachineUpgradeManager < CMannVsMachineUpgrades
{
	public CMannVsMachineUpgradeManager() 
	{
		return view_as<CMannVsMachineUpgradeManager>(g_pMannVsMachineUpgrades);
	}
	
	public CMannVsMachineUpgrades GetUpgradeByIndex(int index)
	{
		Address Upgrades = ((this.Address) + view_as<Address>(m_Upgrades));
		Address pUpgrades = view_as<Address>(LoadFromAddress(Upgrades, NumberType_Int32));
		
		return view_as<CMannVsMachineUpgrades>(pUpgrades + view_as<Address>(index * CMannVsMachineUpgrades_Size));
	}
}
#endif