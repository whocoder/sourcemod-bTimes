#include <sourcemod>
#include <bTimes-core>
#include <bTimes-random>
#include <cstrike>

#define ADVERT_INTERVAL 120.0
#pragma semicolon 1

char CurrentMapName[64];

char ServerAdvertisements[][] = {
	"%s%sType %s!selfies%s in chat to see user-submitted images of themselves.",
	"%s%sBe sure to register on our %sforums%s to participate in exclusive events and %sgive-aways%s!",
	"%s%sIs there a %snew map%s that you want added? Let us know on the %sforums%s!",
	"%s%sYou can type %s!webstats%s or %s!leaderboard%s in chat to view the Timer-Stats home page for this game.",
	"%s%sOur %sminimum donation%s is only %s$5 USD%s and gives you %s2 months%s of donator perks!",
	"%s%sIf you want to disable %sads/announcements%s in chat, you can type %s!ads%s or %s!toggleads%s to toggle!",
	"%s%sSpectators %sdo not count%s in Rock The Vote unless they already voted!",
	"%s%sTyping %s!hide%s may improve %sFPS%s by hiding other players and silencing their footsteps.",
	"%s%sTo %sdonate%s visit %sstrafeodyssey.com/donate%s or type %s!donate%s in chat!",
	"%s%sSign up for our %sforums%s at %sstrafeodyssey.com%s.",
	"%s%sType %s!webwr%s (or %s!webmap%s / %s!webtime%s) in chat to view the Timer-Stats web-page for a map.",
	"%s%sType %s!user%s or %s!webuser%s in chat to view the Timer-Stats web-page for a user.",
	"%s%sDonators get to make %scustom names%s with %sspecial colors%s instead of their rank.",
	"%s%sType %s!webbans%s or %s!bans%s in chat to view the %sSourceBans%s page in-game.",
	"%s%sOur server runs %scustom%s, %sexclusive%s server-side %santi-cheats%s to help keep things fair.",
	"%s%sVisit our website at %sstrafeodyssey.com%s to view the Timer-Stats website and other useful links.",
	"%s%sYou can type %s!practice%s (or %s!p%s / %s!nc%s) in chat to noclip (fly)!",
	"%s%sJoin our %ssteam group%s! Type %s!group / !steam%s or visit %sstrafeodyssey.com%s for a direct link!",
	"%s%sTo be eligible for a %sgive-away%s, you must have at least %s12 hours%s on %s!playtime%s and %s20%% %smap completion.",
	"%s%sYou can type %s!youtube%s (or %s!videos%s / %s!wrvids%s) to open the %sStrafeOdysseyRuns%s YouTube channel!",
	"%s%sHave a %ssuggestion%s for the server? Let us know by participating on our %sforums%s!",
	"%s%sYou can type %s!speclist%s (or %s!specs%s / %s!specinfo%s) to view your spectators." };

int ServerAdsCount = 0;
int CurrentAdvertisement = 0;

bool g_bGameEnded = false;

char g_msg_pre[128] = {""};
char g_msg_var[128] = {""};
char g_msg_msg[128] = {""};

public Plugin myinfo = {
	name = "[bTimes] Web-Link",
	description = "Linking the server to the website.",
	author = "cam",
	version = VERSION,
	url = URL
}

public void OnPluginStart(){
	for(new i = 0; i < (sizeof(ServerAdvertisements)); i++){
		ServerAdsCount++;
	}

	// Leaderboard Home/Recent
	RegConsoleCmd("sm_webstats", Leaderboard);
	RegConsoleCmd("sm_leaderboard", Leaderboard);

	// Leaderboard Maps (and Times)
	RegConsoleCmd("sm_webwr", LeaderboardMap);
	RegConsoleCmd("sm_webmap", LeaderboardMap);
	RegConsoleCmd("sm_webtime", LeaderboardMap);

	// Leaderboard Users
	RegConsoleCmd("sm_user", LeaderboardUser);
	RegConsoleCmd("sm_webuser", LeaderboardUser);

	// Leaderboard Selfies
	RegConsoleCmd("sm_selfies", LeaderboardSelfies);
	RegConsoleCmd("sm_selfie", LeaderboardSelfies);
	RegConsoleCmd("sm_webselfies", LeaderboardSelfies);
	RegConsoleCmd("sm_webselfie", LeaderboardSelfies);

	// SourceBans Home-Page
	RegConsoleCmd("sm_bans", SourceBansWeb);
	RegConsoleCmd("sm_webbans", SourceBansWeb);

	// Steam Group Shortcuts
	RegConsoleCmd("sm_group", SteamGroupWeb);
	RegConsoleCmd("sm_steamgroup", SteamGroupWeb);
	RegConsoleCmd("sm_steam", SteamGroupWeb);

	// Donations
	RegConsoleCmd("sm_donate", DonateWeb);
	RegConsoleCmd("sm_donations", DonateWeb);

	// Motd/Help
	RegConsoleCmd("sm_webhelp", HelpWeb);
	//RegConsoleCmd("sm_motd", MOTDWeb);
	RegConsoleCmd("sm_rules", MOTDWeb);

	RegConsoleCmd("sm_ads", ToggleAds);
	RegConsoleCmd("sm_toggleads", ToggleAds);

	RegConsoleCmd("sm_youtube", OpenYouTubePage);
	RegConsoleCmd("sm_videos", OpenYouTubePage);
	RegConsoleCmd("sm_wrvids", OpenYouTubePage);

	AddCommandListener(Command_MOTD, "motd");
}

public OnMapStart(){
	g_bGameEnded = false;

	GetCurrentMap(CurrentMapName, sizeof(CurrentMapName));

	// Create the timer for Advertisements
	CreateTimer(ADVERT_INTERVAL, Timer_DisplayAds, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public OnMapEnd(){
	g_bGameEnded = true;
}

public OnConfigsExecuted(){
	CopyTimerPrintData();
}

public Action:ToggleAds(client, args){
	SetClientSettings(client, GetClientSettings(client) ^ IGNORE_ADVERTS);

	if(GetClientSettings(client) & IGNORE_ADVERTS)
		PrintColorText(client, "%s%sAdvertisements have been %sdisabled%s.", g_msg_pre, g_msg_msg, g_msg_var, g_msg_msg);
	else
		PrintColorText(client, "%s%sAdvertisements have been %senabled%s.", g_msg_pre, g_msg_msg, g_msg_var, g_msg_msg);

	return Plugin_Handled;
}

public Action:Command_MOTD(client, const String:command[], argc){
	if(GetGameType() == GameType_CSGO && IsPlayerAlive(client) && GetClientTeam(client) != CS_TEAM_NONE)
		FakeClientCommandEx(client, "sm_motd");

	return Plugin_Continue;
}

public Action:Timer_DisplayAds(Handle:timer){
	for(new client = 1; client <= MaxClients; client++){
		if(g_bGameEnded == false && IsClientConnected(client) && IsClientInGame(client) && !(GetClientSettings(client) & IGNORE_ADVERTS)){
			PrintColorText(client, ServerAdvertisements[CurrentAdvertisement],
				g_msg_pre,
				g_msg_msg,
				g_msg_var,
				g_msg_msg,
				g_msg_var,
				g_msg_msg,
				g_msg_var,
				g_msg_msg,
				g_msg_var,
				g_msg_msg,
				g_msg_var,
				g_msg_msg);
		}
	}
	CurrentAdvertisement++;
	if(CurrentAdvertisement >= ServerAdsCount){
		CurrentAdvertisement = 0;
	}
}

public Action:Leaderboard(client, args){
	new String:Leaderboard_Title[32] = "Leaderboard";
	new String:Leaderboard_URL[192] = "http://strafeodyssey.com/stats.php?client=game&p=time";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, true);

	return Plugin_Handled;
}

public Action:LeaderboardMap(client, args){
	new String:Leaderboard_Title[32] = "Leaderboard Map";
	new String:Leaderboard_URL[192];

	if(args < 1){
		Format(Leaderboard_URL, sizeof(Leaderboard_URL), "http://strafeodyssey.com/stats.php?client=game&p=time&map=%s", CurrentMapName);
	}else{
		decl String:Arguments[256];
		GetCmdArgString(Arguments, sizeof(Arguments));

		decl String:arg[65];
		BreakString(Arguments, arg, sizeof(arg));

		if(IsMapValid(arg)){
			Format(Leaderboard_URL, sizeof(Leaderboard_URL), "http://strafeodyssey.com/stats.php?client=game&p=time&map=%s", arg);
		}else{
			PrintColorText(client, "%s%sYou did not specify a valid %smap name%s.", g_msg_pre, g_msg_msg, g_msg_var, g_msg_msg, g_msg_var, g_msg_msg);
			return Plugin_Handled;
		}
	}

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, true);

	return Plugin_Handled;
}

public Action:LeaderboardUser(client, args){
	new String:Leaderboard_Title[32] = "Leaderboard User";
	new String:Leaderboard_URL[192];

	if(args < 1){
		Format(Leaderboard_URL, sizeof(Leaderboard_URL), "http://strafeodyssey.com/stats.php?client=game&p=user");
	}else{
		decl String:Arguments[256];
		GetCmdArgString(Arguments, sizeof(Arguments));

		decl String:arg[65];
		BreakString(Arguments, arg, sizeof(arg));

		new target = FindTarget(client, arg, true, false);

		if(target && target != 0 && IsClientConnected(target)){
			new String:clientSteamID[32];
			AuthId_Steam2(target, AuthId_Engine, clientSteamID, sizeof(clientSteamID));

			Format(Leaderboard_URL, sizeof(Leaderboard_URL), "http://strafeodyssey.com/stats.php?client=game&p=user&steamid=%s", clientSteamID);
		}else if(StrContains(arg, "STEAM_0:") != -1){
			Format(Leaderboard_URL, sizeof(Leaderboard_URL), "http://strafeodyssey.com/stats.php?client=game&p=user&steamid=%s", arg);
		}else{
			PrintColorText(client, "%s%sThat is not a valid %sin-game user%s or valid %ssteam-id%s.", g_msg_pre, g_msg_msg, g_msg_var, g_msg_msg, g_msg_var, g_msg_msg);
			return Plugin_Handled;
		}
	}

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, true);

	return Plugin_Handled;
}

public Action:LeaderboardSelfies(client, args){
	new String:Leaderboard_Title[32] = "Selfies";
	new String:Leaderboard_URL[192] = "http://strafeodyssey.com/stats.php?client=game&p=user&selfies=1";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, true);

	return Plugin_Handled;
}

public Action:SourceBansWeb(client, args){
	new String:Leaderboard_Title[32] = "SourceBans";
	new String:Leaderboard_URL[192] = "http://strafeodyssey.com/server/sourcebans/";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, false);

	return Plugin_Handled;
}

public Action:SteamGroupWeb(client, args){
	new String:Leaderboard_Title[32] = "2001 Steam Group";
	new String:Leaderboard_URL[192] = "http://steamcommunity.com/groups/2001-strafe-odyssey";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, false);

	return Plugin_Handled;
}

public Action DonateWeb(int client, int args){
	new String:Leaderboard_Title[32] = "2001 Donations Page";
	new String:Leaderboard_URL[192] = "http://strafeodyssey.com/donate/";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, false);

	return Plugin_Handled;
}

public Action MOTDWeb(int client, int args){
	new String:Leaderboard_Title[32] = "2001: A Strafe Odyssey";
	new String:Leaderboard_URL[192] = "http://strafeodyssey.com/stats.php?client=game&p=motd";


	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, true);

	return Plugin_Handled;
}

public Action HelpWeb(int client, int args){
	new String:Leaderboard_Title[32] = "2001: A Strafe Odyssey";
	new String:Leaderboard_URL[192] = "http://strafeodyssey.com/stats.php?client=game&p=motd&help=1";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, true);

	return Plugin_Handled;
}

public Action OpenYouTubePage(int client, int args){
	new String:Leaderboard_Title[32] = "StrafeOdysseyRuns";
	//new String:Leaderboard_URL[192] = "https://www.youtube.com/channel/UCOCeeSIrgyTuZDItXtuLYOw";
	new String:Leaderboard_URL[192] = "https://www.youtube.com/c/StrafeOdysseyRuns";

	ShowMOTDNotify(client, Leaderboard_Title, Leaderboard_URL, MOTDPANEL_TYPE_URL, false);

	return Plugin_Handled;
}

CopyTimerPrintData(){
	ConVar __temp_main = FindConVar("timer_msgstart");
	ConVar __temp_text = FindConVar("timer_msgtext");
	ConVar __temp_spec = FindConVar("timer_msgvar");

	__temp_main.GetString(g_msg_pre, sizeof(g_msg_pre));
	__temp_text.GetString(g_msg_msg, sizeof(g_msg_msg));
	__temp_spec.GetString(g_msg_var, sizeof(g_msg_var));

	ReplaceMessage(g_msg_pre, sizeof(g_msg_pre));
	ReplaceMessage(g_msg_msg, sizeof(g_msg_msg));
	ReplaceMessage(g_msg_var, sizeof(g_msg_var));
}
