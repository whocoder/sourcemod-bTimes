#pragma semicolon 1

#include <bTimes-core>

public Plugin:myinfo =
{
	name = "[bTimes] Ghost",
	author = "blacky",
	description = "Shows a bot that replays the top times, fuck my butt",
	version = VERSION,
	url = URL
}

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <smlib/weapons>
#include <smlib/entities>
#include <cstrike>
#include <bTimes-timer>
#include <bTimes-random>

new	String:g_sMapName[64],
	Handle:g_DB;

new 	Handle:g_hFrame[MAXPLAYERS + 1],
	bool:g_bUsedFrame[MAXPLAYERS + 1];

new 	Handle:g_hGhost[MAX_TYPES][MAX_STYLES],
	g_Ghost[MAX_TYPES][MAX_STYLES],
	g_GhostFrame[MAX_TYPES][MAX_STYLES],
	bool:g_GhostPaused[MAX_TYPES][MAX_STYLES],
	String:g_sGhost[MAX_TYPES][MAX_STYLES][48],
	g_GhostPlayerID[MAX_TYPES][MAX_STYLES],
	Float:g_fGhostTime[MAX_TYPES][MAX_STYLES],
	Float:g_fPauseTime[MAX_TYPES][MAX_STYLES],
	g_iBotQuota,
	bool:g_bGhostLoadedOnce[MAX_TYPES][MAX_STYLES],
	bool:g_bGhostLoaded[MAX_TYPES][MAX_STYLES];

new 	Float:g_fStartTime[MAX_TYPES][MAX_STYLES];

// Cvars
new	Handle:g_hGhostClanTag[MAX_TYPES][MAX_STYLES],
	Handle:g_hGhostWeapon[MAX_TYPES][MAX_STYLES],
	Handle:g_hGhostStartPauseTime,
	Handle:g_hGhostEndPauseTime;

// Weapon control
bool g_bNewWeapon;

bool g_bGameEnded;
bool g_PausedAtEnd[MAX_TYPES][MAX_STYLES];

Handle g_hGhostCheck;

public OnPluginStart(){
	if(GetGameType() != GameType_CSGO && GetGameType() != GameType_CSS)
		SetFailState("This timer does not support this game (%d)", GetGameType());

	// Connect to the database
	DB_Connect();

	g_hGhostStartPauseTime = CreateConVar("timer_ghoststartpause", "5.0", "How long the ghost will pause before starting its run.");
	g_hGhostEndPauseTime   = CreateConVar("timer_ghostendpause", "2.0", "How long the ghost will pause after it finishes its run.");

	AutoExecConfig(true, "ghost", "timer");

	// Events
	HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Pre);
	if(GetGameType() == GameType_CSGO){
		HookEvent("game_end", Event_GameEnd, EventHookMode_Pre);
	}
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);

	//HookEvent("player_spawn", Event_PlayerSpawnPre, EventHookMode_Pre);

	// Create admin command that deletes the ghost
	RegAdminCmd("sm_deleteghost", SM_DeleteGhost, ADMFLAG_CUSTOM5, "Deletes the ghost.");

	new Handle:hBotDontShoot = FindConVar("bot_dont_shoot");
	SetConVarFlags(hBotDontShoot, GetConVarFlags(hBotDontShoot) & ~FCVAR_CHEAT);


	HookUserMessage(GetUserMessageId("SayText2"), UserMessageHook_SayText2, true);
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("GetBotInfo", Native_GetBotInfo);

	RegPluginLibrary("ghost");

	return APLRes_Success;
}

public OnStylesLoaded()
{
	decl String:sTypeAbbr[8], String:sType[16], String:sStyleAbbr[8], String:sStyle[16], String:sTypeStyleAbbr[24], String:sCvar[32], String:sDesc[128], String:sValue[32];

	for(new Type; Type < MAX_TYPES; Type++)
	{
		GetTypeName(Type, sType, sizeof(sType));
		GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr));

		for(new Style; Style < MAX_STYLES; Style++)
		{
			// Don't create cvars for styles on bonus except normal style
			if(Style_CanUseReplay(Style, Type))
			{
				GetStyleName(Style, sStyle, sizeof(sStyle));
				GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr));

				Format(sTypeStyleAbbr, sizeof(sTypeStyleAbbr), "%s%s", sTypeAbbr, sStyleAbbr);
				StringToUpper(sTypeStyleAbbr);

				Format(sCvar, sizeof(sCvar), "timer_ghosttag_%s%s", sTypeAbbr, sStyleAbbr);
				Format(sDesc, sizeof(sDesc), "The replay bot's clan tag for the scoreboard (%s style on %s timer)", sStyle, sType);
				Format(sValue, sizeof(sValue), "Ghost :: %s", sTypeStyleAbbr);
				g_hGhostClanTag[Type][Style] = CreateConVar(sCvar, sValue, sDesc);

				Format(sCvar, sizeof(sCvar), "timer_ghostweapon_%s%s", sTypeAbbr, sStyleAbbr);
				Format(sDesc, sizeof(sDesc), "The weapon the replay bot will always use (%s style on %s timer)", sStyle, sType);
				g_hGhostWeapon[Type][Style] = CreateConVar(sCvar, "weapon_glock", sDesc, 0, true, 0.0, true, 1.0);

				HookConVarChange(g_hGhostWeapon[Type][Style], OnGhostWeaponChanged);

				g_hGhost[Type][Style] = CreateArray(6);
			}
		}
	}
}

public Native_GetBotInfo(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);

	if(!IsFakeClient(client))
		return false;

	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style < MAX_STYLES; Style++)
		{
			if(Style_CanUseReplay(Style, Type))
			{
				if(g_Ghost[Type][Style] == client)
				{
					SetNativeCellRef(2, Type);
					SetNativeCellRef(3, Style);

					return true;
				}
			}
		}
	}

	return false;
}

public OnMapStart(){
	g_bGameEnded = false;
	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style < MAX_STYLES; Style++)
		{
			if(Style_CanUseReplay(Style, Type))
			{
				ClearArray(g_hGhost[Type][Style]);
				g_Ghost[Type][Style]  = 0;
				g_fGhostTime[Type][Style] = 0.0;
				g_GhostFrame[Type][Style] = 0;
				g_PausedAtEnd[Type][Style] = false;
				g_GhostPlayerID[Type][Style] = 0;
				g_bGhostLoaded[Type][Style] = false;
				Format(g_sGhost[Type][Style], sizeof(g_sGhost[][]), "No record");
			}
		}
	}

	// Get map name to use the database
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));

	// Check path to folder that holds all the ghost data
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes");
	if(!DirExists(sPath))
	{
		// Create ghost data directory if it doesn't exist
		CreateDirectory(sPath, 511);
	}

	// Timer to check ghost things such as clan tag
	g_hGhostCheck = CreateTimer(0.25, GhostCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public OnZonesLoaded()
{
	LoadGhost();
}

public OnConfigsExecuted()
{
	CalculateBotQuota();
}

public OnUseGhostChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	CalculateBotQuota();
}

public OnGhostWeaponChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style < MAX_STYLES; Style++)
		{
			if(0 < g_Ghost[Type][Style] <= MaxClients && Style_CanUseReplay(Style, Type))
			{
				if(g_hGhostWeapon[Type][Style] == convar)
				{
					CheckWeapons(Type, Style);
				}
			}
		}
	}
}

public OnMapEnd()
{
	g_bGameEnded = true;
	// Remove ghost to get a clean start next map
	ServerCommand("bot_kick all");

	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style < MAX_STYLES; Style++)
		{
			g_Ghost[Type][Style] = 0;
		}
	}

	if(g_hGhostCheck != INVALID_HANDLE)
		KillTimer(g_hGhostCheck);
}

public OnClientPutInServer(client)
{
	if(IsFakeClient(client))
	{
		SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	}
	else
	{
		// Reset player recorded movement
		if(g_bUsedFrame[client] == false)
		{
			g_hFrame[client]     = CreateArray(6);
			g_bUsedFrame[client] = true;
		}
		else
		{
			ClearArray(g_hFrame[client]);
		}
	}
}

public OnEntityCreated(entity, const String:classname[])
{
	if(StrContains(classname, "trigger_", false) != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, OnTrigger);
		SDKHook(entity, SDKHook_EndTouch, OnTrigger);
		SDKHook(entity, SDKHook_Touch, OnTrigger);
	}

	if(IsValidEntity(entity) && strcmp(classname, "player", false) == 0 && IsClientConnected(entity) && IsFakeClient(entity)){
		SDKHook(entity, SDKHook_Spawn, Event_PlayerSpawnPre);
	}
}

public Action:OnTrigger(entity, other)
{
	if(0 < other <= MaxClients)
	{
		if(IsClientConnected(other))
		{
			if(IsFakeClient(other))
			{
				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

public OnPlayerIDLoaded(client)
{
	new PlayerID = GetPlayerID(client);

	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style < MAX_STYLES; Style++)
		{
			if(Style_CanUseReplay(Style, Type))
			{
				if(PlayerID == g_GhostPlayerID[Type][Style])
				{
					decl String:sTime[32];
					FormatPlayerTime(g_fGhostTime[Type][Style], sTime, sizeof(sTime), false, 0);

					decl String:sName[20];
					GetClientName(client, sName, sizeof(sName));

					FormatEx(g_sGhost[Type][Style], sizeof(g_sGhost[][]), "%s", sName, sTime);
				}
			}
		}
	}
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
	// Find out if it's the bot added from another time
	if(IsFakeClient(client) && !IsClientSourceTV(client))
	{
		for(new Type; Type < MAX_TYPES; Type++)
		{
			for(new Style; Style < MAX_STYLES; Style++)
			{
				if(g_Ghost[Type][Style] == 0)
				{
					if(Style_CanUseReplay(Style, Type))
					{
						g_Ghost[Type][Style] = client;

						return true;
					}
				}
			}
		}
	}
	return true;
}

public OnClientDisconnect(client)
{
	// Prevent players from becoming the ghost.
	if(IsFakeClient(client))
	{
		for(new Type; Type < MAX_TYPES; Type++)
		{
			for(new Style; Style < MAX_STYLES; Style++)
			{
				if(Style_CanUseReplay(Style, Type))
				{
					if(client == g_Ghost[Type][Style])
					{
						g_Ghost[Type][Style] = 0;
						break;
					}
				}
			}
		}
	}
}

public OnTimesDeleted(Type, Style, RecordOne, RecordTwo, Handle:Times)
{
	new iSize = GetArraySize(Times);

	if(RecordTwo <= iSize)
	{
		for(new idx = RecordOne - 1; idx < RecordTwo; idx++)
		{
			if(GetArrayCell(Times, idx) == g_GhostPlayerID[Type][Style])
			{
				DeleteGhost(Type, Style);
				break;
			}
		}
	}
}

public Action:Event_PlayerChangeName(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(IsClientInGame(client))
	{
		new PlayerID = GetPlayerID(client);

		if(PlayerID != 0)
		{
			for(new Type; Type < MAX_TYPES; Type++)
			{
				for(new Style; Style < MAX_STYLES; Style++)
				{
					if(Style_CanUseReplay(Style, Type))
					{
						if(PlayerID == g_GhostPlayerID[Type][Style])
						{
							decl String:sNewName[20];
							GetEventString(event, "newname", sNewName, sizeof(sNewName));
							decl String:sOldName[20];
							GetEventString(event, "oldname", sOldName, sizeof(sOldName));

							new Handle:pack;
							CreateDataTimer(0.1, Timer_ChangeName, pack);
							WritePackCell(pack, Type);
							WritePackCell(pack, Style);
							WritePackString(pack, sNewName);
						}
					}
				}
			}
		}
	}

	return Plugin_Continue;
}

public Action:Timer_ChangeName(Handle:timer, Handle:data){
	ResetPack(data);

	new Type  = ReadPackCell(data);
	new Style = ReadPackCell(data);

	decl String:sName[MAX_NAME_LENGTH];
	ReadPackString(data, sName, sizeof(sName));

	decl String:sTime[32];
	FormatPlayerTime(g_fGhostTime[Type][Style], sTime, sizeof(sTime), false, 0);

	Format(g_sGhost[Type][Style], sizeof(g_sGhost[][]), "%s", sName);
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(IsFakeClient(client))
	{

		decl String:clName[48];
		GetClientName(client, clName, sizeof(clName));
		SetEntProp(client, Prop_Data, "m_iFrags", 420);
		SetEntProp(client, Prop_Data, "m_iDeaths", -420);

		for(new Type; Type < MAX_TYPES; Type++)
		{
			for(new Style; Style < MAX_STYLES; Style++)
			{
				if(Style_CanUseReplay(Style, Type))
				{
					if(g_Ghost[Type][Style] == client)
					{
						decl String:stTime[32];
						FormatPlayerTime(g_fGhostTime[Type][Style], stTime, sizeof(stTime), false, 0);
						if(g_fGhostTime[Type][Style] == 0.0 || g_bGhostLoaded[Type][Style] == false){
							return Plugin_Handled;
						}else{
							if(GetGameType() == GameType_CSS)
								CreateTimer(0.1, Timer_CheckWeapons, client);
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action:Event_PlayerSpawnPre(client){
	if(IsClientConnected(client) && IsFakeClient(client)){
		decl String:clName[48];
		GetClientName(client, clName, sizeof(clName));

		for(new Type; Type < MAX_TYPES; Type++)
		{
			for(new Style; Style < MAX_STYLES; Style++)
			{
				if(Style_CanUseReplay(Style, Type))
				{
					if(g_Ghost[Type][Style] == client)
					{
						SetEntProp(client, Prop_Data, "m_iFrags", 420);
						SetEntProp(client, Prop_Data, "m_iDeaths", -420);
						decl String:stTime[32];
						FormatPlayerTime(g_fGhostTime[Type][Style], stTime, sizeof(stTime), false, 0);
						if(g_fGhostTime[Type][Style] == 0.0 || g_bGhostLoaded[Type][Style] == false){
							AcceptEntityInput(client, "Kill");
							return Plugin_Handled;
						}else{
							if(GetGameType() == GameType_CSS)
								CreateTimer(0.1, Timer_CheckWeapons, client);
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action:Timer_CheckWeapons(Handle:timer, any:client)
{
	if(client != 0 && IsClientConnected(client) && IsFakeClient(client)){

		for(new Type; Type < MAX_TYPES; Type++)
		{
			for(new Style; Style < MAX_STYLES; Style++)
			{
				if(Style_CanUseReplay(Style, Type))
				{
					if(g_Ghost[Type][Style] != 0 && g_Ghost[Type][Style] == client && IsClientConnected(client) && IsPlayerAlive(client)){
						CheckWeapons(Type, Style);
					}
				}
			}
		}
	}
}
ClearWeaponSlot(any client, any slot){
	new weaponIndex;
	if((weaponIndex = GetPlayerWeaponSlot(client, slot)) != -1)
		RemovePlayerItem(client, weaponIndex); }

CheckWeapons(Type, Style)
{
	if(g_Ghost[Type][Style] != 0 && IsClientConnected(g_Ghost[Type][Style]) && IsPlayerAlive(g_Ghost[Type][Style])){
		for(new i = 0; i < 8; i++)
		{
			ClearWeaponSlot(g_hGhostWeapon[Type][Style], CS_SLOT_PRIMARY);
			ClearWeaponSlot(g_hGhostWeapon[Type][Style], CS_SLOT_SECONDARY);
			ClearWeaponSlot(g_hGhostWeapon[Type][Style], CS_SLOT_KNIFE);

			decl String:sWeapon[32];
			GetConVarString(g_hGhostWeapon[Type][Style], sWeapon, sizeof(sWeapon));

			g_bNewWeapon = true;
			GivePlayerItem(g_Ghost[Type][Style], sWeapon);
		}
	}
}

public Action:SM_DeleteGhost(client, args)
{
	OpenDeleteGhostMenu(client);

	return Plugin_Handled;
}

OpenDeleteGhostMenu(client)
{
	new Handle:menu = CreateMenu(Menu_DeleteGhost);

	SetMenuTitle(menu, "Select ghost to delete");

	decl String:sDisplay[64], String:sType[32], String:sStyle[32], String:sInfo[8];

	for(new Type; Type < MAX_TYPES; Type++)
	{
		GetTypeName(Type, sType, sizeof(sType));

		for(new Style; Style < MAX_STYLES; Style++)
		{
			if(Style_CanUseReplay(Style, Type))
			{
				GetStyleName(Style, sStyle, sizeof(sStyle));
				FormatEx(sDisplay, sizeof(sDisplay), "%s (%s)", sType, sStyle);
				Format(sInfo, sizeof(sInfo), "%d;%d", Type, Style);
				AddMenuItem(menu, sInfo, sDisplay);
			}
		}
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Menu_DeleteGhost(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[16], String:sTypeStyle[2][8];
		GetMenuItem(menu, param2, info, sizeof(info));

		if(StrContains(info, ";") != -1)
		{
			ExplodeString(info, ";", sTypeStyle, 2, 8);

			DeleteGhost(StringToInt(sTypeStyle[0]), StringToInt(sTypeStyle[1]));

			LogMessage("%L deleted the ghost", param1);
		}
	}
	else if (action == MenuAction_End)
		CloseHandle(menu);
}

public Action:GhostCheck(Handle:timer, any:data)
{
	if(g_bGameEnded == false)
	{
		new Handle:hBotQuota = FindConVar("bot_quota");
		new iBotQuota = GetConVarInt(hBotQuota);

		if(iBotQuota != g_iBotQuota)
			ServerCommand("bot_quota %d", g_iBotQuota);

		CloseHandle(hBotQuota);

		for(new Type; Type < MAX_TYPES; Type++)
		{
			for(new Style; Style < MAX_STYLES; Style++)
			{
				if(Style_CanUseReplay(Style, Type))
				{
					if(g_Ghost[Type][Style] != 0)
					{
						if(IsClientInGame(g_Ghost[Type][Style]))
						{
							// Check clan tag
							decl String:sClanTag[64], String:sCvarClanTag[64];
							CS_GetClientClanTag(g_Ghost[Type][Style], sClanTag, sizeof(sClanTag));
							if(g_hGhostClanTag[Type][Style] != INVALID_HANDLE){
								GetConVarString(g_hGhostClanTag[Type][Style], sCvarClanTag, sizeof(sCvarClanTag));

								if(!StrEqual(sCvarClanTag, sClanTag))
									CS_SetClientClanTag(g_Ghost[Type][Style], sCvarClanTag);
							}

							if(strlen(g_sGhost[Type][Style]) > 0)
							{
								decl String:sGhostname[48];
								GetClientName(g_Ghost[Type][Style], sGhostname, sizeof(sGhostname));

								decl String:sStyleName[16];
								GetStyleName(Style, sStyleName, sizeof(sStyleName));

								decl String:sTime[32];
								FormatPlayerTime(g_fGhostTime[Type][Style], sTime, sizeof(sTime), false, 0);

								decl String:sTypeAbbr[8];
								GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr));

								decl String:sNewN[32];

								if(StringToInt(sTime) == 0)
									sTime = "No record";

								if(Type == 1){
									if(StrEqual(sStyleName, "Normal"))
										Format(sNewN, sizeof(sNewN), "%s - %s", "Bonus", sTime);
									else
										Format(sNewN, sizeof(sNewN), "%s %s - %s", "Bonus", sStyleName, sTime);
								} else {
									Format(sNewN, sizeof(sNewN), "%s - %s", sStyleName, sTime);}

								if(!StrEqual(sGhostname, sNewN))
								{
									if(GetGameType() == GameType_CSS)
										SetClientInfo(g_Ghost[Type][Style], "name", sNewN);
									else
										SetClientName(g_Ghost[Type][Style], sNewN);
								}
							}

							// Check if ghost is dead
							decl String:stTime[32];
							FormatPlayerTime(g_fGhostTime[Type][Style], stTime, sizeof(stTime), false, 0);
							if((IsPlayerAlive(g_Ghost[Type][Style])) && (StringToInt(stTime) == 0)){
								ForcePlayerSuicide(g_Ghost[Type][Style]);
							}else{
								if((StringToInt(stTime) != 0) && !IsPlayerAlive(g_Ghost[Type][Style])){
									CS_RespawnPlayer(g_Ghost[Type][Style]);}
							}

							// Display ghost's current time to spectators
							if(g_hGhost[Type][Style] != INVALID_HANDLE){
								new iSize = GetArraySize(g_hGhost[Type][Style]);
								for(new client = 1; client <= MaxClients; client++)
								{
									if(IsClientInGame(client))
									{
										if(!IsPlayerAlive(client))
										{
											new target 	 = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
											new ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

											if(target == g_Ghost[Type][Style] && (ObserverMode == 4 || ObserverMode == 5))
											{
												if(!(GetGameType() == GameType_CSGO && (GetClientSettings(client) & SHOW_KEYS))){
													if(!g_GhostPaused[Type][Style] && (0 < g_GhostFrame[Type][Style] < iSize)){
														new Float:time = GetEngineTime() - g_fStartTime[Type][Style];
														new String:sTime[32];

														if(GetGameType() == GameType_CSGO)
															FormatPlayerTime(time, sTime, sizeof(sTime), false, 0, true);
														else
															FormatPlayerTime(time, sTime, sizeof(sTime), false, 0);

														decl String:sType[32];
														decl String:sStyle[32];
														GetTypeName(Type, sType, sizeof(sType));
														GetStyleName(Style, sStyle, sizeof(sStyle));

														if(Type != TIMER_MAIN && Style != 0){
															FormatEx(sStyle, sizeof(sStyle), "%s %s", sType, sStyle);
														}else if(Type != TIMER_MAIN && Style == 0){
															FormatEx(sStyle, sizeof(sStyle), "%s", sType);
														}else{
															FormatEx(sStyle, sizeof(sStyle), "%s", sStyle);
														}

														decl String:sSteamID[32];
														GetSteamIDFromPlayerID(g_GhostPlayerID[Type][Style], sSteamID, sizeof(sSteamID));
														if(strlen(sSteamID) < 6)
															FormatEx(sSteamID, sizeof(sSteamID), "%d", g_GhostPlayerID);

														ReplaceString(sSteamID, sizeof(sSteamID), "STEAM_1:", "");
														ReplaceString(sSteamID, sizeof(sSteamID), "STEAM_0:", "");
														#if defined SERVER
														PrintHintGameText(client, "Replay - %s\nPlayer: %s\nTime: %s\nSpeed: %d",
																sStyle,
																g_sGhost[Type][Style],
																sTime,
																RoundToFloor(GetClientVelocity(g_Ghost[Type][Style], true, true, (GetClientSettings(target) & SHOW_2DVEL) == 0)));
														#else
														if(GetGameType() == GameType_CSS)
															PrintHintGameText(client, "[ Replay - %s ]\nSteam: %s\nPlayer: %s\nTime: %s\nVelo: %d",
																sStyle,
																sSteamID,
																g_sGhost[Type][Style],
																sTime,
																RoundToFloor(GetClientVelocity(g_Ghost[Type][Style], true, true, (GetClientSettings(target) & SHOW_2DVEL) == 0)));
														else if(GetGameType() == GameType_CSGO)
															PrintHintGameText(client, "<strong>%s Replay</strong>\nPlayer: %s\nSteam: %s\nTime: <font color='#990033'>%s</font>		Velo: %d",
																sStyle,
																g_sGhost[Type][Style],
																sSteamID,
																sTime,
																RoundToFloor(GetClientVelocity(g_Ghost[Type][Style], true, true, (GetClientSettings(target) & SHOW_2DVEL) == 0)));
														#endif
													}else{
														if(Style_CanUseReplay(Style, Type) && !g_PausedAtEnd[Type][Style])
															g_GhostFrame[Type][Style] = 0;
													}
												}
											}
										}
									}
								}
							}
							if(GetGameType() == GameType_CSS){
								new weaponIndex = GetEntPropEnt(g_Ghost[Type][Style], Prop_Send, "m_hActiveWeapon");

								if(weaponIndex != -1)
								{
									new ammo = Weapon_GetPrimaryClip(weaponIndex);

									if(ammo < 1)
										Weapon_SetPrimaryClip(weaponIndex, 9999);
								}
							}
							// maybe move this bracket down later
							new botFrags = GetEntProp(g_Ghost[Type][Style], Prop_Data, "m_iFrags");
							new botDeaths = GetEntProp(g_Ghost[Type][Style], Prop_Data, "m_iDeaths");

							if(botFrags != 420 || botDeaths != -420){
								SetEntProp(g_Ghost[Type][Style], Prop_Data, "m_iFrags", 420);
								SetEntProp(g_Ghost[Type][Style], Prop_Data, "m_iDeaths", -420);
							}
						}
					}
				}
			}
		}
	}
}

public Action:Hook_WeaponCanUse(client, weapon)
{
	if(g_bNewWeapon == false)
		return Plugin_Handled;

	g_bNewWeapon = false;

	return Plugin_Continue;
}

CalculateBotQuota()
{
	g_iBotQuota = 0;

	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style<MAX_STYLES; Style++)
		{
			if(Style_CanUseReplay(Style, Type))
			{
				g_iBotQuota++;

				if(!g_Ghost[Type][Style])
					ServerCommand("bot_add");
			}
			else if(g_Ghost[Type][Style])
				KickClient(g_Ghost[Type][Style]);
		}
	}

	new Handle:hBotQuota = FindConVar("bot_quota");
	new iBotQuota = GetConVarInt(hBotQuota);

	if(iBotQuota != g_iBotQuota)
		ServerCommand("bot_quota %d", g_iBotQuota);

	CloseHandle(hBotQuota);
}

LoadGhost()
{
	// Rename old version files
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s.rec", g_sMapName);
	if(FileExists(sPath))
	{
		decl String:sPathTwo[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sPathTwo, sizeof(sPathTwo), "data/btimes/%s_0_0.rec", g_sMapName);
		RenameFile(sPathTwo, sPath);
	}

	for(new Type; Type < MAX_TYPES; Type++)
	{
		for(new Style; Style < MAX_STYLES; Style++)
		{
			if(Style_CanUseReplay(Style, Type))
			{
				g_fGhostTime[Type][Style]    = 0.0;
				g_GhostPlayerID[Type][Style] = 0;

				BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d.rec", g_sMapName, Type, Style);

				if(FileExists(sPath))
				{
					// Open file for reading
					new Handle:hFile = OpenFile(sPath, "r");

					// Load all data into the ghost handle
					new String:line[512], String:expLine[6][64], String:expLine2[2][10];
					new iSize = 0;

					ReadFileLine(hFile, line, sizeof(line));
					ExplodeString(line, "|", expLine2, 2, 10);
					g_GhostPlayerID[Type][Style] = StringToInt(expLine2[0]);
					g_fGhostTime[Type][Style]    = StringToFloat(expLine2[1]);

					while(!IsEndOfFile(hFile))
					{
						ReadFileLine(hFile, line, sizeof(line));
						ExplodeString(line, "|", expLine, 6, 64);

						iSize = GetArraySize(g_hGhost[Type][Style]) + 1;
						ResizeArray(g_hGhost[Type][Style], iSize);
						SetArrayCell(g_hGhost[Type][Style], iSize - 1, StringToFloat(expLine[0]), 0);
						SetArrayCell(g_hGhost[Type][Style], iSize - 1, StringToFloat(expLine[1]), 1);
						SetArrayCell(g_hGhost[Type][Style], iSize - 1, StringToFloat(expLine[2]), 2);
						SetArrayCell(g_hGhost[Type][Style], iSize - 1, StringToFloat(expLine[3]), 3);
						SetArrayCell(g_hGhost[Type][Style], iSize - 1, StringToFloat(expLine[4]), 4);
						SetArrayCell(g_hGhost[Type][Style], iSize - 1, StringToInt(expLine[5]), 5);
					}
					CloseHandle(hFile);

					g_bGhostLoadedOnce[Type][Style] = true;

					new Handle:pack = CreateDataPack();
					WritePackCell(pack, Type);
					WritePackCell(pack, Style);
					WritePackString(pack, g_sMapName);

					// Query for name/time of player the ghost is following the path of
					decl String:query[512];
					Format(query, sizeof(query), "SELECT t2.User, t1.Time FROM times AS t1, players AS t2 WHERE t1.PlayerID=t2.PlayerID AND t1.PlayerID=%d AND t1.MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t1.Type=%d AND t1.Style=%d",
						g_GhostPlayerID[Type][Style],
						g_sMapName,
						Type,
						Style);
					SQL_TQuery(g_DB, LoadGhost_Callback, query, pack);
				}
				else
				{
					g_bGhostLoaded[Type][Style] = true;
				}
			}
		}
	}
}

public LoadGhost_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		ResetPack(data);
		new Type  = ReadPackCell(data);
		new Style = ReadPackCell(data);

		decl String:sMapName[64];
		ReadPackString(data, sMapName, sizeof(sMapName));

		if(StrEqual(g_sMapName, sMapName))
		{
			if(SQL_GetRowCount(hndl) != 0)
			{
				SQL_FetchRow(hndl);

				decl String:sName[20];
				SQL_FetchString(hndl, 0, sName, sizeof(sName));

				if(g_fGhostTime[Type][Style] == 0.0)
					g_fGhostTime[Type][Style] = SQL_FetchFloat(hndl, 1);

				// if(StrEqual(g_cGhostName[Type][Style], ""))
					// g_cGhostName[Type][Style] = sName;

				decl String:sTime[32];
				FormatPlayerTime(g_fGhostTime[Type][Style], sTime, sizeof(sTime), false, 0);

				Format(g_sGhost[Type][Style], sizeof(g_sGhost[][]), "%s", sName);
			}

			g_bGhostLoaded[Type][Style] = true;
		}
	}
	else
	{
		LogError(error);
	}

	CloseHandle(data);
}

public OnTimerStart_Post(client, Type, Style)
{
	// Reset saved ghost data
	ClearArray(g_hFrame[client]);
}

public OnTimerFinished_Post(client, Float:Time, Type, Style, bool:NewTime, OldPosition, NewPosition)
{
	if(g_bGhostLoaded[Type][Style] == true)
	{
		if(Style_CanReplaySave(Style, Type))
		{
			if(Time < g_fGhostTime[Type][Style] || g_fGhostTime[Type][Style] == 0.0)
			{
				SaveGhost(client, Time, Type, Style);
			}
		}
	}
}

SaveGhost(client, Float:Time, Type, Style)
{
	g_fGhostTime[Type][Style] = Time;

	g_GhostPlayerID[Type][Style] = GetPlayerID(client);

	// Delete existing ghost for the map
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d.rec", g_sMapName, Type, Style);
	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	// Open a file for writing
	new Handle:hFile = OpenFile(sPath, "w");

	// save playerid to file to grab name and time for later times map is played
	decl String:playerid[16];
	IntToString(GetPlayerID(client), playerid, sizeof(playerid));
	WriteFileLine(hFile, "%d|%f", GetPlayerID(client), Time);

	new iSize = GetArraySize(g_hFrame[client]);
	decl String:buffer[512];
	new Float:data[5], buttons;

	ClearArray(g_hGhost[Type][Style]);
	for(new i=0; i<iSize; i++)
	{
		GetArrayArray(g_hFrame[client], i, data, 5);
		PushArrayArray(g_hGhost[Type][Style], data, 5);

		buttons = GetArrayCell(g_hFrame[client], i, 5);
		SetArrayCell(g_hGhost[Type][Style], i, buttons, 5);

		FormatEx(buffer, sizeof(buffer), "%f|%f|%f|%f|%f|%d", data[0], data[1], data[2], data[3], data[4], buttons);
		WriteFileLine(hFile, buffer);
	}
	CloseHandle(hFile);

	g_GhostFrame[Type][Style] = 0;

	decl String:name[20], String:sTime[32];
	GetClientName(client, name, sizeof(name));
	FormatPlayerTime(g_fGhostTime[Type][Style], sTime, sizeof(sTime), false, 0);
	Format(g_sGhost[Type][Style], sizeof(g_sGhost[][]), "%s", name);
}

DeleteGhost(Type, Style)
{
	// delete map ghost file
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d.rec", g_sMapName, Type, Style);
	if(FileExists(sPath))
		DeleteFile(sPath);

	// reset ghost
	if(g_Ghost[Type][Style] != 0)
	{
		g_fGhostTime[Type][Style] = 0.0;
		ClearArray(g_hGhost[Type][Style]);
		if(g_bGameEnded == false)
			CS_RespawnPlayer(g_Ghost[Type][Style]);
	}
}

DB_Connect()
{
	if(g_DB != INVALID_HANDLE)
		CloseHandle(g_DB);

	decl String:error[255];
	g_DB = SQL_Connect("timer", true, error, sizeof(error));

	if(g_DB == INVALID_HANDLE)
	{
		LogError(error);
		CloseHandle(g_DB);
	}
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if(IsPlayerAlive(client))
	{
		if(!IsFakeClient(client))
		{
			new Type = GetClientTimerType(client);
			new Style = GetClientStyle(client);
			if(IsBeingTimed(client, TIMER_ANY) && !IsTimerPaused(client) && Style_CanReplaySave(Style, Type))
			{
				// Record player movement data
				new iSize = GetArraySize(g_hFrame[client]);
				ResizeArray(g_hFrame[client], iSize + 1);

				new Float:vPos[3], Float:vAng[3];
				Entity_GetAbsOrigin(client, vPos);
				GetClientEyeAngles(client, vAng);

				SetArrayCell(g_hFrame[client], iSize, vPos[0], 0);
				SetArrayCell(g_hFrame[client], iSize, vPos[1], 1);
				SetArrayCell(g_hFrame[client], iSize, vPos[2], 2);
				SetArrayCell(g_hFrame[client], iSize, vAng[0], 3);
				SetArrayCell(g_hFrame[client], iSize, vAng[1], 4);
				SetArrayCell(g_hFrame[client], iSize, buttons, 5);
			}
		}
		else
		{
			if(g_bGameEnded == false)
			{
				for(new Type; Type < MAX_TYPES; Type++)
				{
					for(new Style; Style < MAX_STYLES; Style++)
					{
						if(client == g_Ghost[Type][Style] && g_hGhost[Type][Style] != INVALID_HANDLE)
						{
							new iSize = GetArraySize(g_hGhost[Type][Style]);

							new Float:vPos[3], Float:vAng[3];

							new Float:time = GetEngineTime() - g_fStartTime[Type][Style];
							new String:sTime[32];
							FormatPlayerTime(time, sTime, sizeof(sTime), false, 0);

							if(g_GhostFrame[Type][Style] > 1 && time >= g_fGhostTime[Type][Style]){
								g_GhostFrame[Type][Style] = (iSize - 1);
							}
							if(g_GhostFrame[Type][Style] == 0)
							{
								g_PausedAtEnd[Type][Style] = false;
								g_fStartTime[Type][Style] = GetEngineTime();

								if(iSize > 0)
								{
									vPos[0] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 0);
									vPos[1] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 1);
									vPos[2] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 2);
									vAng[0] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 3);
									vAng[1] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 4);
									TeleportEntity(g_Ghost[Type][Style], vPos, vAng, Float:{0.0, 0.0, 0.0});
								}

								if(g_GhostPaused[Type][Style] == false)
								{
									g_GhostPaused[Type][Style] = true;
									g_fPauseTime[Type][Style]  = GetEngineTime();
								}

								if(GetEngineTime() > g_fPauseTime[Type][Style] + GetConVarFloat(g_hGhostStartPauseTime))
								{
									g_GhostPaused[Type][Style] = false;
									g_GhostFrame[Type][Style]++;
								}
							}
							else if(g_GhostFrame[Type][Style] >= (iSize - 1))
							{
								if(iSize > 0)
								{
									vPos[0] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 0);
									vPos[1] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 1);
									vPos[2] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 2);
									vAng[0] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 3);
									vAng[1] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 4);

									TeleportEntity(g_Ghost[Type][Style], vPos, vAng, Float:{0.0, 0.0, 0.0});
								}

								if(g_GhostPaused[Type][Style] == false)
								{
									g_GhostPaused[Type][Style] = true;
									g_PausedAtEnd[Type][Style] = true;
									g_fPauseTime[Type][Style]  = GetEngineTime();
								}

								if(GetEngineTime() > g_fPauseTime[Type][Style] + GetConVarFloat(g_hGhostEndPauseTime) && iSize > 0)
								{
									g_GhostPaused[Type][Style] = false;
									g_GhostFrame[Type][Style]  = 0;
								}
							}
							else if(g_GhostFrame[Type][Style] < iSize)
							{
								g_PausedAtEnd[Type][Style] = false;
								new Float:vPos2[3];
								Entity_GetAbsOrigin(client, vPos2);

								vPos[0] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 0);
								vPos[1] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 1);
								vPos[2] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 2);
								vAng[0] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 3);
								vAng[1] = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 4);
								buttons = GetArrayCell(g_hGhost[Type][Style], g_GhostFrame[Type][Style], 5);

								if(GetGameType() == GameType_CSGO && (buttons & IN_DUCK))
									buttons &= ~IN_DUCK;

								if(GetVectorDistance(vPos, vPos2) > 50.0)
								{
									TeleportEntity(g_Ghost[Type][Style], vPos, vAng, NULL_VECTOR);
								}
								else
								{
									// Get the new velocity from the the 2 points
									new Float:vVel[3];
									MakeVectorFromPoints(vPos2, vPos, vVel);
									ScaleVector(vVel, 100.0);

									TeleportEntity(g_Ghost[Type][Style], NULL_VECTOR, vAng, vVel);
								}

								if(GetEntityFlags(client) & FL_ONGROUND && GetGameType() == GameType_CSS){
									if(GetEntityMoveType(g_Ghost[Type][Style]) != MOVETYPE_WALK)
										SetEntityMoveType(g_Ghost[Type][Style], MOVETYPE_WALK);
								}else{
									if(GetEntityMoveType(g_Ghost[Type][Style]) != MOVETYPE_NOCLIP)
										SetEntityMoveType(g_Ghost[Type][Style], MOVETYPE_NOCLIP);
								}

								g_GhostFrame[Type][Style] = (g_GhostFrame[Type][Style] + 1) % iSize;
							}

							if(g_GhostPaused[Type][Style] == true)
							{
								if(GetEntityMoveType(g_Ghost[Type][Style]) != MOVETYPE_NONE)
									SetEntityMoveType(g_Ghost[Type][Style], MOVETYPE_NONE);
							}
						}
					}
				}
			}
		}
	}

	return Plugin_Changed;
}

public Action Event_GameEnd(Handle event, const char[] name, bool EventBroadcast){
	g_bGameEnded = true;

	return Plugin_Continue;
}

public Action UserMessageHook_SayText2(UserMsg msg_hd, Handle bf, const int [] players, int playersNum, bool reliable, bool init)
{
	char UserMessage[96];
	Action returnaction = Plugin_Continue;

	if(GetUserMessageType() == UM_Protobuf)
	{
		PbReadString(bf, "msg_name", UserMessage, sizeof(UserMessage));
		if(StrContains(UserMessage, "Name_Change") != -1)
			returnaction = Plugin_Handled;
	}

	if(GetUserMessageType() == UM_BitBuf){
		BfReadString(bf, UserMessage, sizeof(UserMessage));
		BfReadString(bf, UserMessage, sizeof(UserMessage));
		if(StrContains(UserMessage, "Name_Change") != -1)
		{
			//BfReadString(bf, UserMessage, sizeof(UserMessage));
			//if(StrContains(UserMessage, "No record") != -1)
			returnaction = Plugin_Handled;
		}
	}

	return returnaction;
}
