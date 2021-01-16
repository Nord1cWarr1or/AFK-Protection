/*  *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *
*                                                                               *
*   Plugin: AFK Protection                                                      *
*                                                                               *
*   Official plugin support: https://dev-cs.ru/threads/4409/                    *
*   Official repository: https://github.com/Nord1cWarr1or/AFK-Protection        *
*   Contacts of the author: Telegram: @NordicWarrior                            *
*                                                                               *
*   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *       *
*                                                                               *
*   Плагин: Защита АФК-игроков                                                  *
*                                                                               *
*   Официальная поддержка плагина: https://dev-cs.ru/threads/4409/              *
*   Официальный репозиторий: https://github.com/Nord1cWarr1or/AFK-Protection    *
*   Связь с автором: Telegram: @NordicWarrior                                   *
*                                                                               *
*   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   */

#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <fakemeta>
#include <msgstocks>
#include <xs>

new const PLUGIN_VERSION[] = "3.1.2";

#define GetCvarDesc(%0) fmt("%L", LANG_SERVER, %0)

enum _:XYZ { Float:X, Float:Y, Float:Z };

enum _:AFKEffectsFlags (<<=1)
{
    Effects_Transparency = 1,
    Effects_ScreenFade,
    Effects_Icon
};

enum _:Cvars
{
    EFFECTS[4],
    AFK_TIME,
    SCREENFADE_AMOUNT,
    RANDOM_SCREENFADE_COLOR,
    MESSAGE
};

const TASKID__AFK_CHECK = 1500;

const Float:CHECK_FREQUENCY = 0.5;
const Float:ICON_HIGHER = 55.0;

new const g_szIconClassname[] = "afk_icon";

new Float:g_flPlayerOrigin[MAX_PLAYERS + 1][XYZ];
new Float:g_flPlayerViewAngle[MAX_PLAYERS + 1][XYZ];
new bool:g_bIsPlayerAFK[MAX_PLAYERS + 1];
new bool:g_bIsPlayerBot[MAX_PLAYERS + 1];
new bool:g_bIsPlayerOffProtect[MAX_PLAYERS + 1];
new g_iPlayerTime[MAX_PLAYERS + 1];
new g_iPlayerIcon[MAX_PLAYERS + 1] = { NULLENT, ... };
new g_pCvarValue[Cvars];
new g_pCvarEffects;
new g_iSycnHudObj;

new g_iFwd_PlayerBecameAFK_pre, g_iFwd_PlayerBecameAFK_post;
new g_iFwd_PlayerBack_pre, g_iFwd_PlayerBack_post;

new const g_szAFKIconPath[] = "sprites/afk/afk.spr";    // Path to sprite or model of AFK icon

#define AUTO_CONFIG		// Comment out if you don't want the plugin config to be created automatically in "configs/plugins"

public plugin_init()
{
    register_plugin("AFK Protection", PLUGIN_VERSION, "Nordic Warrior");

    RegisterHookChain(RG_CBasePlayer_Spawn, "RG_OnPlayerSpawn_Post", true);
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_OnPlayerKilled_Post", true);

    register_dictionary("afk_protection.txt");

    CreateCvars();

    #if defined AUTO_CONFIG
    AutoExecConfig(true, "AFKProtection");
    #endif

    g_iSycnHudObj = CreateHudSyncObj();

    hook_cvar_change(g_pCvarEffects, "OnChangeCvarEffects");

    CreateForwards();
}

public plugin_precache()
{
    if(file_exists(g_szAFKIconPath))
    {
        precache_model(g_szAFKIconPath);
    }
    else
    {
        set_fail_state("File '%s' not found!", g_szAFKIconPath);
    }
}

public plugin_natives()
{
    register_native("apr_get_player_afk", "native_apr_get_player_afk");
    register_native("apr_set_player_afk", "native_apr_set_player_afk");
    register_native("apr_get_player_status", "native_apr_get_player_status");
    register_native("apr_set_player_status", "native_apr_set_player_status");
}

public client_putinserver(id)
{
    if(is_user_bot(id))
    {
        g_bIsPlayerBot[id] = true;
    }
}

public client_disconnected(id)
{
    ResetCounters(id, true, true);
}

public RG_OnPlayerSpawn_Post(const id)
{
    if(!is_user_alive(id) || g_bIsPlayerBot[id] || g_bIsPlayerOffProtect[id])
        return;

    remove_task(id + TASKID__AFK_CHECK);

    if(g_bIsPlayerAFK[id])
    {
        SetScreenFade(id);
        rg_set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, 120);

        if(g_iPlayerIcon[id] != NULLENT)
        {
            RemoveIcon(id);
        }
    }

    RequestFrame("OnNextFrame", id);
}

public RG_OnPlayerKilled_Post(const id, const iAttacker, iGib)
{
    if(!g_bIsPlayerAFK[id] || !is_user_connected(id))
        return;

    ResetCounters(id);
}

public OnNextFrame(const id)
{
    if(get_entvar(id, var_flags) & FL_ONGROUND)
    {
        StartCheck(id);
    }
    else
    {
        RequestFrame("OnNextFrame", id);
    }
}

public StartCheck(const id)
{
    if(!is_user_alive(id))
        return;

    if(g_bIsPlayerAFK[id])
    {
        set_entvar(id, var_takedamage, DAMAGE_NO);
        set_entvar(id, var_solid, SOLID_NOT);
        set_member(id, m_bIsDefusing, true);

        CreateIcon(id);
    }

    get_entvar(id, var_origin, g_flPlayerOrigin[id]);
    get_entvar(id, var_angles, g_flPlayerViewAngle[id]);    

    AFKCheck(id);

    set_task_ex(CHECK_FREQUENCY, "AFKCheck", id + TASKID__AFK_CHECK, .flags = SetTask_Repeat);
}

public AFKCheck(id)
{
    id -= TASKID__AFK_CHECK;

    if(!is_user_alive(id))
        return;

    static Float:flPlayerOrigin[XYZ], Float:flPlayerViewAngle[XYZ];

    static iReturn;

    get_entvar(id, var_origin, flPlayerOrigin);
    get_entvar(id, var_angles, flPlayerViewAngle);

    if(xs_vec_equal(flPlayerOrigin, g_flPlayerOrigin[id]) && xs_vec_equal(flPlayerViewAngle, g_flPlayerViewAngle[id]) \
    && !get_entvar(id, var_button))
    {
        if(!g_bIsPlayerAFK[id] && get_entvar(id, var_waterlevel) <= 2 && get_entvar(id, var_takedamage) > DAMAGE_NO)
        {
            g_iPlayerTime[id]++;
        }

        if(g_iPlayerTime[id] >= g_pCvarValue[AFK_TIME] / CHECK_FREQUENCY)
        {
            ExecuteForward(g_iFwd_PlayerBecameAFK_pre, iReturn, id);

            if(iReturn == PLUGIN_HANDLED)
                return;

            g_bIsPlayerAFK[id] = true;
            g_iPlayerTime[id] = 0;

            ToggleAFKProtection(id);
            SendMessage(id);

            ExecuteForward(g_iFwd_PlayerBecameAFK_post, iReturn, id);
        }
    }
    else
    {
        if(g_bIsPlayerAFK[id])
        {
            ExecuteForward(g_iFwd_PlayerBack_pre, iReturn, id);

            if(iReturn == PLUGIN_HANDLED)
                return;

            g_bIsPlayerAFK[id] = false;

            ToggleAFKProtection(id);
            SendMessage(id);

            ExecuteForward(g_iFwd_PlayerBack_post, iReturn, id);
        }

        g_iPlayerTime[id] = 0;
    }

    xs_vec_copy(flPlayerOrigin, g_flPlayerOrigin[id]);
    xs_vec_copy(flPlayerViewAngle, g_flPlayerViewAngle[id]);
}

ToggleAFKProtection(const id)
{
    if(g_bIsPlayerAFK[id])
    {
        set_entvar(id, var_takedamage, DAMAGE_NO);
        set_entvar(id, var_solid, SOLID_NOT);
        set_member(id, m_bIsDefusing, true);
    }
    else
    {
        set_entvar(id, var_takedamage, DAMAGE_AIM);
        set_entvar(id, var_solid, SOLID_SLIDEBOX);
        set_member(id, m_bIsDefusing, false);
    }

    ToggleEffects(id);
}

ToggleEffects(const id)
{
    new iFlagsEffects = read_flags(g_pCvarValue[EFFECTS]);

    if(iFlagsEffects & Effects_Transparency)
    {
        if(g_bIsPlayerAFK[id])
        {
            rg_set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, 120);
        }
        else
        {
            rg_set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 0);
        }
    }
    if(iFlagsEffects & Effects_ScreenFade)
    {
        if(g_bIsPlayerAFK[id])
        {
            SetScreenFade(id);
        }
        else
        {
            UnsetScreenFade(id);
        }
    }
    if(iFlagsEffects & Effects_Icon)
    {
        if(g_bIsPlayerAFK[id] && g_iPlayerIcon[id] == NULLENT)
        {
            CreateIcon(id);
        }
        else if(!g_bIsPlayerAFK[id] && g_iPlayerIcon[id] != NULLENT)
        {
            RemoveIcon(id);
        }
    }
}

SendMessage(const id)
{
    SetGlobalTransTarget(id);

    switch(g_pCvarValue[MESSAGE])
    {
        case 1: client_print_color(id, g_bIsPlayerAFK[id] ? print_team_blue : print_team_red, "%l", g_bIsPlayerAFK[id] ? "AFKPROTECTION_CHAT_COLOR_AFK_ON" : "AFKPROTECTION_CHAT_COLOR_AFK_OFF");
        case 2:
        {
            set_hudmessage(0, 200, 200, -1.0, 0.1, 0, 1.0, 3.0, 0.1, 0.2);
            ShowSyncHudMsg(id, g_iSycnHudObj, "%l", g_bIsPlayerAFK[id] ? "AFKPROTECTION_CHAT_AFK_ON" : "AFKPROTECTION_CHAT_AFK_OFF");
        }
        case 3:
        {
            set_dhudmessage(0, 200, 200, -1.0, 0.2, 0, 1.0, 3.0, 0.1, 0.2)
            clear_dhudmessage();
            show_dhudmessage(id, "%l", g_bIsPlayerAFK[id] ? "AFKPROTECTION_CHAT_AFK_ON" : "AFKPROTECTION_CHAT_AFK_OFF");
        }
        case 4: client_print(id, print_center, "%l", g_bIsPlayerAFK[id] ? "AFKPROTECTION_CHAT_AFK_ON" : "AFKPROTECTION_CHAT_AFK_OFF");
    }
}

CreateIcon(const id)
{
    new iEnt = rg_create_entity("env_sprite");

    new Float:flPlayerOrigin[XYZ];
    get_entvar(id, var_origin, flPlayerOrigin);

    flPlayerOrigin[2] += ICON_HIGHER;

    set_entvar(iEnt, var_classname, g_szIconClassname);
    engfunc(EngFunc_SetModel, iEnt, g_szAFKIconPath);
    set_entvar(iEnt, var_scale, 0.5);
    set_entvar(iEnt, var_rendermode, kRenderTransAdd);
    set_entvar(iEnt, var_renderamt, 100.0);
    set_entvar(iEnt, var_framerate, 10.0);
    set_entvar(iEnt, var_origin, flPlayerOrigin);
    set_entvar(iEnt, var_spawnflags, SF_SPRITE_STARTON);

    g_iPlayerIcon[id] = iEnt;

    dllfunc(DLLFunc_Spawn, iEnt);
}

RemoveIcon(const id)
{
    set_entvar(g_iPlayerIcon[id], var_flags, FL_KILLME);
    g_iPlayerIcon[id] = NULLENT;
}

ResetCounters(const id, bool:bDisconnected = false, bStopTask = false)
{
    new bool:bOldState = g_bIsPlayerAFK[id];

    g_bIsPlayerAFK[id] = false;
    
    g_iPlayerTime[id] = 0;

    for(new i; i < XYZ; i++)
    {
        g_flPlayerOrigin[id][i] = 0.0;
        g_flPlayerViewAngle[id][i] = 0.0;
    }

    if(bStopTask)
    {
        remove_task(id + TASKID__AFK_CHECK);
    }

    if(!bDisconnected)
    {
        if(bOldState)
        {
            ToggleAFKProtection(id);
        }
    }
    else
    {
        g_bIsPlayerBot[id] = false;
        g_bIsPlayerOffProtect[id] = false;

        if(g_iPlayerIcon[id] != NULLENT)
        {
            RemoveIcon(id);
        }
    }
}

SetScreenFade(const id)
{
    if(get_viewent(id) != id)
        return;

    fade_user_screen(id, 
        .duration = 0.0,
        .fadetime = 0.0,
        .flags = ScreenFade_StayOut,
        .r = g_pCvarValue[RANDOM_SCREENFADE_COLOR] ? random(255) : 0,
        .g = g_pCvarValue[RANDOM_SCREENFADE_COLOR] ? random(255) : 0,
        .b = g_pCvarValue[RANDOM_SCREENFADE_COLOR] ? random(255) : 0,
        .a = g_pCvarValue[SCREENFADE_AMOUNT]);
}

UnsetScreenFade(const id)
{
    if(get_viewent(id) != id)
        return;

    fade_user_screen(id, 
        .duration = 0.0,
        .fadetime = g_pCvarValue[RANDOM_SCREENFADE_COLOR] ? 0.0 : 1.0,
        .flags = ScreenFade_FadeIn,
        .r = 0,
        .g = 0,
        .b = 0,
        .a = g_pCvarValue[SCREENFADE_AMOUNT]);
}

public OnChangeCvarEffects(pCvar, const szOldValue[], const szNewValue[])
{
    new iOldFlagsEffects = read_flags(szOldValue);
    new iNewFlagsEffects = read_flags(szNewValue);

    new bool:bAddTransparency, bool:bDelTransparency;
    new bool:bAddScreenFade, bool:bDelScreenFade;
    new bool:bAddIcon, bool:bDelIcon;

    if(iOldFlagsEffects & Effects_Transparency && !(iNewFlagsEffects & Effects_Transparency))
    {
        bDelTransparency = true;
    }
    else if(!(iOldFlagsEffects & Effects_Transparency) && iNewFlagsEffects & Effects_Transparency)
    {
        bAddTransparency = true;
    }

    if(iOldFlagsEffects & Effects_ScreenFade && !(iNewFlagsEffects & Effects_ScreenFade))
    {
        bDelScreenFade = true;
    }
    else if(!(iOldFlagsEffects & Effects_ScreenFade) && iNewFlagsEffects & Effects_ScreenFade)
    {
        bAddScreenFade = true;
    }

    if(iOldFlagsEffects & Effects_Icon && !(iNewFlagsEffects & Effects_Icon))
    {
        bDelIcon = true;
    }
    else if(!(iOldFlagsEffects & Effects_Icon) && iNewFlagsEffects & Effects_Icon)
    {
        bAddIcon = true;
    }

    for(new id = 1; id <= MaxClients; id++)
    {
        if(!g_bIsPlayerAFK[id])
            continue;

        if(bDelTransparency)
            rg_set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 0);
        else if(bAddTransparency)
            rg_set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, 120);

        if(bDelScreenFade)
            UnsetScreenFade(id);
        else if(bAddScreenFade)
            SetScreenFade(id);

        if(bDelIcon)
            RemoveIcon(id);
        else if(bAddIcon)
            CreateIcon(id);
    }
}

public bool:native_apr_get_player_afk(iPluginID, iParams)
{
    enum { id = 1 };

    return bool:g_bIsPlayerAFK[get_param(id)];
}

public native_apr_set_player_afk(iPluginID, iParams)
{
    enum { iPlayer = 1, _bSet };

    new id = get_param(iPlayer);
    new bool:bSet = bool:get_param(_bSet);

    if(bSet && !g_bIsPlayerAFK[id] && !g_bIsPlayerOffProtect[id])
    {
        g_bIsPlayerAFK[id] = true;
        ToggleAFKProtection(id);

        return true;
    }
    else if(!bSet && g_bIsPlayerAFK[id])
    {
        ResetCounters(id);
        ToggleAFKProtection(id);

        return true;
    }

    return false;
}

public bool:native_apr_get_player_status(iPluginID, iParams)
{
    enum { id = 1 };

    return bool:g_bIsPlayerOffProtect[get_param(id)];
}

public native_apr_set_player_status(iPluginID, iParams)
{
    enum { iPlayer = 1, _bSet };

    new id = get_param(iPlayer);
    new bool:bSet = bool:get_param(_bSet);

    if(bSet)
    {
        g_bIsPlayerOffProtect[id] = true;

        ResetCounters(id, false, true);

        if(g_bIsPlayerAFK[id])
        {
            g_bIsPlayerAFK[id] = false;
            ToggleAFKProtection(id);
        }
    }
    else
    {
        g_bIsPlayerOffProtect[id] = false;

        RG_OnPlayerSpawn_Post(id);
    }

    return bSet;
}

CreateCvars()
{
    bind_pcvar_string(g_pCvarEffects = create_cvar("afk_effects",
        .string = "abc",
        .description = GetCvarDesc("AFKPROTECTION_CVAR_EFFECTS")),
        g_pCvarValue[EFFECTS], charsmax(g_pCvarValue[EFFECTS]));

    bind_pcvar_num(create_cvar("afk_time", "15",
        .description = GetCvarDesc("AFKPROTECTION_CVAR_TIME")),
        g_pCvarValue[AFK_TIME]);

    bind_pcvar_num(create_cvar("afk_screenfade_amount", "110",
        .description = GetCvarDesc("AFKPROTECTION_CVAR_SCREENFADE_AMOUNT")),
        g_pCvarValue[SCREENFADE_AMOUNT]);

    bind_pcvar_num(create_cvar("afk_random_screenfade_color", "0",
        .description = GetCvarDesc("AFKPROTECTION_CVAR_RANDOM_SCREENFADE_COLOR")),
        g_pCvarValue[RANDOM_SCREENFADE_COLOR]);

    bind_pcvar_num(create_cvar("afk_message", "0",
        .description = GetCvarDesc("AFKPROTECTION_CVAR_MESSAGE")),
        g_pCvarValue[MESSAGE]);
}

CreateForwards()
{
    g_iFwd_PlayerBecameAFK_pre  = CreateMultiForward("OnPlayerBecameAFK_pre", ET_STOP, FP_CELL);
    g_iFwd_PlayerBecameAFK_post = CreateMultiForward("OnPlayerBecameAFK_post", ET_IGNORE, FP_CELL);
    g_iFwd_PlayerBack_pre       = CreateMultiForward("OnPlayerBack_pre", ET_STOP, FP_CELL);
    g_iFwd_PlayerBack_post      = CreateMultiForward("OnPlayerBack_post", ET_IGNORE, FP_CELL);
}

public OnConfigsExecuted()
{
    register_cvar("AFKProtection_version", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED);
}

stock clear_dhudmessage()
{
    for(new i = 1; i < 8; i++)
    {
        show_dhudmessage(0, "");
    }
}

stock rg_set_rendering(const id, const iRenderFx, const R, const G, const B, const iRenderMode, const iRenderAmount)
{
    new Float:flRenderColor[3];

    flRenderColor[0] = float(R);
    flRenderColor[1] = float(G);
    flRenderColor[2] = float(B);

    set_entvar(id, var_renderfx, iRenderFx);
    set_entvar(id, var_rendercolor, flRenderColor);
    set_entvar(id, var_rendermode, iRenderMode);
    set_entvar(id, var_renderamt, float(iRenderAmount));
}