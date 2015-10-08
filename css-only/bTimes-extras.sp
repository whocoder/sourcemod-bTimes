#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <bTimes-core>
#include <bTimes-timer>
#include <smlib/entities>
#include "bTimes/extras.sp" // Weapons


#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name = "[bTimes] Extras",
	description = "Essential extras produced by cam for use on 2001",
	author = "cam",
	version = VERSION,
	url = URL
}

int g_iLastRadio[MAXPLAYERS+1];
int g_iSelectedTeam[MAXPLAYERS+1] = {-1, ...};

int m_hActive;
int m_iClip1;
int m_iClip2;
int m_iAmmo1;
int m_iAmmo2;
int m_iFlashAlpha;


char g_msg_pre[128] = {""};
char g_msg_var[128] = {""};
char g_msg_msg[128] = {""};
char RadioCommands[][] = {
	"coverme",			"takepoint",		"hodlpos",			"regroup",			"followme",
	"takingfire",		"go",				"fallback", 		"sticktog",			"getinpos",
	"stormfront",		"report",			"roger", 			"enemyspot",		"needbackup",
	"sectorclear",		"inposition",		"reportingin",		"getout",			"negative",
	"enemydown"
};

public void OnPluginStart()
{
	HookEvent("player_team", 		HookPlayerTeamChange, 	EventHookMode_Pre);
	HookEvent("server_cvar", 		HookServerVariables, 	EventHookMode_Pre);
	HookEvent("player_blind", 		HookPlayerFlash,		EventHookMode_Pre);

	HookEvent("player_spawn",		Event_PlayerSpawn,		EventHookMode_Post);

	RegConsoleCmd("say", 			HookUserChatMessage);
	RegConsoleCmd("say_team", 		HookUserChatMessage);


	RegConsoleCmd("sm_m4a1", 		GiveWeapon_M4	);
	RegConsoleCmd("sm_m4", 			GiveWeapon_M4	);
	RegConsoleCmd("sm_ak47",		GiveWeapon_AK	);
	RegConsoleCmd("sm_ak",			GiveWeapon_AK	);
	RegConsoleCmd("sm_scout", 		GiveWeapon_Scout);
	RegConsoleCmd("sm_p90", 		GiveWeapon_P90	);
	RegConsoleCmd("sm_usp", 		GiveWeapon_USP	);
	RegConsoleCmd("sm_glock", 		GiveWeapon_G18	);
	RegConsoleCmd("sm_awp",			GiveWeapon_AWP	);

	/* Game specific shit */
	RegConsoleCmd("sm_knife",	GiveWeapon_Knife);
	RegConsoleCmd("sm_m3", 		GiveWeapon_M3	);

	m_hActive	 	= FindSendPropOffs("CAI_BaseNPC", "m_hActiveWeapon");
	m_iClip1 	 	= FindSendPropOffs("CBaseCombatWeapon", "m_iClip1");
	m_iClip2 		= FindSendPropOffs("CBaseCombatWeapon", "m_iClip2");
	m_iAmmo1		= FindSendPropOffs("CBaseCombatWeapon", "m_iPrimaryAmmoCount");
	m_iAmmo2		= FindSendPropOffs("CBaseCombatWeapon", "m_iSecondaryAmmoCount");
	m_iFlashAlpha 	= FindSendPropOffs("CCSPlayer", "m_flFlashMaxAlpha");


	for(int command = 0; command < sizeof(RadioCommands); command++)
		RegConsoleCmd(RadioCommands[command], Command_RadioOverride);

	AddCommandListener(Command_JoinTeamOverride, "jointeam");
	AddCommandListener(Command_JoinTeamOverride, "spectate");

	HookEventEx("player_connect_full", Event_OnFullConnect);
}

public void OnMapStart()
{
	CreateTimer(1.0, HookAmmunitionChange, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	// Enforce settings
	CreateTimer(5.0, Timer_CheckConvars, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

/** HOOK FULL CONNECT AND ASSIGN TO SPECTATOR TEAM **/
public Action Event_OnFullConnect(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(!client || client == 0 || !IsClientInGame(client))
		return Plugin_Continue;

	if(g_iSelectedTeam[client] != -1)
	{
		ForcePlayerSuicide(client);
		ChangeClientTeam(client, CS_TEAM_SPECTATOR);
	}

	return Plugin_Continue;
}

public Action Event_RoundPostStart(Handle event, const char[] name, bool PreventBroadcast)
{
	ServerCommand("mp_warmup_end");

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	g_iSelectedTeam[client] = -1;
	g_iLastRadio[client] = -1;
}

/** HOOK SERVER VARIABLE CHANGES & PREVENT DISPLAY **/
public Action HookServerVariables(Handle event, const char[] name, bool dontBroadcast){
	SetEventBroadcast(event, true);

	char cvar_string[64];
	GetEventString(event, "cvarname", cvar_string, sizeof(cvar_string));

	if(StrEqual(cvar_string, "sv_allow_votes", false))
		SetEventInt(event, "cvarvalue", 0);

	if(StrEqual(cvar_string, "sv_airaccelerate", false))
		SetEventInt(event, "cvarvalue", 1000);

	if(StrEqual(cvar_string, "sv_enablebunnyhopping", false))
		SetEventInt(event, "cvarvalue", 1);

	if(StrEqual(cvar_string, "sv_alltalk", false))
		SetEventInt(event, "cvarvalue", 1);

	if(StrEqual(cvar_string, "sv_accelerate", false))
		SetEventInt(event, "cvarvalue", 5);

	if(StrEqual(cvar_string, "sv_friction", false))
		SetEventInt(event, "cvarvalue", 4);

	if(StrEqual(cvar_string, "sv_maxvelocity", false))
		SetEventInt(event, "cvarvalue", 9999999);

	if(StrEqual(cvar_string, "sv_full_alltalk", false))
		SetEventInt(event, "cvarvalue", 1);

	if(StrEqual(cvar_string, "sv_deadtalk", false))
		SetEventInt(event, "cvarvalue", 2);

	if(StrEqual(cvar_string, "sv_staminamax", false))
		SetEventInt(event, "cvarvalue", 0);

	if(StrEqual(cvar_string, "sv_staminalandcost", false))
		SetEventInt(event, "cvarvalue", 0);

	if(StrEqual(cvar_string, "mp_match_end_restart", false))
		SetEventInt(event, "cvarvalue", 0);

	return Plugin_Continue;
}

public Action Timer_CheckConvars(Handle timer)
{
	ForceConVar("sv_alltalk", "1");
	ForceConVar("sv_enablebunnyhopping", "1");
	ForceConVar("sv_airaccelerate", "1000");
	ForceConVar("sv_accelerate", "5");
	ForceConVar("sv_friction", "4");
	ForceConVar("sv_maxvelocity", "9999999");

}

public void OnTimerChatChanged(int MessageType, char[] Message)
{
	if(MessageType == 0)
	{
		Format(g_msg_pre, sizeof(g_msg_pre), Message);
		ReplaceMessage(g_msg_pre, sizeof(g_msg_pre));
	}
	else if(MessageType == 1)
	{
		Format(g_msg_var, sizeof(g_msg_var), Message);
		ReplaceMessage(g_msg_var, sizeof(g_msg_var));
	}
	else if(MessageType == 2)
	{
		Format(g_msg_msg, sizeof(g_msg_msg), Message);
		ReplaceMessage(g_msg_msg, sizeof(g_msg_msg));
	}
}


/** PREVENT AMMO LOSS / RELOADING		**/
public Action HookAmmunitionChange(Handle timer){
		for (int client = 1; client <= MaxClients; client++){
			if(IsClientConnected(client) && IsClientInGame(client) && IsPlayerAlive(client)){
				int clientWeapon = -1;
				if(m_hActive != -1){
					clientWeapon = GetEntDataEnt2(client, m_hActive);
					if(clientWeapon != -1){
						if(m_iClip1 != -1)
							SetEntData(clientWeapon, m_iClip1, 99, 4, true);
						if(m_iClip2 != -1)
							SetEntData(clientWeapon, m_iClip2, 99, 4, true);
						if(m_iAmmo1 != -1)
							SetEntData(clientWeapon, m_iAmmo1, 99, 4, true);
						if(m_iAmmo2 != -1)
							SetEntData(clientWeapon, m_iAmmo2, 99, 4, true);
					}
				}
			}
		}
}

/** PREVENT TEAM CHANGE DISPLAY			**/
public Action HookPlayerTeamChange(Handle event, const char[] name, bool dontBroadcast){
	SetEventBroadcast(event, true);
	return Plugin_Continue;
}

/** PREVENT MAPS FROM USING SAY			**/
public Action HookUserChatMessage(int client, int args){
	if(client == 0) return Plugin_Handled;

	return Plugin_Continue;
}

/** PREVENT RADIO FROM BEING SPAMMED	**/
public Action Command_RadioOverride(int client, int args){
	int CurrentTime = GetTime();

	if(g_iLastRadio[client] == -1){
		g_iLastRadio[client] = CurrentTime;
		return Plugin_Continue;
	}

	int TimeElapsed = CurrentTime - g_iLastRadio[client];
	if(TimeElapsed >= 5){
		g_iLastRadio[client] = CurrentTime;
		return Plugin_Continue;
	} else
		PrintColorText(client, "%s%s You must wait %s%i %sseconds to use a radio command again.",
			g_msg_pre,
			g_msg_msg,
			g_msg_var,
			(5 - TimeElapsed),
			g_msg_msg);

	return Plugin_Handled;
}

/** ANTI FLASH							**/
public Action HookPlayerFlash(Handle event, const char[] name, bool dontBroadcast){
	int client = GetClientOfUserId(GetEventInt(event,"userid"));

	if((IsClientInGame(client)) && (IsPlayerAlive(client)))
		SetEntDataFloat(client, m_iFlashAlpha, 0.0);

	return Plugin_Handled;
}

/** FORCE TEAM CHANGES TO PROPER TEAM	**/
public Action Command_JoinTeamOverride(int client, const char[] command, int argc){
	if(StrEqual(command, "jointeam")){
		// Handle team joining - This way the teams can't ever be 'full'

		char sArg[192];
		GetCmdArgString(sArg, sizeof(sArg));

		int team = StringToInt(sArg);

		if(team == CS_TEAM_T || team == CS_TEAM_CT || team == CS_TEAM_NONE)
			team = CS_TEAM_T;


		g_iSelectedTeam[client] = team;

		if(team == CS_TEAM_T || team == CS_TEAM_CT || team == CS_TEAM_NONE){
			CS_SwitchTeam(client, team);
			CS_RespawnPlayer(client);
		}else if(team == CS_TEAM_SPECTATOR){
			ForcePlayerSuicide(client);
			ChangeClientTeam(client, CS_TEAM_SPECTATOR);
		}
	}else{
		// Command was 'spectate' - Send the player to spectate

		ForcePlayerSuicide(client);
		ChangeClientTeam(client, CS_TEAM_SPECTATOR);
	}

	return Plugin_Handled;
}

public Action Event_JoinTeamFailed(Handle event, const char[] name, bool dontBroadcast){
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client || !IsClientInGame(client))
		return Plugin_Continue;

	int team = g_iSelectedTeam[client];

	if(team != -1)
	{
		if(team == CS_TEAM_T || team == CS_TEAM_CT || team == CS_TEAM_NONE)
			CS_SwitchTeam(client, team);
		else
			ChangeClientTeam(client, team);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool PreventBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	CreateTimer(0.5, Timer_PlayerSpawn, client);
}

public Action Timer_PlayerSpawn(Handle timer, any client)
{
	if(0 < client <= MaxClients){
		if(IsClientConnected(client) && IsClientInGame(client) && IsPlayerAlive(client))
			SetEntProp( client, Prop_Data, "m_nHitboxSet", 2 );
	}
}

//public Action CS_OnGetWeaponPrice(int client, const char[] weapon, int &price)
//{
//	price = 0;
//	return Plugin_Handled;
//}

//public Action CS_OnBuyCommand(int client, const char[] weapon)
//{
//	char WeaponClass[128];
//	CS_GetTranslatedWeaponAlias(weapon, WeaponClass, sizeof(WeaponClass));
//
//	if(!StrEqual(WeaponClass, weapon, false))
//		GivePlayerItem(client, WeaponClass);
//
//	return Plugin_Handled;
//}
