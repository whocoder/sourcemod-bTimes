#include <sourcemod>
#include <sdktools>
#include <bTimes-core>
#include <bTimes-timer>
#include <smlib/entities>

#define MAX_FRAMES 40
#define TURN_LEFT 0
#define TURN_RIGHT 1

#define MOVE_LEFT 0
#define MOVE_RIGHT 1

new	Float:g_fOldAngle[MAXPLAYERS + 1],
	Float:g_fLastMove[MAXPLAYERS + 1],
	g_LastMove[MAXPLAYERS + 1];

new	g_TotalSync[MAXPLAYERS + 1],
	g_GoodSync[MAXPLAYERS + 1][2];
	
new	g_Tick[MAXPLAYERS + 1];

new	g_LastTurnDir[MAXPLAYERS + 1],
	g_LastTurnTime[MAXPLAYERS + 1],
	bool:g_Turned[MAXPLAYERS + 1][2];
	
new	g_LastMoveTime[MAXPLAYERS + 1],
	g_LastMoveDir[MAXPLAYERS + 1];

new	g_Frames[MAXPLAYERS + 1][MAX_FRAMES],
	g_CurrentFrame[MAXPLAYERS + 1],
	bool:g_UsedFrame[MAXPLAYERS + 1][MAX_FRAMES];
	
new g_Notifications[MAXPLAYERS + 1];
	
new	String:g_sLogFile[PLATFORM_MAX_PATH];

ConVar Cvar_Bans_Enabled;
ConVar Cvar_Bans_Amount;
ConVar Cvar_Bans_Length;
ConVar Cvar_Bans_ServerURL;

Handle g_hTimer;

public Plugin:myinfo = {
	name = "[bTimes] BASH",
	author = "blacky, cam",
	description = "Detects strafe hacks based on methods from LJStats and other.",
	version = VERSION,
	url = URL
}

public OnPluginStart(){
	Cvar_Bans_Enabled 	= CreateConVar("timer_bash_bans_enabled", "0", "Enables or disables automatic bans", _, true, 0.0, true, 1.0);
	Cvar_Bans_Amount	= CreateConVar("timer_bash_bans_amount", "10", "If bans are enabled, determines how many BASH notifications before automatic ban (during one map)", _, true, 5.0, true, 30.0);
	Cvar_Bans_Length	= CreateConVar("timer_bash_bans_length", "0", "If bans are enabled, determines how long automatic bans should be (in minutes)", _, true, 0.0, false);
	
	Cvar_Bans_ServerURL = CreateConVar("timer_bash_bans_url", "strafeodyssey.com", "Set the link to display in the kick message");
	
	AutoExecConfig(true, "bash", "timer");

	RegAdminCmd("bash_stats", Bash_Stats, ADMFLAG_GENERIC, "Check a player's strafe stats");
	
	BuildPath(Path_SM, g_sLogFile, PLATFORM_MAX_PATH, "logs/bTimes-BASH.txt");
}

public OnMapStart(){
	g_hTimer = CreateTimer(30.0, Timer_BashCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	for(new client = 1; client <= MaxClients; client++){
		if(IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
			g_Notifications[client] = 0;
	}
}

public OnMapEnd(){
	for(new client = 1; client <= MaxClients; client++){
		if(IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
			g_Notifications[client] = 0;
	}
	
	if(g_hTimer != 	INVALID_HANDLE)
		KillTimer(g_hTimer);
}

public OnClientPutInServer(client)
{
	for(new frame; frame < MAX_FRAMES; frame++)
	{
		g_Frames[client][frame]     = 0;
		g_UsedFrame[client][frame]  = false;
	}
	
	g_CurrentFrame[client] = 0;
	g_Tick[client] = 0;
	g_Notifications[client] = 0;
}

public Action:Bash_Stats(client, args)
{
	if(args)
	{
		decl String:sArg[MAX_NAME_LENGTH];
		GetCmdArgString(sArg, MAX_NAME_LENGTH);
		if(StrEqual(sArg, "@spec", false))
		{
			if(!IsPlayerAlive(client))
			{
				new target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
				if(0 < target <= MaxClients)
				{
					ShowBashStats(client, target);
				}
				else
				{
					ReplyToCommand(client, "[BASH] You are not spectating anyone.");
				}
			}
			else
			{
				ReplyToCommand(client, "[BASH] You can't be alive to use the @spec argument.");
			}
		}
		else
		{
			if(sArg[0] == '#')
			{
				ReplaceString(sArg, MAX_NAME_LENGTH, "#", "", true);
				new target = GetClientOfUserId(StringToInt(sArg, 10));
				if(target)
				{
					ShowBashStats(client, target);
				}
				else
				{
					ReplyToCommand(client, "[BASH] No player with userid '%s'.", sArg);
				}
			}
			
			decl String:sName[MAX_NAME_LENGTH];
			new bool:bFoundTarget;
			for(new target = 1; target <= MaxClients; target++)
			{
				if (IsClientInGame(target))
				{
					GetClientName(target, sName, MAX_NAME_LENGTH);
					if (StrContains(sName, sArg, false) != -1)
					{
						bFoundTarget = true;
						ShowBashStats(client, target);
					}
				}
			}
			
			if(!bFoundTarget)
			{
				ReplyToCommand(client, "[BASH] No player found with '%s' in their name.", sArg);
			}
		}
	}
	else
	{
		for(new target = 1; target <= MaxClients; target++)
		{
			if((client != 0) && (IsClientInGame(client)))
			{
				ShowBashStats(client, target);
			}
		}
	}
	
	return Plugin_Handled;
}

public Action:Timer_BashCheck(Handle:timer, any:data)
{
	decl String:sSuspectReason[128];
	
	new bool:Suspected;
	for(new client = 1; client <= MaxClients; client++)
	{
		if ((client != 0) && (IsClientInGame(client)))
		{
			if (g_TotalSync[client] > 2000 && UsedAllFrames(client))
			{
				Suspected = false;
				
				new PerfectStrafes = 0, StrafesOverZero = 0;
				AnalyzeStrafes(client, PerfectStrafes, StrafesOverZero);
				
				if(PerfectStrafes >= 33){
					Suspected = true;
					FormatEx(sSuspectReason, sizeof(sSuspectReason), "Too many perfect strafes.");
				}
				
				if(StrafesOverZero == MAX_FRAMES){
					Suspected = true;
					FormatEx(sSuspectReason, sizeof(sSuspectReason), "Too many strafes over zero.");
				}
				
				if(GetGameType() != GameType_CSGO && (GetClientSync(client, 1) - GetClientSync(client, 0)) > 15.0){
					Suspected = true;
					FormatEx(sSuspectReason, sizeof(sSuspectReason), "Sync 2 much higher than Sync 1.");
				}
				
				if(GetClientSync(client, 0) > (GetClientSync(client, 1) + 1.0)){
					Suspected = true;
					FormatEx(sSuspectReason, sizeof(sSuspectReason), "Sync 1 higher than Sync 2.");
				}
				
				if(Suspected == true){
					g_Notifications[client]++;
					SuspectPlayerMessage(client, sSuspectReason);
				}
				
				g_TotalSync[client]   = 0;
				g_GoodSync[client][0] = 0;
				g_GoodSync[client][1] = 0;
			}
		}
	}
	
	DoAutomaticBans();
}

bool:UsedAllFrames(client)
{
	new UsedFramesCount;
	
	for(new frame = 0; frame < MAX_FRAMES; frame++)
	{
		if(g_UsedFrame[client][frame] == true)
		{
			UsedFramesCount++;
		}
	}
	
	return UsedFramesCount == MAX_FRAMES;
}

AnalyzeStrafes(client, &PerfectCount, &StrafesOverZero)
{
	for(new frame = 0; frame < MAX_FRAMES; frame++)
	{
		if(-1 <= g_Frames[client][frame] <= 1)
		{
			PerfectCount++;
		}
		
		if(g_Frames[client][frame] >= 0)
		{
			StrafesOverZero++;
		}
	}
}

SuspectPlayerMessage(target, const String:reason[])
{
	decl String:sMessage[256];
	Format(sMessage, sizeof(sMessage), "[BASH] %N is suspected of using a strafe hack. (%s)", target, reason);
	LogToFile(g_sLogFile, sMessage);
	
	new String:sBashStats[256];
	GetBashStatsMessage(target, sBashStats, sizeof(sBashStats));
	LogToFile(g_sLogFile, sBashStats);
	
	for(new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			if(GetAdminFlag(GetUserAdmin(client), Admin_Generic, Access_Effective))
			{
				PrintToChat(client, sMessage);
				PrintToConsole(client, sBashStats);
				
				
			}
		}
	}
}

ShowBashStats(client, target)
{
	new String:sStats[256];
	GetBashStatsMessage(target, sStats, sizeof(sStats));
	ReplyToCommand(client, sStats);
}

GetBashStatsMessage(target, String:message[], maxlen)
{
	for(new frame = 0; frame < MAX_FRAMES; frame++)
	{
		if (g_UsedFrame[target][frame] == true)
		{
			Format(message, maxlen, "%s%d ", message, g_Frames[target][frame]);
		}
		else
		{
			Format(message, maxlen, "%s- ", message);
		}
	}
	new String:playerIP[64];
	GetClientIP(target, playerIP, sizeof(playerIP));
	Format(message, maxlen, "\n \n[BASH] Stats for %L<%s> | Sync 1: %.2f | Sync 2: %.2f \n%s", target, playerIP, GetClientSync(target, 0), GetClientSync(target, 1), message);



}

Float:GetClientSync(client, syncNum)
{
	if(g_TotalSync[client] > 0.0)
	{
		return float(g_GoodSync[client][syncNum]) / float(g_TotalSync[client]) * 100;
	}
	
	return 0.0;
}

VectorAngles(Float:vel[3], Float:angles[3])
{
	new Float:tmp, Float:yaw, Float:pitch;
	
	if (vel[1] == 0 && vel[0] == 0)
	{
		yaw = 0.0;
		if (vel[2] > 0)
			pitch = 270.0;
		else
			pitch = 90.0;
	}
	else
	{
		yaw = (ArcTangent2(vel[1], vel[0]) * (180 / 3.141593));
		if (yaw < 0)
			yaw += 360;

		tmp = SquareRoot(vel[0]*vel[0] + vel[1]*vel[1]);
		pitch = (ArcTangent2(-vel[2], tmp) * (180 / 3.141593));
		if (pitch < 0)
			pitch += 360;
	}
	
	angles[0] = pitch;
	angles[1] = yaw;
	angles[2] = 0.0;
}

GetDirection(client)
{
	new Float:vVel[3];
	Entity_GetAbsVelocity(client, vVel);
	
	new Float:vAngles[3];
	GetClientEyeAngles(client, vAngles);
	new Float:fTempAngle = vAngles[1];
	VectorAngles(vVel, vAngles);

	if(fTempAngle < 0)
		fTempAngle += 360;

	new Float:fTempAngle2 = fTempAngle - vAngles[1];

	if(fTempAngle2 < 0)
		fTempAngle2 = -fTempAngle2;
	
	if(fTempAngle2 < 22.5 || fTempAngle2 > 337.5)
		return 1; // Forwards
	if(fTempAngle2 > 22.5 && fTempAngle2 < 67.5 || fTempAngle2 > 292.5 && fTempAngle2 < 337.5 )
		return 2; // Half-sideways
	if(fTempAngle2 > 67.5 && fTempAngle2 < 112.5 || fTempAngle2 > 247.5 && fTempAngle2 < 292.5)
		return 3; // Sideways
	if(fTempAngle2 > 112.5 && fTempAngle2 < 157.5 || fTempAngle2 > 202.5 && fTempAngle2 < 247.5)
		return 4; // Backwards Half-sideways
	if(fTempAngle2 > 157.5 && fTempAngle2 < 202.5)
		return 5; // Backwards
	
	return 0; // Unknown
}

CheckSync(client, buttons, Float:vel[3], Float:fAngleDiff)
{
	new Direction = GetDirection(client);
	
	if(Direction == 1 && GetClientVelocity(client, true, true, false) != 0)
	{	
		new flags = GetEntityFlags(client);
		new MoveType:movetype = GetEntityMoveType(client);
		if(!(flags & (FL_ONGROUND|FL_INWATER)) && (movetype != MOVETYPE_LADDER))
		{			
			// Add to good sync if client buttons match up
			if(fAngleDiff > 0)
			{
				g_TotalSync[client]++;
				if((buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
				{
					g_GoodSync[client][0]++;
				}
				if(vel[1] < 0)
				{
					g_GoodSync[client][1]++;
				}
			}
			else if(fAngleDiff < 0)
			{
				g_TotalSync[client]++;
				if((buttons & IN_MOVERIGHT) && !(buttons & IN_MOVELEFT))
				{
					g_GoodSync[client][0]++;
				}
				if(vel[1] > 0)
				{
					g_GoodSync[client][1]++;
				}
			}
		}
	}
}

CheckIfTurned(client, Float:fAngleDiff)
{
	if(fAngleDiff > 0)
	{
		if(g_LastTurnDir[client] == TURN_RIGHT)
		{
			// Turned left
			ClientTurned(client, TURN_LEFT);
		}
	}
	else if(fAngleDiff < 0)
	{
		if(g_LastTurnDir[client] == TURN_LEFT)
		{
			// Turned right
			ClientTurned(client, TURN_RIGHT);
		}
	}
}

ClientTurned(client, TurnDirection)
{
	g_LastTurnDir[client]                     = TurnDirection;
	g_LastTurnTime[client]                    = g_Tick[client];
	g_Turned[client][TurnDirection]           = true;
	g_Turned[client][(TurnDirection + 1) % 2] = false;
	
	if(g_LastMoveDir[client] == TurnDirection)
	{
		new difference = g_LastMoveTime[client] - g_LastTurnTime[client];
		if (-20 <= difference <= 20)
		{
			g_Frames[client][g_CurrentFrame[client]] = difference;
			g_UsedFrame[client][g_CurrentFrame[client]] = true;
			g_CurrentFrame[client] = (g_CurrentFrame[client] + 1) % MAX_FRAMES;
		}
	}
}

CheckIfSwitchedKeys(client, Float:SideMove)
{	
	new Move;
	if(SideMove < 0)
		Move = TURN_LEFT;
	else
		Move = TURN_RIGHT;
	
	if(SideMove != 0)
	{
		if(g_fLastMove[client] == 0 || g_LastMove[client] != Move)
		{			
			if(SideMove < 0)
				g_LastMoveDir[client] = MOVE_LEFT;
			if(SideMove > 0)
				g_LastMoveDir[client] = MOVE_RIGHT;
			
			g_LastMoveTime[client] = g_Tick[client];
			
			ClientSwitchedKeys(client);
		}
	}
	
	g_fLastMove[client] = SideMove;
	g_LastMove[client]  = Move;
}

ClientSwitchedKeys(client)
{
	if(g_Turned[client][g_LastMoveDir[client]] == true)
	{
		new difference = g_LastMoveTime[client] - g_LastTurnTime[client];
		if (-20 <= difference <= 20)
		{
			g_Frames[client][g_CurrentFrame[client]] = difference;
			g_UsedFrame[client][g_CurrentFrame[client]] = true;
			g_CurrentFrame[client] = (g_CurrentFrame[client] + 1) % MAX_FRAMES;
		}
	}
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if(!IsFakeClient(client))
	{
		new Float:fAngleDiff = angles[1] - g_fOldAngle[client];
		if (fAngleDiff > 180)
			fAngleDiff -= 360;
		else if(fAngleDiff < -180)
			fAngleDiff += 360;
		
		g_fOldAngle[client] = angles[1];
		
		if(IsPlayerAlive(client) && !(GetEntityFlags(client) & (FL_ONGROUND|FL_INWATER)) && Style_CalculateStrafeStats(GetClientStyle(client))){
			g_Tick[client]++;
			CheckIfTurned(client, fAngleDiff);
			CheckIfSwitchedKeys(client, vel[1]);
			CheckSync(client, buttons, vel, fAngleDiff);
		}
	}
}

DoAutomaticBans(){
	char server_website[64];
	char cSteamID[32];
	
	if(Cvar_Bans_Enabled.BoolValue || Cvar_Bans_Enabled.IntValue > 0 || Cvar_Bans_Enabled.FloatValue > 0.0){
		Cvar_Bans_ServerURL.GetString(server_website, sizeof(server_website));
		for(int client = 1; client <= MaxClients; client++){
			if(IsClientConnected(client) && IsClientInGame(client) && g_Notifications[client] > 0){
				if(g_Notifications[client] > Cvar_Bans_Amount.IntValue || g_Notifications[client] > Cvar_Bans_Amount.FloatValue){
					GetClientAuthId(client, AuthId_Steam2, cSteamID, sizeof(cSteamID));
					
					ServerCommand("sm_addban %d %s [BASH] Automated ban", Cvar_Bans_Length.IntValue, cSteamID);
					
					KickClient(client, "[BASH] Automated ban, check %s for more info.", server_website);
				}
			}
		}
	}
}