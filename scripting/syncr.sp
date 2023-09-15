#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <tf2>
#include <tf2_stocks>

#define PLUGIN_VERSION "0.9.1"

#define MAX_ROCKETS				20

#define POSITIVE_INFINITY		view_as<float>(0x7F800000)

#define TR_VERIFY_SECTIONS		10
#define DIST_BAR_MAX			30
#define DIST_BAR_RES			10
#define DIST_BAR_WIDTH			35

enum struct Rocketeer {
	bool bActivated;
	int iRockets[MAX_ROCKETS];
}

Handle g_hRefreshTimer;

ConVar g_hCVEnabled;
ConVar g_hCVLaser;
ConVar g_hCVLaserAll;
ConVar g_hCVLaserHide;
ConVar g_hCVChart;
ConVar g_hCVRing;
ConVar g_hCVCrit;
ConVar g_hCVSound;
ConVar g_hCVRave;
ConVar g_hCVWarnDist;
ConVar g_hCVThreshold;

ConVar g_hCVGravity;

// Models
int g_iLaser;
int g_iHalo;

// Player and rocket data
Rocketeer g_eRocketeer[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "SyncR",
	author = "AI",
	description = "Rocket Jump Sync Reflex Trainer",
	version = PLUGIN_VERSION,
	url = "https://github.com/geominorai/syncr"
}

public void OnPluginStart() {
	CreateConVar("syncr_version", PLUGIN_VERSION, "SyncR plugin version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_hCVEnabled = CreateConVar("syncr_enabled", "1", "Enables SyncR", FCVAR_NOTIFY);

	g_hCVLaser = CreateConVar("syncr_laser", "1", "Show colored laser pointer");
	g_hCVLaserAll = CreateConVar("syncr_laser_all", "0", "Show colored laser pointer of all players using SyncR");
	g_hCVLaserHide = CreateConVar("syncr_laser_hide", "1", "Hide colored laser pointer when looking up");

	g_hCVChart = CreateConVar("syncr_chart", "1", "Show distance to impact chart");

	g_hCVRing = CreateConVar("syncr_ring", "1", "Show landing prediction ring");
	g_hCVCrit = CreateConVar("syncr_crit", "1", "Show sync crit particle");
	g_hCVSound = CreateConVar("syncr_sound", "1", "Play sync crit sound");
	g_hCVRave = CreateConVar("syncr_rave", "0", "Switch on some disco/rave fun"); // For the bored admins ;)

	g_hCVWarnDist = CreateConVar("syncr_warn_distance", "440.0", "Imminent rocket impact distance to warn with red", FCVAR_NONE, true, 0.0, false);
	g_hCVThreshold = CreateConVar("syncr_threshold", "30.0", "Distance required between rockets for blue laser and crit feedback -- Set to 0 to disable", FCVAR_NONE, true, 0.0, false);

	g_hCVGravity = FindConVar("sv_gravity");

	RegConsoleCmd("sm_syncr", cmdSyncr, "Toggles visual and audio feedback for rocket syncs");
	RegAdminCmd("sm_setsyncr", cmdSetSyncr, ADMFLAG_SLAY, "Enable/disable SyncR for the specified player");

	AutoExecConfig(true, "syncr");

	LoadTranslations("common.phrases");
}

public void OnMapStart() {
	g_iLaser = PrecacheModel("sprites/laser.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");

	PrecacheSound("weapons/rocket_shoot_crit.wav");

	ClearAllData();

	g_hRefreshTimer = CreateTimer(0.0, Timer_Refresh, INVALID_HANDLE, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd() {
	delete g_hRefreshTimer;
}

public void OnClientDisconnect(int iClient) {
	if(g_hCVEnabled.BoolValue) {
		ClearData(iClient);
	}
}

public void OnEntityCreated(int iEntity, const char[] sClassName) {
	if(g_hCVEnabled.BoolValue) {
		if (StrEqual(sClassName,"tf_projectile_rocket") || StrEqual(sClassName,"tf_projectile_energy_ball")) {
			SDKHook(iEntity, SDKHook_Spawn, SDKHookCB_OnRocketSpawn);
		} else if (g_hCVRave.BoolValue && StrContains(sClassName,"tf_projectile") == 0) {
			// sClassName starts with "tf_projectile", i.e. rockets, pipes, stickies, arrows, syringe, bolts
			SDKHook(iEntity, SDKHook_Spawn, SDKHookCB_OnRocketSpawn);
		}
	}
}

// Custom callbacks

public void SDKHookCB_OnRocketSpawn(int iEntity) {
	int iEntityRef = EntIndexToEntRef(iEntity);

	static int prevEntityRef = -1;

	if (g_hCVEnabled.BoolValue && prevEntityRef != iEntityRef) {

		// Workaround for SourceMod bug calling hook twice on the same rocket entity
		prevEntityRef = iEntityRef;

		int iOwner = Entity_GetOwner(iEntity);
		if (IsClientInGame(iOwner) && g_eRocketeer[iOwner].bActivated) {
			float vecOrigin[3];
			float vecOtherOrigin[3];

			Entity_GetAbsOrigin(iEntity, vecOrigin);

			if (g_hCVThreshold.FloatValue > 0.0 && (g_hCVSound.BoolValue || g_hCVCrit.BoolValue)) {
				bool bNearRocket = false;
				int iEntIdx = -1;

				for (int j=0; j<MAX_ROCKETS && !bNearRocket; j++) {
					iEntIdx = EntRefToEntIndex(g_eRocketeer[iOwner].iRockets[j]);

					if (iEntIdx == -1) {
						// Rocket no longer exists -- clean up
						g_eRocketeer[iOwner].iRockets[j] = -1;
					} else {
						Entity_GetAbsOrigin(iEntIdx, vecOtherOrigin);

						float fVerticalDisparity = 0.7*(vecOtherOrigin[2]-vecOrigin[2])*(vecOtherOrigin[2]-vecOrigin[2]);
						float fHorizontalDisparity = 0.3*(vecOtherOrigin[0]-vecOrigin[0])*(vecOtherOrigin[0]-vecOrigin[0]) + (vecOtherOrigin[1]-vecOrigin[1])*(vecOtherOrigin[1]-vecOrigin[1]);

						bNearRocket = !g_hCVRave.BoolValue && SquareRoot(fHorizontalDisparity + fVerticalDisparity) < g_hCVThreshold.FloatValue;
					}
				}

				if (bNearRocket) {
					if (g_hCVSound.BoolValue) {
						int iClients[MAXPLAYERS+1];
						int iClientCount = Client_Get(iClients, CLIENTFILTER_INGAMEAUTH);

						Entity_GetAbsOrigin(iOwner, vecOtherOrigin);
						EmitSoundToClient(iOwner, "weapons/rocket_shoot_crit.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);
						EmitSound(iClients, iClientCount, "weapons/rocket_shoot_crit.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.75, SNDPITCH_NORMAL, -1, vecOtherOrigin);
					}

					if (g_hCVCrit.BoolValue) {
						Critify(iOwner, iEntity);
						Critify(iOwner, iEntIdx); // Nearby rocket
					}
				}
			}

			for (int i=0; i<MAX_ROCKETS; i++) {
				int iRef = g_eRocketeer[iOwner].iRockets[i];
				if (iRef == -1 || EntRefToEntIndex(iRef) == -1) {
					g_eRocketeer[iOwner].iRockets[i] = iEntityRef;
					return;
				}
			}
		}
	}
}

public Action Timer_Refresh(Handle hTimer) {
	if (!g_hCVEnabled.BoolValue || !g_hCVLaser.BoolValue) {
		return Plugin_Continue;
	}

	float vecOrigin[3];
	float vecAngles[3];
	float vecClientOrigin[3];
	float vecClientVelocity[3];
	float vecClientEyeAngles[3];
	float fDistanceImpact;
	float fDistanceBody;
	float vecTargetPoint[3];
	float vecGroundPoint[3];

	int iColor[4];
	float fBeamWidth = g_hCVRave.BoolValue ? 10.0 : 2.0;

	char sDistBar[DIST_BAR_WIDTH];
	int iClientObs[MAXPLAYERS];
	int iClientObsCount;

	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && g_eRocketeer[i].bActivated && TF2_GetClientTeam(i) > TFTeam_Spectator) {
			// Find all observers
			iClientObs[0] = i; // Include self
			iClientObsCount = 1; // Include self
			for (int j=1; j<=MaxClients; j++) {
				if (IsClientInGame(j) && i != j) {
					Obs_Mode eObsMode = Client_GetObserverMode(j);
					if ((eObsMode == OBS_MODE_IN_EYE || eObsMode == OBS_MODE_CHASE)) {
						int iObsTarget = Client_GetObserverTarget(j);
						if (i == iObsTarget) {
							iClientObs[iClientObsCount++] = j;
						}
					}
				}
			}

			int iRingColor[4] = {255, 255, 255, 255}; // White
			float fClosetDistance = POSITIVE_INFINITY;

			char sRocketInfo[254] = "\0";
			float vecVel[3];

			GetClientEyeAngles(i, vecClientEyeAngles);

			// Draw beams for each of the client's rockets
			for (int j=0; j<MAX_ROCKETS; j++) {
				int iEntIdx = EntRefToEntIndex(g_eRocketeer[i].iRockets[j]);

				if (iEntIdx == -1) {
					// Rocket no longer exists -- clean up
					g_eRocketeer[i].iRockets[j] = -1;
				} else {
					Entity_GetAbsOrigin(iEntIdx, vecOrigin);
					Entity_GetAbsAngles(iEntIdx, vecAngles);

					if (g_hCVRave.BoolValue) {
						vecAngles[0] = GetRandomFloat()*360;
						vecAngles[1] = GetRandomFloat()*360;
						vecAngles[2] = GetRandomFloat()*360;
					}

					TR_TraceRayFilter(vecOrigin, vecAngles, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment, iEntIdx);
					if(TR_DidHit() && IsValidEntity(TR_GetEntityIndex())) {
						TR_GetEndPosition(vecTargetPoint);
					} else {
						continue;
					}

					fDistanceImpact = GetVectorDistance(vecOrigin, vecTargetPoint);

					Entity_GetAbsVelocity(iEntIdx, vecVel);

					int iSegments = RoundToFloor(fDistanceImpact/GetVectorLength(vecVel)*DIST_BAR_RES);
					sDistBar[0] = 0;
					for (int k=0; k<DIST_BAR_MAX && k<iSegments; k++) {
						sDistBar[k] = '|';
					}
					if (iSegments > DIST_BAR_MAX-3) {
						sDistBar[DIST_BAR_MAX-4] = '.';
						sDistBar[DIST_BAR_MAX-3] = '.';
						sDistBar[DIST_BAR_MAX-2] = '.';
						sDistBar[DIST_BAR_MAX-1] = 0;
					} else {
						sDistBar[iSegments] = 0;
					}

					Format(sRocketInfo, sizeof(sRocketInfo), "%s\nR%d: %s", sRocketInfo, j+1, sDistBar);

					// Disable beams when the client looks up
					if (g_hCVLaserHide.BoolValue && FloatAbs(vecClientEyeAngles[0]+89.0) < 20.0) {
						continue;
					}

					if (fDistanceImpact < g_hCVWarnDist.FloatValue) {
						iColor = {255, 0, 0, 255}; // Red
					} else if (fDistanceImpact < 1.5*g_hCVWarnDist.FloatValue) {
						iColor = {255, 0, 127, 255}; // Rose
					} else {
						fDistanceBody = GetVectorDistance(vecOrigin, vecClientOrigin);

						if (0.0 < g_hCVThreshold.FloatValue && fDistanceBody < g_hCVThreshold.FloatValue) {
							iColor = {0, 0, 255, 255}; // Blue
						} else if (0.0 < g_hCVThreshold.FloatValue && fDistanceBody < 1.5*g_hCVThreshold.FloatValue) {
							iColor = {0, 255, 255, 255}; // Cyan
						} else if (fDistanceImpact < 2*g_hCVWarnDist.FloatValue) {
							iColor = {255, 255, 0, 255}; // Yellow
						} else {
							iColor = {0, 255, 0, 255}; // Green
						}
					}

					if (g_hCVRave.BoolValue) {
						iColor[0] = GetRandomInt(0, 255);
						iColor[1] = GetRandomInt(0, 255);
						iColor[2] = GetRandomInt(0, 255);
						iColor[3] = 255;
					}

					if (fDistanceImpact < fClosetDistance) {
						fClosetDistance = fDistanceImpact;
						iRingColor = iColor; // Reference
					}

					TE_SetupBeamPoints(vecOrigin, vecTargetPoint, g_iLaser, g_iHalo, 0, 30, 0.2, fBeamWidth, fBeamWidth, 10, 1.0, iColor, 0);

					if (g_hCVLaserAll.BoolValue || g_hCVRave.BoolValue) {
						TE_SendToAll();
					} else {
						TE_Send(iClientObs, iClientObsCount);
					}
				}
			}

			Entity_GetAbsOrigin(i, vecClientOrigin);
			Entity_GetAbsVelocity(i, vecClientVelocity);

			vecAngles[0] = 90.0;
			vecAngles[1] = 0.0;
			vecAngles[2] = 0.0;

			float vecProbePoint[3];
			vecProbePoint = vecClientOrigin;

			float vecProbeVelocity[3];
			vecProbeVelocity = vecClientVelocity;
			ScaleVector(vecProbeVelocity, GetTickInterval());

			float fPlayerGravityRatio = GetEntityGravity(i);
			if (fPlayerGravityRatio == 0.0) {
				fPlayerGravityRatio = 1.0;
			}

			float fGravity = -g_hCVGravity.FloatValue * fPlayerGravityRatio * GetTickInterval() * GetTickInterval();

			float vecTracePointPrev[3];
			float vecTracePoint[3];

			vecTracePointPrev = vecProbePoint;

			float vecNormal[3];

			for (int k=0; k<5; k++) {
				TR_TraceRayFilter(vecProbePoint, vecAngles, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilter_Environment);
				if(!TR_DidHit()) {
					break;
				}

				TR_GetEndPosition(vecGroundPoint);

				float fDist = vecGroundPoint[2] - vecProbePoint[2];
				if (FloatAbs(fDist) < 10) {
					TR_GetPlaneNormal(null, vecNormal);
					break;
				}

				float fVelDirectional = fGravity * fDist;

				// v_f^2 = v_0^2 + 2*g*d
				float fVelFinal = SquareRoot(FloatAbs(vecProbeVelocity[2]*vecProbeVelocity[2] + 2*fVelDirectional));
				if (fVelDirectional > 0) {
					fVelFinal *= -1.0;
				}

				float fTime = (fVelFinal-vecProbeVelocity[2])/fGravity;

				// Final value
				vecGroundPoint[0] += vecProbeVelocity[0]*fTime;
				vecGroundPoint[1] += vecProbeVelocity[1]*fTime;

				float vecTemp[3];

				// RT verification
				for (int l=1; l<=TR_VERIFY_SECTIONS; l++) {
					float fTimeSlice = (l*fTime)/TR_VERIFY_SECTIONS;
					vecTracePoint[0] = vecProbePoint[0] + vecProbeVelocity[0]*fTimeSlice;
					vecTracePoint[1] = vecProbePoint[1] + vecProbeVelocity[1]*fTimeSlice;

					// dz = v_0*t+0.5*at*^2 = (v_0 + 0.5*a*t)*t
					vecTracePoint[2] = vecProbePoint[2] + (vecProbeVelocity[2] + 0.5*fGravity*fTimeSlice)*fTimeSlice;

					float fTraceDist = GetVectorDistance(vecTracePoint, vecTracePointPrev);

					SubtractVectors(vecTracePoint, vecTracePointPrev, vecTemp); // Store temp vector in fTemp
					GetVectorAngles(vecTemp, vecTemp);

					TR_TraceRayFilter(vecTracePointPrev, vecTemp, MASK_ALL, RayType_Infinite, TraceEntityFilter_Environment);
					if(!TR_DidHit()) {
						break;
					}

					TR_GetEndPosition(vecTemp);

					if (GetVectorDistance(vecTracePointPrev, vecTemp) <= fTraceDist) {
						vecGroundPoint = vecTemp;
						TR_GetPlaneNormal(null, vecNormal);

						break;
					}

					vecTracePointPrev = vecTracePoint;
				}

				// Furthest probe points
				vecProbePoint = vecGroundPoint;

				vecProbeVelocity[2] = fVelFinal;
			}

			if (g_hCVChart.BoolValue) {
				BfWrite hMessage = view_as<BfWrite>(StartMessage("KeyHintText", iClientObs, iClientObsCount));
				hMessage.WriteByte(1); // Channel

				fDistanceImpact = GetVectorDistance(vecClientOrigin, vecGroundPoint);
				int iSegments = RoundToFloor(fDistanceImpact/1100.0*DIST_BAR_RES);

				sDistBar[0] = '-';
				sDistBar[1] = 0;

				for (int k=0; k<DIST_BAR_MAX && k<iSegments; k++) {
					sDistBar[k] = '|';
				}

				if (iSegments > DIST_BAR_MAX-3) {
					sDistBar[DIST_BAR_MAX-4] = '.';
					sDistBar[DIST_BAR_MAX-3] = '.';
					sDistBar[DIST_BAR_MAX-2] = '.';
					sDistBar[DIST_BAR_MAX-1] = 0;
				} else if (iSegments > 0) {
					sDistBar[iSegments] = 0;
				}

				int iHu = RoundFloat(1100.0/DIST_BAR_RES);
				if (sRocketInfo[0]) {
					Format(sRocketInfo, sizeof(sRocketInfo), "Distance to Impact (per %d hu)\n                                                    \nPC: %s%s", iHu, sDistBar, sRocketInfo);
					hMessage.WriteString(sRocketInfo);
				} else {
					Format(sRocketInfo, sizeof(sRocketInfo), "Distance to Impact (per %d hu)\n                                                    \nPC: %s", iHu, sDistBar);
					hMessage.WriteString(sRocketInfo);
				}

				EndMessage();
			}

			// Ignore vertical
			if (vecNormal[2] <= 0.0) {
				continue;
			}

			if (g_hCVRing.BoolValue) {
				// Distance from client to currently predicted landing point
				float fDistImpactPoint = GetVectorDistance(vecClientOrigin, vecGroundPoint);
				if (fDistImpactPoint < g_hCVThreshold.FloatValue) {
					iRingColor = {0, 0, 255, 255}; // Blue
				}

				if (vecClientEyeAngles[0] > 45.0 && fClosetDistance != POSITIVE_INFINITY || fDistImpactPoint > 30) {
					float fMultiplier = Math_Min(1.0, FloatAbs(fDistImpactPoint)/1000.0);
					float fDeg0 = FLOAT_PI/3;

					// Move ring slightly above ground to avoid clipping
					float vecNormalOffset[3];
					vecNormalOffset = vecNormal;
					ScaleVector(vecNormalOffset, 5.0);
					AddVectors(vecNormalOffset, vecGroundPoint, vecGroundPoint);

					float vecRingPoint[3];
					float vecRingPointPrev[3];

					// Solve for z-coordinate using the general equation of a plane
					vecRingPointPrev[0] = vecGroundPoint[0] + Cosine(0.0)*g_hCVThreshold.FloatValue*fMultiplier;
					vecRingPointPrev[1] = vecGroundPoint[1] + Sine(0.0)*g_hCVThreshold.FloatValue*fMultiplier;
					vecRingPointPrev[2] = ((vecGroundPoint[0]-vecRingPointPrev[0])*vecNormal[0] + (vecGroundPoint[1]-vecRingPointPrev[1])*vecNormal[1] + vecGroundPoint[2]*vecNormal[2]) / vecNormal[2];

					float vecExpand[3];
					float vecPointA[3];
					float vecPointB[3];

					for (float fDeg=fDeg0; fDeg<2*FLOAT_PI; fDeg+=fDeg0) {
						vecRingPoint[0] = vecGroundPoint[0] + Cosine(fDeg)*g_hCVThreshold.FloatValue*fMultiplier;
						vecRingPoint[1] = vecGroundPoint[1] + Sine(fDeg)*g_hCVThreshold.FloatValue*fMultiplier;
						vecRingPoint[2] = ((vecGroundPoint[0]-vecRingPoint[0])*vecNormal[0] + (vecGroundPoint[1]-vecRingPoint[1])*vecNormal[1] + vecGroundPoint[2]*vecNormal[2]) / vecNormal[2];

						SubtractVectors(vecRingPoint, vecRingPointPrev, vecExpand);
						ScaleVector(vecExpand, 0.5*1.08);

						vecPointA[0] = 0.5*(vecRingPointPrev[0]+vecRingPoint[0]);
						vecPointA[1] = 0.5*(vecRingPointPrev[1]+vecRingPoint[1]);
						vecPointA[2] = 0.5*(vecRingPointPrev[2]+vecRingPoint[2]);

						AddVectors(vecPointA, vecExpand, vecPointA);
						ScaleVector(vecExpand, -2.0);
						AddVectors(vecPointA, vecExpand, vecPointB);

						TE_SetupBeamPoints(vecPointA, vecPointB, g_iLaser, g_iHalo, 0, 30, 0.2, fMultiplier*5.0, fMultiplier*5.0, 10, 1.0, iRingColor, 0);

						vecRingPointPrev = vecRingPoint;

						if (g_hCVLaserAll.BoolValue) {
							TE_SendToAll();
						} else {
							TE_Send(iClientObs, iClientObsCount);
						}
					}
				}
			}
		}
	}

	return Plugin_Continue;
}

public bool TraceEntityFilter_Environment(int iEntity, int iMask, int iSelfEntity) {
	return iEntity > MaxClients && iEntity != iSelfEntity;
}

// Commands

public Action cmdSetSyncr(int iClient, int iArgC) {
	if (iArgC != 2) {
		ReplyToCommand(iClient, "[SM] Usage: sm_setsyncr <player> [0/1]");
		return Plugin_Handled;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	int iTarget = FindTarget(iClient, sArg1);
	if (iTarget == -1) {
		return Plugin_Handled;
	}

	char sArg2[32];
	GetCmdArg(2, sArg2, sizeof(sArg2));
	bool bEnable = StringToInt(sArg2) != 0;

	char sTargetName[32];
	GetClientName(iTarget, sTargetName, sizeof(sTargetName));

	g_eRocketeer[iTarget].bActivated = bEnable;
	if (bEnable) {
		ReplyToCommand(iClient, "[SM] SyncR enabled for %s", sTargetName);
		PrintToChat(iTarget, "[SM] SyncR enabled");
	} else {
		ReplyToCommand(iClient, "[SM] SyncR disabled for %s", sTargetName);
		PrintToChat(iTarget, "[SM] SyncR disabled");
		ClearData(iTarget);
	}

	return Plugin_Handled;
}

public Action cmdSyncr(int iClient, int iArgC) {
	g_eRocketeer[iClient].bActivated = !g_eRocketeer[iClient].bActivated;

	if (g_eRocketeer[iClient].bActivated) {
		ReplyToCommand(iClient, "[SM] SyncR enabled");
	} else {
		ReplyToCommand(iClient, "[SM] SyncR disabled");
		ClearData(iClient);
	}

	return Plugin_Handled;
}

// Helpers

void ClearData(int iClient) {
	g_eRocketeer[iClient].bActivated = false;
	for (int i=0; i<MAX_ROCKETS; i++) {
		g_eRocketeer[iClient].iRockets[i] = -1;
	}
}

void ClearAllData() {
	for (int i=1; i<=MaxClients; i++) {
		ClearData(i);
		Array_Fill(g_eRocketeer[i].iRockets, MAX_ROCKETS, -1);
	}
}

void Critify(int iClient, int iEntity) {
	int iParticle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(iParticle)) {
		float vecOrigin[3];
		Entity_GetAbsOrigin(iEntity, vecOrigin);
		Entity_SetAbsOrigin(iParticle, vecOrigin);

		if (TF2_GetClientTeam(iClient) == TFTeam_Red) {
			DispatchKeyValue(iParticle, "effect_name", "critical_rocket_red");
		} else {
			DispatchKeyValue(iParticle, "effect_name", "critical_rocket_blue");
		}

		SetVariantString("!activator");
		AcceptEntityInput(iParticle, "SetParent", iEntity, iParticle, 0);
		DispatchSpawn(iParticle);
		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "Start");
	}
}
