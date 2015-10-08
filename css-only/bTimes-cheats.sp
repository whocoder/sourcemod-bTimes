#include <sourcemod>

ConVar mat_fullbright;
ConVar r_drawclipbrushes;

public Plugin:myinfo = {
	name = "Cheat Commands",
	author = "cam",
	description = "Allows users to use custom cheat commands in the server.",
	version = VERSION,
	url = URL
};

public OnPluginStart(){
	CreateConVar("timer_cheats_version", "2001-0.1", "The current plugin version.");
}

public OnMapStart(){
	mat_fullbright 		= FindConVar("mat_fullbright");
	r_drawclipbrushes 	= FindConVar("r_drawclipbrushes");
	
	RemoveCheats(mat_fullbright);
	RemoveCheats(r_drawclipbrushes);
	
	RegAdminCmd("sm_fullbright", 		FullbrightToggle, 	ADMFLAG_CUSTOM6, "Toggle fullbright");
	RegAdminCmd("sm_lights", 			FullbrightToggle, 	ADMFLAG_CUSTOM6, "Toggle fullbright");
	
	RegAdminCmd("sm_showclips", 		DrawClipsToggle, 	ADMFLAG_CUSTOM6, "Show player-clips");
	RegAdminCmd("sm_drawclips", 		DrawClipsToggle, 	ADMFLAG_CUSTOM6, "Show player-clips");
	RegAdminCmd("sm_showclipbrushes",	DrawClipsToggle, 	ADMFLAG_CUSTOM6, "Show player-clips");
}

public Action:FullbrightToggle(client, args){
	ToggleConVarBool(mat_fullbright);
	
	return Plugin_Handled;
}

public Action:DrawClipsToggle(client, args){
	ToggleConVarBool(r_drawclipbrushes);
	
	return Plugin_Handled;
}

void ToggleConVarBool(ConVar cvar){
	if(cvar.Flags & FCVAR_CHEAT)
		RemoveCheats(cvar);
		
	cvar.SetBool(!cvar.BoolValue);
}

void RemoveCheats(ConVar cvar){
	int newFlags = cvar.Flags;
	
	if(newFlags & FCVAR_CHEAT)
		newFlags &= ~FCVAR_CHEAT;
	
	cvar.Flags = newFlags;
}