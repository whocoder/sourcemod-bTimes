#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = {
	name = "[bTimes] Core",
	author = "blacky, cam",
	description = "The root of bTimes",
	version = VERSION,
	url = URL
}

#include <sourcemod>
#include <sdktools>
#include <scp>
#include <smlib/clients>
#include <bTimes-timer>
#include <cstrike>

Handle g_hCommandList;
bool g_bCommandListLoaded;

Handle g_DB;

char g_sMapName[64];
int g_PlayerID[MAXPLAYERS+1];
Handle g_MapList;
Handle g_hDbMapNameList;
Handle g_hDbMapIdList;
bool g_bDbMapsLoaded;
float g_fMapStart;

float g_fSpamTime[MAXPLAYERS + 1];
float g_fJoinTime[MAXPLAYERS + 1];

// Chat
char g_msg_start[128] = {""};
char g_msg_varcol[128] = {"\x07B4D398"};
char g_msg_textcol[128] = {"\x01"};

// Forwards
Handle g_fwdMapIDPostCheck;
Handle g_fwdMapListLoaded;
Handle g_fwdPlayerIDLoaded;

// PlayerID retrieval data
Handle g_hPlayerID;
Handle g_hUser;
bool g_bPlayerListLoaded;

bool g_bPlayerWelcomed[MAXPLAYERS + 1] = {false, ...};

// Cvars
ConVar Cvar_ChangeLogURL;

public void OnPluginStart()
{
	DB_Connect();

	// Cvars
	Cvar_ChangeLogURL = CreateConVar("timer_changelog", "http://strafeodyssey.com/forums/archive/index.php?forum-5.html", "The URL to the timer changelog.");
	RegConsoleCmdEx("sm_changes", SM_Changes, "See the most recent BhopTimer changes on the server.");
	RegConsoleCmdEx("sm_changelog", SM_Changes, "See the most recent BhopTimer changes on the server.");

	AutoExecConfig(true, "core", "timer");

	// Events
	HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerInitialSpawn, EventHookMode_Post);

	// Commands
	RegConsoleCmdEx("sm_mostplayed", SM_TopMaps, "Displays the most played maps.");
	RegConsoleCmdEx("sm_lastplayed", SM_LastPlayed, "Shows the last played maps.");
	RegConsoleCmdEx("sm_playtime", SM_Playtime, "Shows the people who played the most.");
	RegConsoleCmdEx("sm_timeplayed", SM_Playtime, "Shows the people who played the most.");
	RegConsoleCmdEx("sm_thelp", SM_THelp, "Shows the timer commands.");
	RegConsoleCmdEx("sm_timerhelp", SM_THelp, "Shows the timer commands.");
	RegConsoleCmdEx("sm_commands", SM_THelp, "Shows the timer commands.");
	RegConsoleCmdEx("sm_search", SM_Search, "Search the command list for the given string of text.");

	// Makes FindTarget() work properly
	LoadTranslations("common.phrases");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("GetClientID", Native_GetClientID);
	CreateNative("IsSpamming", Native_IsSpamming);
	CreateNative("SetIsSpamming", Native_SetIsSpamming);
	CreateNative("RegisterCommand", Native_RegisterCommand);
	CreateNative("GetMapIdFromMapName", Native_GetMapIdFromMapName);
	CreateNative("GetMapNameFromMapId", Native_GetMapNameFromMapId);
	CreateNative("GetNameFromPlayerID", Native_GetNameFromPlayerID);
	CreateNative("GetSteamIDFromPlayerID", Native_GetSteamIDFromPlayerID);

	g_fwdMapIDPostCheck = CreateGlobalForward("OnMapIDPostCheck", ET_Event);
	g_fwdPlayerIDLoaded = CreateGlobalForward("OnPlayerIDLoaded", ET_Event, Param_Cell);
	g_fwdMapListLoaded  = CreateGlobalForward("OnDatabaseMapListLoaded", ET_Event);

	return APLRes_Success;
}

public void OnMapStart()
{
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));

	g_fMapStart = GetEngineTime();

	if(g_MapList != INVALID_HANDLE)
	{
		CloseHandle(g_MapList);
	}

	g_MapList = ReadMapList();

	// Creates map if it doesn't exist, sets map as recently played, and loads map playtime
	CreateCurrentMapID();
}

public void OnMapEnd()
{
	DB_SaveMapPlaytime();
	DB_SetMapLastPlayed();
}

public void OnClientAuthorized(int client, const char[] sAuth)
{
	if(!IsFakeClient(client) && g_bPlayerListLoaded == true)
	{
		CreatePlayerID(client);
	}
	g_fJoinTime[client] = GetEngineTime();
}

public void OnClientDisconnect(int client)
{
	// Save player's play time
	if(g_PlayerID[client] != 0 && !IsFakeClient(client))
	{
		DB_SavePlaytime(client);
	}

	// Reset the playerid for the client index
	g_PlayerID[client] = 0;

	g_bPlayerWelcomed[client] = false;
}

public void OnClientPostAdminCheck(int client){
	if(g_bPlayerWelcomed[client] == true)
		return;

	g_bPlayerWelcomed[client] = true;

	// This is the console welcome message
	#if !defined SERVER
	PrintToConsole(client, "\n\n\n\n================================================================================\n\n #######    #####     #####      ##      ########  ##     ##  #######  ########  \n##     ##  ##   ##   ##   ##   ####      ##     ## ##     ## ##     ## ##     ## \n       ## ##     ## ##     ##    ##      ##     ## ##     ## ##     ## ##     ## \n #######  ##     ## ##     ##    ##      ########  ######### ##     ## ########  \n##        ##     ## ##     ##    ##      ##     ## ##     ## ##     ## ##        \n##         ##   ##   ##   ##     ##      ##     ## ##     ## ##     ## ##        \n#########   #####     #####    ######    ########  ##     ##  #######  ##        \n\n================================================================================\n\n                        Welcome to 2001: A Strafe Odyssey!\n\n================================================================================\n\n\n");
	#endif
}

public void OnTimerChatChanged(int MessageType, char[] Message)
{
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

public Action Event_PlayerInitialSpawn(Handle event, const char[] name, bool dontBroadcast){
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if((0 < client <= MaxClients) && IsClientInGame(client) && (GetEventInt(event, "oldteam") == CS_TEAM_NONE)){
		// User is swapping from unassigned to a team. 'Initial' player spawn.

		#if !defined SERVER
			// Stupid Pexii doesn't want a welcome message.
			PrintColorText(client, "%s%sWelcome to %s2001: A Strafe Odyssey%s. Type %s!changes%s to see recent server updates.",
				g_msg_start, g_msg_textcol, g_msg_varcol, g_msg_textcol, g_msg_varcol, g_msg_textcol);
		#else

		#endif
	}
}

// Simple Chat Proccessor (Redux) Forwards
public Action OnChatMessage(int &author, Handle recipients, char[] name, char[] message){
	if(IsChatTrigger()){
		return Plugin_Stop;
	}

	return Plugin_Continue;
}


public Action SM_TopMaps(int client, int args)
{
	if(!IsSpamming(client))
	{
		SetIsSpamming(client, 1.0);

		char query[256];
		Format(query, sizeof(query), "SELECT MapName, MapPlaytime FROM maps ORDER BY MapPlaytime DESC");
		SQL_TQuery(g_DB, TopMaps_Callback, query, client);
	}

	return Plugin_Handled;
}

public TopMaps_Callback(Handle owner, Handle hndl, char[] error, any client)
{
	if(hndl != INVALID_HANDLE)
	{
		if(IsClientInGame(client))
		{
			Handle menu = CreateMenu(Menu_TopMaps);
			SetMenuTitle(menu, "Most played maps\n---------------------------------------");

			int rows = SQL_GetRowCount(hndl);
			if(rows > 0)
			{
				char mapname[64];
				char timeplayed[32];
				char display[128];
				int iTime;
				for(int i, j; i < rows; i++)
				{
					SQL_FetchRow(hndl);
					iTime = SQL_FetchInt(hndl, 1);

					if(iTime != 0)
					{
						SQL_FetchString(hndl, 0, mapname, sizeof(mapname));

						if(FindStringInArray(g_MapList, mapname) != -1)
						{
							FormatPlayerTime(float(iTime), timeplayed, sizeof(timeplayed), false, 1);
							SplitString(timeplayed, ".", timeplayed, sizeof(timeplayed));
							Format(display, sizeof(display), "#%d: %s - %s", ++j, mapname, timeplayed);

							AddMenuItem(menu, display, display);
						}
					}
				}

				SetMenuExitButton(menu, true);
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
			}
		}
	}
	else
	{
		LogError(error);
	}
}

public Menu_TopMaps(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		FakeClientCommand(param1, "sm_nominate %s", info);
	}
	else if(action == MenuAction_End)
		CloseHandle(menu);
}

public Action SM_LastPlayed(int client, int argS)
{
	if(!IsSpamming(client))
	{
		SetIsSpamming(client, 1.0);

		char query[256];
		Format(query, sizeof(query), "SELECT MapName, LastPlayed FROM maps ORDER BY LastPlayed DESC");
		SQL_TQuery(g_DB, LastPlayed_Callback, query, client);
	}

	return Plugin_Handled;
}

public LastPlayed_Callback(Handle owner, Handle hndl, char[] error, any client)
{
	if(hndl != INVALID_HANDLE)
	{
		if(IsClientInGame(client))
		{
			Handle menu = CreateMenu(Menu_LastPlayed);
			SetMenuTitle(menu, "Last played maps\n---------------------------------------");

			char sMapName[64];
			char sDate[32];
			char sTimeOfDay[32];
			char display[256];
			int iTime;

			int rows = SQL_GetRowCount(hndl);
			for(int i=1; i<=rows; i++)
			{
				SQL_FetchRow(hndl);
				iTime = SQL_FetchInt(hndl, 1);

				if(iTime != 0)
				{
					SQL_FetchString(hndl, 0, sMapName, sizeof(sMapName));

					if(FindStringInArray(g_MapList, sMapName) != -1)
					{
						FormatTime(sDate, sizeof(sDate), "%x", iTime);
						FormatTime(sTimeOfDay, sizeof(sTimeOfDay), "%X", iTime);

						Format(display, sizeof(display), "%s - %s - %s", sMapName, sDate, sTimeOfDay);

						AddMenuItem(menu, display, display);
					}
				}
			}

			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, MENU_TIME_FOREVER);
		}
	}
	else
	{
		LogError(error);
	}
}

public Menu_LastPlayed(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		FakeClientCommand(param1, "sm_nominate %s", info);
	}
	else if(action == MenuAction_End)
		CloseHandle(menu);
}

public Action Event_PlayerChangeName(Handle event, const char[] name, bool dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(!IsFakeClient(client) && g_PlayerID[client] != 0)
	{
		decl String:sNewName[MAX_NAME_LENGTH];
		GetEventString(event, "newname", sNewName, sizeof(sNewName));
		UpdateName(client, sNewName);
	}
}

public Action SM_Changes(int client, int args){
	char ChangeLogURL[PLATFORM_MAX_PATH];
	Cvar_ChangeLogURL.GetString(ChangeLogURL, sizeof(ChangeLogURL));

	ShowMOTDNotify(client, "Timer Change-log", ChangeLogURL, MOTDPANEL_TYPE_URL, false);


	return Plugin_Handled;
}

DB_Connect()
{
	if(g_DB != INVALID_HANDLE)
		CloseHandle(g_DB);

	char error[255];
	g_DB = SQL_Connect("timer", true, error, sizeof(error));

	if(g_DB == INVALID_HANDLE)
	{
		LogError(error);
		CloseHandle(g_DB);
	}
	else
	{
		char query[512];

		// Create maps table
		Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS maps(MapID INTEGER NOT NULL AUTO_INCREMENT, MapName TEXT, MapPlaytime INTEGER NOT NULL, LastPlayed INTEGER NOT NULL, PRIMARY KEY (MapID))");
		SQL_TQuery(g_DB, DB_Connect_Callback, query);

		// Create zones table
		Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS zones(RowID INTEGER NOT NULL AUTO_INCREMENT, MapID INTEGER, Type INTEGER, point00 REAL, point01 REAL, point02 REAL, point10 REAL, point11 REAL, point12 REAL, flags INTEGER, PRIMARY KEY (RowID))");
		SQL_TQuery(g_DB, DB_Connect_Callback, query);

		// Create players table
		Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS players(PlayerID INTEGER NOT NULL AUTO_INCREMENT, SteamID TEXT, User Text, Playtime INTEGER NOT NULL, ccname TEXT, ccmsgcol TEXT, ccuse INTEGER, PRIMARY KEY (PlayerID))");
		SQL_TQuery(g_DB, DB_Connect_Callback, query);

		// Create times table
		Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS times(rownum INTEGER NOT NULL AUTO_INCREMENT, MapID INTEGER, Type INTEGER, Style INTEGER, PlayerID INTEGER, Time REAL, Jumps INTEGER, Strafes INTEGER, Points REAL, Timestamp INTEGER, Sync REAL, SyncTwo REAL, PRIMARY KEY (rownum))");
		SQL_TQuery(g_DB, DB_Connect_Callback, query);

		LoadPlayers();
		LoadDatabaseMapList();
	}
}

public DB_Connect_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError(error);
	}
}

LoadDatabaseMapList()
{
	char query[256];
	FormatEx(query, sizeof(query), "SELECT MapID, MapName FROM maps");
	SQL_TQuery(g_DB, LoadDatabaseMapList_Callback, query);
}

public LoadDatabaseMapList_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl != INVALID_HANDLE)
	{
		if(g_bDbMapsLoaded == false)
		{
			g_hDbMapNameList = CreateArray(ByteCountToCells(64));
			g_hDbMapIdList   = CreateArray();
			g_bDbMapsLoaded  = true;
		}

		char sMapName[64];

		while(SQL_FetchRow(hndl))
		{
			SQL_FetchString(hndl, 1, sMapName, sizeof(sMapName));

			PushArrayString(g_hDbMapNameList, sMapName);
			PushArrayCell(g_hDbMapIdList, SQL_FetchInt(hndl, 0));
		}

		Call_StartForward(g_fwdMapListLoaded);
		Call_Finish();
	}
	else
	{
		LogError(error);
	}
}

LoadPlayers()
{
	g_hPlayerID = CreateArray(ByteCountToCells(32));
	g_hUser     = CreateArray(ByteCountToCells(MAX_NAME_LENGTH));

	char query[128];
	FormatEx(query, sizeof(query), "SELECT SteamID, PlayerID, User FROM players");
	SQL_TQuery(g_DB, LoadPlayers_Callback, query);
}

public LoadPlayers_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl != INVALID_HANDLE)
	{
		decl String:sName[32], String:sAuth[32];

		new RowCount = SQL_GetRowCount(hndl), PlayerID, iSize;
		for(new Row; Row < RowCount; Row++)
		{
			SQL_FetchRow(hndl);

			SQL_FetchString(hndl, 0, sAuth, sizeof(sAuth));
			PlayerID = SQL_FetchInt(hndl, 1);
			SQL_FetchString(hndl, 2, sName, sizeof(sName));

			iSize = GetArraySize(g_hPlayerID);

			if(PlayerID >= iSize)
			{
				ResizeArray(g_hPlayerID, PlayerID + 1);
				ResizeArray(g_hUser, PlayerID + 1);
			}

			SetArrayString(g_hPlayerID, PlayerID, sAuth);
			SetArrayString(g_hUser, PlayerID, sName);
		}

		g_bPlayerListLoaded = true;

		for(new client = 1; client <= MaxClients; client++)
		{
			if(IsClientConnected(client) && !IsFakeClient(client))
			{
				if(IsClientAuthorized(client) && IsClientInGame(client))
				{
					CreatePlayerID(client);
				}
			}
		}
	}
	else
	{
		LogError(error);
	}
}

CreateCurrentMapID()
{
	Handle pack = CreateDataPack();
	WritePackString(pack, g_sMapName);

	char query[512];
	FormatEx(query, sizeof(query), "INSERT INTO maps (MapName) SELECT * FROM (SELECT '%s') AS tmp WHERE NOT EXISTS (SELECT MapName FROM maps WHERE MapName = '%s') LIMIT 1",
		g_sMapName,
		g_sMapName);
	SQL_TQuery(g_DB, DB_CreateCurrentMapID_Callback, query, pack);
}

public DB_CreateCurrentMapID_Callback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		if(SQL_GetAffectedRows(hndl) > 0)
		{
			ResetPack(data);

			char sMapName[64];
			ReadPackString(data, sMapName, sizeof(sMapName));

			new MapID = SQL_GetInsertId(hndl);
			LogMessage("MapID for %s created (%d)", sMapName, MapID);

			if(g_bDbMapsLoaded == false)
			{
				g_hDbMapNameList = CreateArray(ByteCountToCells(64));
				g_hDbMapIdList   = CreateArray();
				g_bDbMapsLoaded  = true;
			}

			PushArrayString(g_hDbMapNameList, sMapName);
			PushArrayCell(g_hDbMapIdList, MapID);
		}

		Call_StartForward(g_fwdMapIDPostCheck);
		Call_Finish();
	}
	else
	{
		LogError(error);
	}

	CloseHandle(data);
}

CreatePlayerID(client)
{
	decl String:sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	decl String:sAuth[32];
	AuthId_Steam2(client, AuthId_Engine, String:sAuth, sizeof(sAuth));

	new idx = FindStringInArray(g_hPlayerID, sAuth);
	if(idx != -1)
	{
		g_PlayerID[client] = idx;

		decl String:sOldName[MAX_NAME_LENGTH];
		GetArrayString(g_hUser, idx, sOldName, sizeof(sOldName));

		if(!StrEqual(sName, sOldName))
		{
			UpdateName(client, sName);
		}

		Call_StartForward(g_fwdPlayerIDLoaded);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		decl String:sEscapeName[(2 * MAX_NAME_LENGTH) + 1];
		SQL_LockDatabase(g_DB);
		SQL_EscapeString(g_DB, sName, sEscapeName, sizeof(sEscapeName));
		SQL_UnlockDatabase(g_DB);

		new Handle:pack = CreateDataPack();
		WritePackCell(pack, GetClientUserId(client));
		WritePackString(pack, sAuth);
		WritePackString(pack, sName);

		decl String:query[128];
		FormatEx(query, sizeof(query), "INSERT INTO players (SteamID, User) VALUES ('%s', '%s')",
			sAuth,
			sEscapeName);
		SQL_TQuery(g_DB, CreatePlayerID_Callback, query, pack);
	}
}

public CreatePlayerID_Callback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		ResetPack(data);
		new client = GetClientOfUserId(ReadPackCell(data));

		decl String:sAuth[32];
		ReadPackString(data, sAuth, sizeof(sAuth));

		decl String:sName[MAX_NAME_LENGTH];
		ReadPackString(data, sName, sizeof(sName));

		new PlayerID = SQL_GetInsertId(hndl);

		new iSize = GetArraySize(g_hPlayerID);

		if(PlayerID >= iSize)
		{
			ResizeArray(g_hPlayerID, PlayerID + 1);
			ResizeArray(g_hUser, PlayerID + 1);
		}

		SetArrayString(g_hPlayerID, PlayerID, sAuth);
		SetArrayString(g_hUser, PlayerID, sName);

		if(client != 0)
		{
			g_PlayerID[client] = PlayerID;

			Call_StartForward(g_fwdPlayerIDLoaded);
			Call_PushCell(client);
			Call_Finish();
		}
	}
	else
	{
		LogError(error);
	}
}

UpdateName(client, const String:sName[])
{
	SetArrayString(g_hUser, g_PlayerID[client], sName);

	decl String:sEscapeName[(2 * MAX_NAME_LENGTH) + 1];
	SQL_LockDatabase(g_DB);
	SQL_EscapeString(g_DB, sName, sEscapeName, sizeof(sEscapeName));
	SQL_UnlockDatabase(g_DB);

	decl String:query[128];
	FormatEx(query, sizeof(query), "UPDATE players SET User='%s' WHERE PlayerID=%d",
		sEscapeName,
		g_PlayerID[client]);
	SQL_TQuery(g_DB, UpdateName_Callback, query);
}

public UpdateName_Callback(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	if(hndl == INVALID_HANDLE)
		LogError(error);
}

public Native_GetClientID(Handle:plugin, numParams)
{
	return g_PlayerID[GetNativeCell(1)];
}

DB_SavePlaytime(client)
{
	if(IsClientInGame(client))
	{
		new PlayerID = GetPlayerID(client);
		if(PlayerID != 0)
		{
			decl String:query[128];
			Format(query, sizeof(query), "UPDATE players SET Playtime=(SELECT Playtime FROM (SELECT * FROM players) AS x WHERE PlayerID=%d)+%d WHERE PlayerID=%d",
				PlayerID,
				RoundToFloor(GetEngineTime() - g_fJoinTime[client]),
				PlayerID);

			SQL_TQuery(g_DB, DB_SavePlaytime_Callback, query);
		}
	}
}

public DB_SavePlaytime_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
		LogError(error);
}

DB_SaveMapPlaytime()
{
	decl String:query[256];

	Format(query, sizeof(query), "UPDATE maps SET MapPlaytime=(SELECT MapPlaytime FROM (SELECT * FROM maps) AS x WHERE MapName='%s' LIMIT 0, 1)+%d WHERE MapName='%s'",
		g_sMapName,
		RoundToFloor(GetEngineTime()-g_fMapStart),
		g_sMapName);

	SQL_TQuery(g_DB, DB_SaveMapPlaytime_Callback, query);
}

public DB_SaveMapPlaytime_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
		LogError(error);
}

DB_SetMapLastPlayed()
{
	decl String:query[128];

	Format(query, sizeof(query), "UPDATE maps SET LastPlayed=%d WHERE MapName='%s'",
		GetTime(),
		g_sMapName);

	SQL_TQuery(g_DB, DB_SetMapLastPlayed_Callback, query);
}

public DB_SetMapLastPlayed_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
		LogError(error);
}

public Action:SM_Playtime(client, args)
{
	if(!IsSpamming(client))
	{
		SetIsSpamming(client, 1.0);

		if(args == 0)
		{
			if(g_PlayerID[client] != 0)
			{
				DB_ShowPlaytime(client, g_PlayerID[client]);
			}
		}
		else
		{
			decl String:sArg[MAX_NAME_LENGTH];
			GetCmdArgString(sArg, sizeof(sArg));

			new target = FindTarget(client, sArg, true, false);
			if(target != -1)
			{
				if(g_PlayerID[target] != 0)
				{
					DB_ShowPlaytime(client, g_PlayerID[target]);
				}
			}
		}
	}

	return Plugin_Handled;
}

DB_ShowPlaytime(client, PlayerID)
{
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, PlayerID);

	decl String:query[512];
	Format(query, sizeof(query), "SELECT (SELECT Playtime FROM players WHERE PlayerID=%d) AS TargetPlaytime, User, Playtime, PlayerID FROM players ORDER BY Playtime DESC LIMIT 0, 100",
		PlayerID);
	SQL_TQuery(g_DB, DB_ShowPlaytime_Callback, query, pack);
}

public DB_ShowPlaytime_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		ResetPack(data);
		new client = GetClientOfUserId(ReadPackCell(data));

		if(client != 0)
		{
			new rows = SQL_GetRowCount(hndl);
			if(rows != 0)
			{
				new TargetPlayerID = ReadPackCell(data);

				new Handle:menu = CreateMenu(Menu_ShowPlaytime);

				decl String:sName[MAX_NAME_LENGTH], String:sTime[32], String:sDisplay[64], String:sInfo[16], PlayTime, PlayerID, TargetPlaytime;
				for(new i = 1; i <= rows; i++)
				{
					SQL_FetchRow(hndl);

					TargetPlaytime = SQL_FetchInt(hndl, 0);
					SQL_FetchString(hndl, 1, sName, sizeof(sName));
					PlayTime = SQL_FetchInt(hndl, 2);
					PlayerID = SQL_FetchInt(hndl, 3);

					// Set info
					IntToString(PlayerID, sInfo, sizeof(sInfo));

					// Set display
					FormatPlayerTime(float(PlayTime), sTime, sizeof(sTime), false, 1);
					SplitString(sTime, ".", sTime, sizeof(sTime));
					FormatEx(sDisplay, sizeof(sDisplay), "#%d: %s: %s", i, sName, sTime);
					if(((i % 7) == 0 || i == rows))
						Format(sDisplay, sizeof(sDisplay), "%s\n--------------------------------------", sDisplay);

					// Add item
					AddMenuItem(menu, sInfo, sDisplay);
				}

				GetNameFromPlayerID(TargetPlayerID, sName, sizeof(sName));

				new Float:ConnectionTime, target;

				if((target = GetClientFromPlayerID(TargetPlayerID)) != 0)
				{
					ConnectionTime = GetEngineTime() - g_fJoinTime[target];
				}

				FormatPlayerTime(ConnectionTime + float(TargetPlaytime), sTime, sizeof(sTime), false, 1);
				SplitString(sTime, ".", sTime, sizeof(sTime));

				SetMenuTitle(menu, "Playtimes\n \n%s: %s\n--------------------------------------",
					sName,
					sTime);

				SetMenuExitButton(menu, true);
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
			}
		}
	}
	else
	{
		LogError(error);
	}
	CloseHandle(data);
}

public Menu_ShowPlaytime(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
		CloseHandle(menu);
}

public Action:SM_THelp(client, args)
{
	new iSize = GetArraySize(g_hCommandList);
	decl String:sResult[256];

	if(0 < client <= MaxClients)
	{
		if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
			ReplyToCommand(client, "[SM] Look in your console for timer command list.");

		decl String:sCommand[32];
		GetCmdArg(0, sCommand, sizeof(sCommand));

		if(args == 0)
		{
			ReplyToCommand(client, "[SM] %s 10 for the next page.", sCommand);
			for(new i=0; i<10 && i < iSize; i++)
			{
				GetArrayString(g_hCommandList, i, sResult, sizeof(sResult));
				PrintToConsole(client, sResult);
			}
		}
		else
		{
			decl String:arg[250];
			GetCmdArgString(arg, sizeof(arg));
			new iStart = StringToInt(arg);

			if(iStart < (iSize-10))
			{
				ReplyToCommand(client, "[SM] %s %d for the next page.", sCommand, iStart + 10);
			}

			for(new i = iStart; i < (iStart + 10) && (i < iSize); i++)
			{
				GetArrayString(g_hCommandList, i, sResult, sizeof(sResult));
				PrintToConsole(client, sResult);
			}
		}
	}
	else if(client == 0)
	{
		for(new i; i < iSize; i++)
		{
			GetArrayString(g_hCommandList, i, sResult, sizeof(sResult));
			PrintToServer(sResult);
		}
	}

	return Plugin_Handled;
}

public Action:SM_Search(client, args)
{
	if(args > 0)
	{
		decl String:sArgString[255], String:sResult[256];
		GetCmdArgString(sArgString, sizeof(sArgString));

		new iSize = GetArraySize(g_hCommandList);
		for(new i=0; i<iSize; i++)
		{
			GetArrayString(g_hCommandList, i, sResult, sizeof(sResult));
			if(StrContains(sResult, sArgString, false) != -1)
			{
				PrintToConsole(client, sResult);
			}
		}
	}
	else
	{
		PrintColorText(client, "%s%ssm_search must have a string to search with after it.",
			g_msg_start,
			g_msg_textcol);
	}

	return Plugin_Handled;
}

GetClientFromPlayerID(PlayerID)
{
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && !IsFakeClient(client) && g_PlayerID[client] == PlayerID)
		{
			return client;
		}
	}

	return 0;
}

public Native_IsSpamming(Handle:plugin, numParams)
{
	return GetEngineTime() < g_fSpamTime[GetNativeCell(1)];
}

public Native_SetIsSpamming(Handle:plugin, numParams)
{
	g_fSpamTime[GetNativeCell(1)] = Float:GetNativeCell(2) + GetEngineTime();
}

public Native_RegisterCommand(Handle:plugin, numParams)
{
	if(g_bCommandListLoaded == false)
	{
		g_hCommandList = CreateArray(ByteCountToCells(256));
		g_bCommandListLoaded = true;
	}

	decl String:sListing[256], String:sCommand[32], String:sDesc[224];

	GetNativeString(1, sCommand, sizeof(sCommand));
	GetNativeString(2, sDesc, sizeof(sDesc));

	FormatEx(sListing, sizeof(sListing), "%s - %s", sCommand, sDesc);

	decl String:sIndex[256];
	new idx, idxlen, listlen = strlen(sListing), iSize = GetArraySize(g_hCommandList), bool:IdxFound;
	for(; idx < iSize; idx++)
	{
		GetArrayString(g_hCommandList, idx, sIndex, sizeof(sIndex));
		idxlen = strlen(sIndex);

		for(new cmpidx = 0; cmpidx < listlen && cmpidx < idxlen; cmpidx++)
		{
			if(sListing[cmpidx] < sIndex[cmpidx])
			{
				IdxFound = true;
				break;
			}
			else if(sListing[cmpidx] > sIndex[cmpidx])
			{
				break;
			}
		}

		if(IdxFound == true)
			break;
	}

	if(idx >= iSize)
		ResizeArray(g_hCommandList, idx + 1);
	else
		ShiftArrayUp(g_hCommandList, idx);

	SetArrayString(g_hCommandList, idx, sListing);
}

public Native_GetMapNameFromMapId(Handle:plugin, numParams)
{
	new Index = FindValueInArray(g_hDbMapIdList, GetNativeCell(1));

	if(Index != -1)
	{
		decl String:sMapName[64];
		GetArrayString(g_hDbMapNameList, Index, sMapName, sizeof(sMapName));
		SetNativeString(2, sMapName, GetNativeCell(3));

		return true;
	}
	else
	{
		return false;
	}
}

public Native_GetNameFromPlayerID(Handle:plugin, numParams)
{
	decl String:sName[MAX_NAME_LENGTH];

	GetArrayString(g_hUser, GetNativeCell(1), sName, sizeof(sName));

	SetNativeString(2, sName, GetNativeCell(3));
}

public Native_GetSteamIDFromPlayerID(Handle:plugin, numParams)
{
	decl String:sAuth[32];

	GetArrayString(g_hPlayerID, GetNativeCell(1), sAuth, sizeof(sAuth));

	SetNativeString(2, sAuth, GetNativeCell(3));
}

public Native_GetMapIdFromMapName(Handle:plugin, numParams)
{
	decl String:sMapName[64];
	GetNativeString(1, sMapName, sizeof(sMapName));

	new Index = FindStringInArray(g_hDbMapNameList, sMapName);

	if(Index != -1)
	{
		return GetArrayCell(g_hDbMapIdList, Index);
	}
	else
	{
		return 0;
	}
}
