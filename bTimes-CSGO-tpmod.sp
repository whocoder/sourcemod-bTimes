#include <sourcemod>
#include <sdktools>
#include <dhooks>

#include <bTimes-core>
#include <bTimes-random>

#pragma semicolon 1
#pragma newdecls required

Handle g_hTeleport;

char g_msg_start[128] = {""};
char g_msg_textcol[128] = {""};
char g_msg_varcol[128] = {""};

bool g_bLatedLoaded = false;

public Plugin myinfo = {
	name = "[bTimes] Teleport Mod",
	author = "cam",
	description = "Handles player teleporting and adds options.",
	version = VERSION,
	url = URL
}

public void OnPluginStart(){
	RegConsoleCmdEx("sm_brokentele", SM_BrokenTeles, "Toggles between broken and server default teleports.");
	RegConsoleCmdEx("sm_brokenteles", SM_BrokenTeles, "Toggles between broken and server default teleports.");
	RegConsoleCmdEx("sm_telemod", SM_BrokenTeles, "Toggles between broken and server default teleports.");
	RegConsoleCmdEx("sm_tpmod", SM_BrokenTeles, "Toggles between broken and server default teleports.");
	
	Handle hGameData = LoadGameConfigFile("sdktools.games");
	if(hGameData == INVALID_HANDLE)
		SetFailState("TPMod - Missing SDKTools gamedata.");

	int iOffset = GameConfGetOffset(hGameData, "Teleport");

	CloseHandle(hGameData);

	if(iOffset == -1)
		SetFailState("TPMod - Missing SDKTools Teleport offset.");

	g_hTeleport = DHookCreate(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Hook_DHooks_Teleport);
	DHookAddParam(g_hTeleport, HookParamType_VectorPtr);
	DHookAddParam(g_hTeleport, HookParamType_ObjectPtr);
	DHookAddParam(g_hTeleport, HookParamType_VectorPtr);
	
	if(GetGameType() == GameType_CSGO)
		DHookAddParam(g_hTeleport, HookParamType_Bool); // CS:GO only

	for(int i=1;i<=MaxClients;i++){
		if(IsClientInGame(i)){
			g_bLatedLoaded = true;
			OnClientPutInServer(i);
		}
	}
	
	if(g_bLatedLoaded)
		PrintToServer("TPMod - Late loaded successfully.");
}

public void OnClientPutInServer(int client){
	if(g_hTeleport != INVALID_HANDLE)
		DHookEntity(g_hTeleport, false, client);
	else
		SetFailState("TPMod - Failed to create g_hTeleport with DHookCreate");
}


public MRESReturn Hook_DHooks_Teleport(int client, Handle hParams){
	if(!DHookIsNullParam(hParams, 2))
	{
		if(client != 0 && IsClientInGame(client) && IsPlayerAlive(client) && !IsFakeClient(client)){
			if(GetClientSettings(client) & BROKEN_TELES){
				float oldAngles[3];
				GetClientEyeAngles(client, oldAngles);
				for(int i=0;i<3;i++)
					DHookSetParamObjectPtrVar(hParams, 2, i*4, ObjectValueType_Float, oldAngles[i]);
				
				return MRES_Handled;
			}
		}
	}
	
	return MRES_Ignored;
}

public Action SM_BrokenTeles(int client, int args){
	SetClientSettings(client, GetClientSettings(client) ^ BROKEN_TELES);
	
	if(GetClientSettings(client) & BROKEN_TELES)
		PrintColorText(client, "%s%sBroken teleports are now %senabled%s.",
			g_msg_start,
			g_msg_textcol,
			g_msg_varcol,
			g_msg_textcol);
	else
		PrintColorText(client, "%s%sBroken teleports are now %sdisabled%s.",
			g_msg_start,
			g_msg_textcol,
			g_msg_varcol,
			g_msg_textcol);
	
	return Plugin_Handled;
}

public int OnTimerChatChanged(int MessageType, char[] Message){
	if(MessageType == 0)
	{
		Format(g_msg_start, sizeof(g_msg_start), Message);
		ReplaceMessage(g_msg_start, sizeof(g_msg_start));
	}
	else if(MessageType == 1)
	{
		Format(g_msg_varcol, sizeof(g_msg_varcol), Message);
		ReplaceMessage(g_msg_varcol, sizeof(g_msg_varcol));
	}
	else if(MessageType == 2)
	{
		Format(g_msg_textcol, sizeof(g_msg_textcol), Message);
		ReplaceMessage(g_msg_textcol, sizeof(g_msg_textcol));
	}
}