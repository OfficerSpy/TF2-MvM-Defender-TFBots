#if defined METHOD_MVM_UPGRADES

//Amount of upgrades parsed in mvm_upgrades.txt
#define MAX_UPGRADES	62

//Size of attribute string
#define MAX_ATTRIBUTE_DESCRIPTION_LENGTH	128

enum //CEconItemAttributeDefinition
{
	m_pKVAttribute = 0,
	m_nDefIndex = 4
}

methodmap CEconItemAttributeDefinition
{
	property Address Address
	{
		public get() { return view_as<Address>(this); }
	}

	public int GetIndex()
	{
		int iAttribIndex = LoadFromAddress(this.Address + view_as<Address>(m_nDefIndex), NumberType_Int32);
		
		if (iAttribIndex > 3018 || iAttribIndex < 0)
			iAttribIndex = LoadFromAddress(this.Address - view_as<Address>(m_nDefIndex), NumberType_Int32); 
	
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

//CMannVsMachineUpgrades
// static int offset_szAttribute;
// static int offset_szIcon;
// static int offset_flIncrement;
static int offset_flCap;
// static int offset_nCost;
static int offset_nUIGroup;
// static int offset_nQuality;
static int offset_nTier;
static int CMannVsMachineUpgrades_Size;

enum //CMannVsMachineUpgradeManager
{
	m_Upgrades = 12, //0x000C
	
	CMannVsMachineUpgradeManager_Size = 28
} //Size=0x001C

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
		//szAttrib is located at 0, no need to add its offset here
		
		char attribute[MAX_ATTRIBUTE_DESCRIPTION_LENGTH];
		
		for (int i = 0; i < sizeof(attribute); i++)
			attribute[i] = LoadFromAddress(this.Address + view_as<Address>(i), NumberType_Int32);
		
		return attribute;
	}
	
	public float m_flCap()
	{
		return float(LoadFromAddress(this.Address + view_as<Address>(offset_flCap), NumberType_Int32));
	}
	
	public int m_iUIGroup()
	{
		return LoadFromAddress(this.Address + view_as<Address>(offset_nUIGroup), NumberType_Int32);
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
		Address rawUpgrades = this.Address + view_as<Address>(m_Upgrades);
		Address pUpgrades = DereferencePointer(rawUpgrades);
		
		return view_as<CMannVsMachineUpgrades>(pUpgrades + view_as<Address>(index * CMannVsMachineUpgrades_Size));
	}
}

void InitMvMUpgrades(GameData hGamedata)
{
	// offset_szAttribute = hGamedata.GetOffset("CMannVsMachineUpgrades::szAttrib");
	// offset_szIcon = hGamedata.GetOffset("CMannVsMachineUpgrades::szIcon");
	// offset_flIncrement = hGamedata.GetOffset("CMannVsMachineUpgrades::flIncrement");
	offset_flCap = hGamedata.GetOffset("CMannVsMachineUpgrades::flCap");
	// offset_nCost = hGamedata.GetOffset("CMannVsMachineUpgrades::nCost");
	offset_nUIGroup = hGamedata.GetOffset("CMannVsMachineUpgrades::nUIGroup");
	// offset_nQuality = hGamedata.GetOffset("CMannVsMachineUpgrades::nQuality");
	offset_nTier = hGamedata.GetOffset("CMannVsMachineUpgrades::nTier");
	CMannVsMachineUpgrades_Size = offset_nTier + 4;
	
#if defined TESTING_ONLY
	// LogMessage("CMannVsMachineUpgrades->szAttrib = %d", offset_szAttribute);
	// LogMessage("CMannVsMachineUpgrades->szIcon = %d", offset_szIcon);
	// LogMessage("CMannVsMachineUpgrades->flIncrement = %d", offset_flIncrement);
	LogMessage("InitMvMUpgrades: CMannVsMachineUpgrades->flCap = %d", offset_flCap);
	// LogMessage("CMannVsMachineUpgrades->nCost = %d", offset_nCost);
	LogMessage("InitMvMUpgrades: CMannVsMachineUpgrades->nUIGroup = %d", offset_nUIGroup);
	// LogMessage("CMannVsMachineUpgrades->nQuality = %d", offset_nQuality);
	LogMessage("InitMvMUpgrades: CMannVsMachineUpgrades->nTier = %d", offset_nTier);
	LogMessage("InitMvMUpgrades: Size of CMannVsMachineUpgrades = %d", CMannVsMachineUpgrades_Size);
#endif
}

/* TECHNICAL DATA FOR REFERENCE
class CEconItemAttributeDefinition
{
	KeyValues	*m_pKVAttribute;
	attrib_definition_index_t	m_nDefIndex;
	const class ISchemaAttributeType *m_pAttrType;
	bool		m_bHidden;
	bool		m_bWebSchemaOutputForced;
	bool		m_bStoredAsInteger;
	bool		m_bInstanceData;
	EAssetClassAttrExportRule_t	m_eAssetClassAttrExportRule;
	uint32		m_unAssetClassBucket;
	bool		m_bIsSetBonus;
	int			m_iUserGenerationType;
	attrib_effect_types_t m_iEffectType;
	int			m_iDescriptionFormat;
	const char	*m_pszDescriptionString;
	const char	*m_pszArmoryDesc;
	const char	*m_pszDefinitionName;
	const char	*m_pszAttributeClass;
	bool		m_bCanAffectMarketName;
	bool		m_bCanAffectRecipeComponentName;
	econ_tag_handle_t	m_ItemDefinitionTag;
	mutable string_t	m_iszAttributeClass;
}

class CMannVsMachineUpgrades
{
	char szAttrib[ MAX_ATTRIBUTE_DESCRIPTION_LENGTH ];
	char szIcon[ MAX_PATH ];
	float flIncrement;
	float flCap;
	int nCost;
	int nUIGroup;
	int nQuality;
	int nTier;
}

class CMannVsMachineUpgradeManager
{
	CUtlVector< CMannVsMachineUpgrades > m_Upgrades;
	CUtlMap< const char*, int > m_AttribMap;
} */
#endif