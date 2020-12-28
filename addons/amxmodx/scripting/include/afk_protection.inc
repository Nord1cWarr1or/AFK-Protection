#if defined _afk_protection_included
    #endinput
#endif

#define _afk_protection_included

/**
 * Checks if player is has AFK protection active or not.
 *
 * @param id    Player index
 *
 * @return      True, if player is AFK, false otherwise
 */
native bool:apr_get_player_afk(id);

/**
 * Activate or deactivate player's AFK protection.
 *
 * @param id    Player index
 * @param bSet  True - enable protection. false - disable
 *
 * @return      True if AFK protection has sucsessfuly activateed or deactivated,
 *              false otherwise.
 */
native apr_set_player_afk(id, bool:bSet);

/**
 * Checks if player is has OFF AFK protection or not.
 *
 * @param id    Player index
 *
 * @return      True, if player is OFF AFK protection, false otherwise
 */
native bool:apr_get_player_status(id);

/**
 * Turn ON or OFF checks for afk for player.
 *
 * @param id    Player index
 * @param bSet  True - disable checks. false - enable
 *
 * @return      Player's status
 */
native apr_set_player_status(id, bool:bSet);

/**
* Called before a player will become AFK
*
* @param id     Index of a player
*
* @noreturn
*/
forward OnPlayerBecameAFK_pre(const id);

/**
* Called after a player has become AFK
*
* @param id     Index of a player
*
* @noreturn
*/
forward OnPlayerBecameAFK_post(const id);

/**
* Called before a player will be back from AFK mode
*
* @param id     Index of a player
*
* @noreturn
*/
forward OnPlayerBack_pre(const id);

/**
* Called after a player is back from AFK mode
*
* @param id     Index of a player
*
* @noreturn
*/
forward OnPlayerBack_post(const id);