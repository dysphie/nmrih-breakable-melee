#include <sourcemod>
#include <dhooks>
#include <sdkhooks>
#include <nmr_instructor>

#define MAX_EDICTS	  2048
#define MAX_CLASSNAME 80

#define SND_EMPTY "common/null.wav"

public Plugin myinfo =
{
	name		= "Breakable Melee",
	author		= "Dysphie",
	description = "Makes melee break after some use",
	version		= "1.0.0",
	url			= ""
};

int		  durability[MAX_EDICTS + 1];
int		  maxDurability[MAX_EDICTS + 1];

ConVar	  cvSound;
ConVar	  cvDefaultDurability;

Handle	  fnGetPrintName;
StringMap config;

bool	  lateloaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateloaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("breakable-melee.phrases");

	cvDefaultDurability = CreateConVar("sm_breakable_melee_default_durability", "-1", "Default durability applied to weapons not found in the config file. -1 = unbreakable");
	cvSound				= CreateConVar("sm_breakable_melee_sound", "physics/wood/wood_plank_break8.wav", "Sound to play upon melee weapon breakage");
	cvSound.AddChangeHook(OnBreakableSoundChanged);

	RegAdminCmd("sm_reload_breakable_melee", Cmd_ReloadBreakableMelee, ADMFLAG_GENERIC);
	ParseConfig();

	GameData gamedata = new GameData("breakable-melee.games");
	SetupDetours(gamedata);
	SetupSDKCalls(gamedata);
	delete gamedata;

	if (lateloaded)
	{
		LateloadSupport();
	}
}

void LateloadSupport()
{
	int	 e = -1;
	char classname[MAX_CLASSNAME];
	while ((e = FindEntityByClassname(e, "me_*")) != -1)
	{
		GetEntityClassname(e, classname, sizeof(classname));
		OnMeleeCreated(e, classname);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip);
}

Action OnWeaponEquip(int client, int weapon)
{
	if (!IsValidEntity(weapon)) return Plugin_Continue;

	// TODO: Optimize, remove classname check, check durability[weapon] instead
	char classname[MAX_CLASSNAME];
	GetEntityClassname(weapon, classname, sizeof(classname));

	if (IsBreakableMelee(classname)) {
		UpdateLabel(weapon, client);
	}

	return Plugin_Continue;
}

Action Cmd_ReloadBreakableMelee(int client, int args)
{
	ParseConfig();
	ReplyToCommand(client, "Reloaded melee durability definitions");
	return Plugin_Handled;
}

void ParseConfig()
{
	if (!config)
	{
		config = new StringMap();
	}

	config.Clear();
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/breakable-melee.cfg");

	KeyValues kv = new KeyValues("");
	if (!kv.ImportFromFile(path))
	{
		SetFailState("Failed to open configs/breakable-melee.cfg");
	}

	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			char classname[MAX_CLASSNAME];
			kv.GetSectionName(classname, sizeof(classname));
			int value = kv.GetNum(NULL_STRING, cvDefaultDurability.IntValue);
			config.SetValue(classname, value);
		}
		while (kv.GotoNextKey(false));
	}
}

void OnBreakableSoundChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	PrecacheBreakSound();
}

public void OnMapStart()
{
	PrecacheSound(SND_EMPTY);
	PrecacheBreakSound();
}

void PrecacheBreakSound()
{
	char sound[PLATFORM_MAX_PATH];
	cvSound.GetString(sound, sizeof(sound));

	if (!sound[0]) return;
	PrecacheSound(sound);
}

void SetupDetours(GameData gamedata)
{
	DynamicDetour detour = DynamicDetour.FromConf(gamedata, "CNMRiH_MeleeBase::DrainMeleeSwingStamina");
	detour.Enable(Hook_Pre, Detour_DrainMeleeSwingStamina);
	delete detour;
}

void SetupSDKCalls(GameData gamedata)
{
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseCombatWeapon::GetPrintName");
	PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Pointer);
	fnGetPrintName = EndPrepSDKCall();
	if (!fnGetPrintName)
	{
		SetFailState("Failed to set up SDKCall for CBaseCombatWeapon::GetPrintName");
	}
}

void UpdateLabel(int melee, int client)
{
	char label[128];
	SDKCall(fnGetPrintName, melee, label, sizeof(label));
	float remaining = durability[melee] * 100.0 / maxDurability[melee];
	Format(label, sizeof(label), "%T (%.f%%)", label, client, remaining);

	// Don't use SetEntPropString here or it overflows into subsequent netprops (SM bug)
	DispatchKeyValue(melee, "label_override", label);
}

MRESReturn Detour_DrainMeleeSwingStamina(int melee)
{
	if (durability[melee] == -1) return MRES_Ignored;

	int owner = GetEntPropEnt(melee, Prop_Send, "m_hOwner");
	if (owner == -1) return MRES_Ignored;

	durability[melee]--;

	UpdateLabel(melee, owner);

	if (durability[melee] <= 0)
	{
		Break(melee);
	}
	return MRES_Ignored;
}

void Break(int melee)
{
	char sound[PLATFORM_MAX_PATH];
	cvSound.GetString(sound, sizeof(sound));
	if (!sound[0]) return;

	EmitSoundToAll(sound, melee);

	int owner = GetEntPropEnt(melee, Prop_Send, "m_hOwner");
	if (owner != -1)
	{
		EmitSoundToClient(owner, sound);
		
		char caption[255];
		FormatEx(caption, sizeof(caption), "%T", "Your Melee Broke", owner);

		SendInstructorHint(owner, 
			"hint_melee_broke", "hint_melee_broke", 0, 0, 5,
			ICON_ALERT, ICON_ALERT, 
			caption, caption,  255, 255, 255, 
			0.0, 0.0, 0, "+use", true, false, false, false, SND_EMPTY, 255);
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || client == owner) continue;

		EmitSoundToClient(client, sound, melee);
	}

	SDKHooks_DropWeapon(owner, melee);
	RemoveEntity(melee);



}

public void OnEntityCreated(int entity, const char[] classname)
{
	static const char MELEE_PREFIX[] = "me_";
	if (strncmp(classname, MELEE_PREFIX, sizeof(MELEE_PREFIX) - 1) == 0)
	{
		OnMeleeCreated(entity, classname);
	}
}

void OnMeleeCreated(int melee, const char[] classname)
{
	if (!IsBreakableMelee(classname)) return;

	if (!config.GetValue(classname, durability[melee]))
	{
		durability[melee] = cvDefaultDurability.IntValue;
	}
	
	maxDurability[melee] = durability[melee];
}

bool IsBreakableMelee(const char[] classname) 
{
    static const char MELEE_PREFIX[] = "me_";
    return strncmp(classname, MELEE_PREFIX, sizeof(MELEE_PREFIX) - 1) == 0 &&
           !StrEqual(classname[3], "fists") && !StrEqual(classname[3], "zippo");
}
