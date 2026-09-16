-- ZPause's settings, from the lobby: Black Ops 4 through Shield.
--
-- The host gets a ZPAUSE SETTINGS button in Shield's zombies custom game
-- setup, above its own difficulty list, which opens a page laid out the way
-- Shield's own settings popups are: a tab for each part of ZPause's settings,
-- the settings as a list, and what the one under the cursor does and what its
-- default is.
--
-- Every setting is a dvar, and the script reads them as a match starts. Black
-- Ops 4 keeps no dvar once it closes, so a change made here is also written
-- to project-bo4/saved/server/zpause_lobby.json with Shield's writejson, and
-- read back into its dvar with readjson once when the game starts. The script
-- still takes project-bo4/saved/server/zpause.json -- the file the installer
-- and the in-game menu write -- for anything this page has not set.
--
-- Shield loads this file through the mod's metadata.json, hooked after the
-- frontend file its own lobby pages hang off. The rows between the markers
-- below are written by tools/mk_t8_lobby.py from zpause.gsc on every build.
--
-- Four things about Lua on this client that shape the code:
--   * No new globals: a file-scope `function Name()` is refused and the file
--     dies before a line runs. Everything here is local, or a field on a table
--     the game already has.
--   * Functions the engine provides are keyed by hash, not by name.
--     Engine[@"getdvarstring"] is the call Shield's own pages make;
--     Engine.GetDvarString is nil.
--   * Text a stock widget localizes has to be a localized string the game
--     knows. A plain string is taken as the name of one: it draws as a hash
--     and raises a script error every time it is drawn. The tab names and the
--     reset confirmation's title and choices are keys the manifest registers;
--     everything else here is set as it is.
--   * Nothing here is allowed to take Shield's lobby down with it, so every
--     step runs protected and says what went wrong in the console.

-- ZP_ROWS_BEGIN
-- Written by tools/mk_t8_lobby.py from zpause.gsc and zpause-t8.settings.
-- Never edit by hand: change the zp_cfg calls or the README, and build.
local PAGES = {
	{
		title = "INPUT",
		key = "zpause/lobby_input",
		rows = {
			{
				dvar = "zp_button_combo",
				kind = "flag",
				default = "1",
				hint = "Enable the button combo. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_button_hold_time",
				kind = "number",
				default = "0.3",
				hint = "How long the combo must be held. Default: 0.3.",
				values = { "0.1", "0.2", "0.3", "0.5", "0.75", "1", "1.5", "2" },
				labels = { "0.1", "0.2", "0.3", "0.5", "0.75", "1", "1.5", "2" }
			},
			{
				dvar = "zp_combo",
				kind = "choice",
				default = "crouch_melee",
				hint = "Which two buttons: crouch_melee, crouch_use, crouch_frag, crouch_ads, use_frag, use_ads, use_attack, attack_ads, frag_only, or jump_melee. Default: CROUCH MELEE.",
				values = { "crouch_melee", "crouch_use", "crouch_frag", "crouch_ads", "use_frag", "use_ads", "use_attack", "attack_ads", "frag_only", "jump_melee" },
				labels = { "CROUCH MELEE", "CROUCH USE", "CROUCH FRAG", "CROUCH ADS", "USE FRAG", "USE ADS", "USE ATTACK", "ATTACK ADS", "FRAG ONLY", "JUMP MELEE" }
			},
			{
				dvar = "zp_button_combo_dead",
				kind = "choice",
				default = "use_ads",
				hint = "The combo used while down, when stance and melee stop registering. Default: USE ADS.",
				values = { "use_ads", "crouch_use", "crouch_frag", "crouch_ads", "crouch_melee", "use_frag", "frag_only", "use_attack", "attack_ads" },
				labels = { "USE ADS", "CROUCH USE", "CROUCH FRAG", "CROUCH ADS", "CROUCH MELEE", "USE FRAG", "FRAG ONLY", "USE ATTACK", "ATTACK ADS" }
			},
			{
				dvar = "zp_allow_short_words",
				kind = "flag",
				default = "0",
				hint = "No effect on this engine - there are no chat commands to widen. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_input_debug",
				kind = "flag",
				default = "0",
				hint = "Print each player which buttons the server receives from them, for picking the two above. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
		}
	},
	{
		title = "WHO DECIDES",
		key = "zpause/lobby_who_decides",
		rows = {
			{
				dvar = "zp_host_only",
				kind = "flag",
				default = "0",
				hint = "Only the host can pause or resume. Everyone else's combo is ignored. On a dedicated server there is no host, so it turns itself off rather than locking everybody out. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_ready_check",
				kind = "flag",
				default = "0",
				hint = "Resuming waits for the players to say they're back. Not a vote - nobody says no and it can't fail. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_ready_percent",
				kind = "number",
				default = "100",
				hint = "How much of the room has to be ready. 100 is everybody. Default: 100.",
				values = { "25", "50", "75", "100" },
				labels = { "25", "50", "75", "100" }
			},
			{
				dvar = "zp_host_approve",
				kind = "flag",
				default = "0",
				hint = "The host pauses at once; anyone else has to ask and the host answers yes or no. It runs as a vote only the host can cast, so the yes/no input, the HUD and the timeout are a vote's. Pausing only - resuming still follows zp_vote. zp_host_only wins where both are set. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
		}
	},
	{
		title = "VOTING",
		key = "zpause/lobby_voting",
		rows = {
			{
				dvar = "zp_vote",
				kind = "flag",
				default = "0",
				hint = "Put pauses to a vote. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_min",
				kind = "number",
				default = "2",
				hint = "Minimum yes votes, whatever the player count. Default: 2.",
				values = { "1", "2", "3", "4", "6", "8" },
				labels = { "1", "2", "3", "4", "6", "8" }
			},
			{
				dvar = "zp_vote_percent",
				kind = "number",
				default = "51",
				hint = "Percent of players who must vote yes. Default: 51.",
				values = { "25", "34", "50", "51", "67", "75", "100" },
				labels = { "25", "34", "50", "51", "67", "75", "100" }
			},
			{
				dvar = "zp_vote_time",
				kind = "number",
				default = "30",
				hint = "Seconds a vote stays open. Default: 30.",
				values = { "10", "15", "20", "30", "45", "60", "90", "120" },
				labels = { "10", "15", "20", "30", "45", "60", "90", "120" }
			},
			{
				dvar = "zp_vote_unpause",
				kind = "flag",
				default = "0",
				hint = "Resuming needs a vote too. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_hold",
				kind = "flag",
				default = "0",
				hint = "Freeze the game while the vote runs, and resume it if the vote fails. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_initiator_yes",
				kind = "flag",
				default = "1",
				hint = "Whoever called the vote counts as a yes. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_lockout",
				kind = "number",
				default = "10",
				hint = "Seconds before another vote can be called after one fails. Default: 10.",
				values = { "0", "5", "10", "20", "30", "60", "120" },
				labels = { "0", "5", "10", "20", "30", "60", "120" }
			},
			{
				dvar = "zp_vote_hud",
				kind = "flag",
				default = "1",
				hint = "Show the vote tally on screen. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_show_voters",
				kind = "flag",
				default = "1",
				hint = "List each player and how they voted. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_hud_position",
				kind = "choice",
				default = "top",
				hint = "Where the vote tally sits. Same slots as zp_hud_position. Default: TOP.",
				values = { "top", "bottom", "middle", "left", "right" },
				labels = { "TOP", "BOTTOM", "MIDDLE", "LEFT", "RIGHT" }
			},
			{
				dvar = "zp_vote_alive_only",
				kind = "flag",
				default = "1",
				hint = "Leave bled-out spectators out of the threshold and the count. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_vote_result_time",
				kind = "number",
				default = "2",
				hint = "Seconds the result stands on the tally after a vote resolves. 0 = clear at once. Default: 2.",
				values = { "0", "1", "2", "3", "5", "10" },
				labels = { "0", "1", "2", "3", "5", "10" }
			},
			{
				dvar = "zp_vote_no_combo",
				kind = "choice",
				default = "jump_melee",
				hint = "Combo for a no vote. Same list as zp_combo. Default: JUMP MELEE.",
				values = { "jump_melee", "crouch_use", "crouch_frag", "crouch_ads", "crouch_melee", "use_frag", "frag_only", "use_ads", "use_attack", "attack_ads" },
				labels = { "JUMP MELEE", "CROUCH USE", "CROUCH FRAG", "CROUCH ADS", "CROUCH MELEE", "USE FRAG", "FRAG ONLY", "USE ADS", "USE ATTACK", "ATTACK ADS" }
			},
			{
				dvar = "zp_vote_no_combo_dead",
				kind = "choice",
				default = "use_attack",
				hint = "The same, for a no vote while down. Default: USE ATTACK.",
				values = { "use_attack", "crouch_use", "crouch_frag", "crouch_ads", "crouch_melee", "use_frag", "frag_only", "use_ads", "attack_ads" },
				labels = { "USE ATTACK", "CROUCH USE", "CROUCH FRAG", "CROUCH ADS", "CROUCH MELEE", "USE FRAG", "FRAG ONLY", "USE ADS", "ATTACK ADS" }
			},
		}
	},
	{
		title = "TIMING",
		key = "zpause/lobby_timing",
		rows = {
			{
				dvar = "zp_countdown",
				kind = "number",
				default = "3",
				hint = "Seconds counted down before the game starts again. 0 resumes at once. Default: 3.",
				values = { "0", "1", "2", "3", "5", "10" },
				labels = { "0", "1", "2", "3", "5", "10" }
			},
			{
				dvar = "zp_grace",
				kind = "number",
				default = "2",
				hint = "Seconds of invulnerability after resuming. Default: 2.",
				values = { "0", "1", "2", "3", "5", "10" },
				labels = { "0", "1", "2", "3", "5", "10" }
			},
			{
				dvar = "zp_cooldown",
				kind = "number",
				default = "2",
				hint = "Seconds before the pause can be toggled again. Default: 2.",
				values = { "0", "1", "2", "3", "5", "10", "30" },
				labels = { "0", "1", "2", "3", "5", "10", "30" }
			},
			{
				dvar = "zp_max_pause_time",
				kind = "number",
				default = "0",
				hint = "Resume automatically after this many seconds. 0 is no limit. Default: 0.",
				values = { "0", "60", "120", "300", "600", "900", "1800", "3600" },
				labels = { "0", "60", "120", "300", "600", "900", "1800", "3600" }
			},
			{
				dvar = "zp_max_pauses",
				kind = "number",
				default = "0",
				hint = "How many times one match can be paused. 0 is no cap. Default: 0.",
				values = { "0", "1", "2", "3", "5", "10", "20" },
				labels = { "0", "1", "2", "3", "5", "10", "20" }
			},
			{
				dvar = "zp_ease",
				kind = "flag",
				default = "1",
				hint = "Ease time down into the pause and back out, instead of cutting to a stop. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_ease_time",
				kind = "number",
				default = "0.35",
				hint = "Seconds of ramp at each end. Default: 0.35.",
				values = { "0", "0.1", "0.2", "0.35", "0.5", "0.75", "1" },
				labels = { "0", "0.1", "0.2", "0.35", "0.5", "0.75", "1" }
			},
			{
				dvar = "zp_round_pause",
				kind = "flag",
				default = "0",
				hint = "Hold a pause until the round is over instead of freezing the game mid-horde. Asking again calls it off. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_pause_on_disconnect",
				kind = "flag",
				default = "0",
				hint = "Pause when somebody drops, so whoever is left isn't overrun while they rejoin. Nothing un-pauses on its own, so zp_max_pause_time is the way out if they don't come back. Default: OFF.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
		}
	},
	{
		title = "WHAT GETS FROZEN",
		key = "zpause/lobby_what_gets_frozen",
		rows = {
			{
				dvar = "zp_godmode",
				kind = "flag",
				default = "1",
				hint = "Nobody can be hurt while paused. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_freeze_players",
				kind = "flag",
				default = "1",
				hint = "Lock players in place while paused. 0 lets them walk around with their weapons down, locked again for the countdown - not recommended, because doors, the box, perks, traps and pickups can all still be used while the zombies are held. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_control_guard",
				kind = "flag",
				default = "1",
				hint = "Re-apply the freeze on a tick, in case another script releases somebody mid-pause. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_freeze_clock",
				kind = "flag",
				default = "1",
				hint = "Hold the match timer. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_freeze_powerups",
				kind = "flag",
				default = "1",
				hint = "Stop ground powerups timing out. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_freeze_effects",
				kind = "flag",
				default = "1",
				hint = "Hold insta-kill / double-points countdowns. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_freeze_bleedout",
				kind = "flag",
				default = "1",
				hint = "Stop downed players bleeding out. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_engine_freeze",
				kind = "flag",
				default = "1",
				hint = "Use setentitypaused(), the call stock's own AI freeze is built on. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_drift_guard",
				kind = "flag",
				default = "1",
				hint = "Snap back any AI that still manages to move. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_freeze_anims",
				kind = "flag",
				default = "1",
				hint = "No effect on this engine - the entity pause already stops animation. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_silence_zombies",
				kind = "flag",
				default = "1",
				hint = "Stop zombies growling while paused. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
		}
	},
	{
		title = "PRESENTATION",
		key = "zpause/lobby_presentation",
		rows = {
			{
				dvar = "zp_hud",
				kind = "flag",
				default = "1",
				hint = "Draw the pause block at all. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_hud_position",
				kind = "choice",
				default = "center",
				hint = "Where it sits: center, top, middle, bottom, left or right. Default: CENTER.",
				values = { "center", "top", "middle", "bottom", "left", "right" },
				labels = { "CENTER", "TOP", "MIDDLE", "BOTTOM", "LEFT", "RIGHT" }
			},
			{
				dvar = "zp_hud_timer",
				kind = "flag",
				default = "1",
				hint = "Show how long the pause has run. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_show_hint",
				kind = "flag",
				default = "1",
				hint = "Tell players how to pause when they spawn. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_hud_binds",
				kind = "flag",
				default = "1",
				hint = "Show the combo as key names rather than plain words. Applies to the spawn hint; the pause block always uses words. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_blackout",
				kind = "flag",
				default = "1",
				hint = "Dim everyone's screen while paused, which keeps the pause text readable over a bright skybox. Raise zp_blackout_alpha for the anti-scouting blackout this used to be. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_blackout_alpha",
				kind = "number",
				default = "0.2",
				hint = "How far it dims. 0.2 is a light darkening; 1 is fully black. Default: 0.2.",
				values = { "0.1", "0.2", "0.35", "0.5", "0.65", "0.8", "1" },
				labels = { "0.1", "0.2", "0.35", "0.5", "0.65", "0.8", "1" }
			},
			{
				dvar = "zp_blur",
				kind = "flag",
				default = "1",
				hint = "Blur the screen while paused. Default: ON.",
				values = { "0", "1" },
				labels = { "OFF", "ON" }
			},
			{
				dvar = "zp_blur_amount",
				kind = "number",
				default = "2",
				hint = "How much. 1.5 reads as a step back without hiding the game. Default: 2.",
				values = { "0.5", "1", "1.5", "2", "3", "4", "6" },
				labels = { "0.5", "1", "1.5", "2", "3", "4", "6" }
			},
			{
				dvar = "zp_pause_sound",
				kind = "choice",
				default = "zmb_bgb_plainsight_start",
				hint = "Played to everyone on pause. none for silence. Default: BGB PLAINSIGHT START.",
				values = { "zmb_bgb_plainsight_start", "none" },
				labels = { "BGB PLAINSIGHT START", "NONE" }
			},
		}
	},
}
-- ZP_ROWS_END

local SAVED = "project-bo4/saved/server/zpause_lobby.json"
local RESTORED = "zp_lobby_restored"

local POPUP = "ZPause_SettingsPopup"
local ROWS = "ZPauseSettingsRows"
local TABS = "ZPauseSettingsTabs"
local RESET = "ZPauseSettingsReset"

local CONFIRM = nil
local BACK = nil
local ALIGN_LEFT = nil
local ALIGN_TOP = nil

local constants = function ()
	CONFIRM = Enum[@"luibutton"][@"lui_key_xba_pscross"]
	BACK = Enum[@"luibutton"][@"lui_key_xbb_pscircle"]
	ALIGN_LEFT = Enum[@"luialignment"][@"lui_alignment_left"]
	ALIGN_TOP = Enum[@"luialignment"][@"lui_alignment_top"]
end

local say = function ( text )
	pcall( Engine[@"printinfo"], 0, "^3ZPause lobby: " .. tostring( text ) )
end

local try = function ( what, fn, ... )
	local ok, err = pcall( fn, ... )
	if not ok then
		say( what .. " failed: " .. tostring( err ) )
	end
	return ok, err
end

-- ------------------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------------------

local primary = function ()
	local ok, controller = pcall( Engine[@"getprimarycontroller"] )
	if ok and controller ~= nil then
		return controller
	end
	return 0
end

local exec = function ( controller, text )
	pcall( Engine[@"exec"], controller or primary(), text )
end

local get = function ( dvar )
	local ok, value = pcall( Engine[@"getdvarstring"], dvar )
	if ok and type( value ) == "string" then
		return value
	end
	return ""
end

-- SetDvar is what Shield's pages use on a dvar that exists; the console's set
-- is what makes one that does not.
local set = function ( controller, dvar, value )
	pcall( Engine[@"setdvar"], dvar, value )
	exec( controller, "set " .. dvar .. " \"" .. value .. "\"" )
end

-- Said in the console as well, because Shield's log shows the commands its
-- own readjson runs and not the ones a Lua file hands the engine.
local save = function ( controller, dvar, value )
	exec( controller, "writejson \"\" " .. dvar .. " \"" .. value .. "\" string " .. SAVED )
	say( "saved " .. dvar .. " \"" .. value .. "\"" )
end

-- Whether the value a dvar holds is the one a choice stands for, numbers
-- compared as numbers: "0.30" is 0.3.
local same = function ( a, b )
	local na = tonumber( a )
	local nb = tonumber( b )
	if na ~= nil and nb ~= nil then
		return na == nb
	end
	return a == b
end

-- Empty is the obvious case, but the script writes every setting into its
-- dvar as a match loads, so after one has been played every setting nobody
-- touched holds its default.
local isDefault = function ( current, row )
	return current == "" or same( current, row.default )
end

-- Once per game start, not once per trip to the frontend: coming back from a
-- match loads this file again, and by then the dvars hold whatever the match
-- left them at -- the in-game menu's changes included.
--
-- readjson runs "set <dvar> <value>" itself, so it makes a dvar that does not
-- exist yet. An empty default is a set with nothing to set, which leaves
-- every setting this page has never saved exactly as it was.
local restore = function ()
	if get( RESTORED ) == "1" then
		return
	end
	local controller = primary()
	for _, page in ipairs( PAGES ) do
		for _, row in ipairs( page.rows ) do
			exec( controller, "readjson " .. row.dvar .. " \"\" " .. row.dvar .. " string \"\" true " .. SAVED )
		end
	end
	exec( controller, "set " .. RESTORED .. " 1" )
	say( "restored the lobby's settings from " .. SAVED )
end

-- ------------------------------------------------------------------------
-- Rows
-- ------------------------------------------------------------------------

local page = 1
local openList = nil

local refresh = function ()
	if openList ~= nil then
		openList:setDataSource( "" )
		openList:setDataSource( ROWS )
	end
end

-- Called by a row whenever one of its choices is under the cursor: as the
-- page opens, as the cursor moves onto the row, and as left or right moves
-- the choice. Only a move to a different value is a change.
local chosen = function ( self, element, controller, row, menu )
	if CoD.OptionsUtility ~= nil and CoD.OptionsUtility.UpdateInfoModels ~= nil then
		pcall( CoD.OptionsUtility.UpdateInfoModels, element )
	end
	local current = get( row.dvar )
	if element.default == true then
		if isDefault( current, row ) then
			return
		end
	elseif same( current, element.value ) then
		return
	end
	set( controller, row.dvar, element.value )
	save( controller, row.dvar, element.value )
end

local showChange = function ( item )
	return item.default ~= true
end

-- One setting. DEFAULT is the empty value, and it stands for the default
-- itself, which is not offered again as a choice of its own. A value the page
-- does not step through keeps a choice of its own rather than showing as
-- another.
local rowItem = function ( row )
	local source = "ZPauseSettingsOpt_" .. row.dvar
	local current = get( row.dvar )
	local atDefault = isDefault( current, row )
	local listed = atDefault
	for _, value in ipairs( row.values ) do
		if same( current, value ) then
			listed = true
		end
	end

	local options = {}
	local add = function ( label, value, default, selected )
		table.insert( options, {
			models = {
				text = label
			},
			properties = {
				title = row.dvar,
				desc = row.hint,
				value = value,
				default = default,
				actionParam = row,
				action = chosen,
				selectIndex = selected,
				loopEdges = false,
				showChangeIndicator = showChange
			}
		} )
	end

	add( "DEFAULT", "", true, atDefault )
	for index, value in ipairs( row.values ) do
		if not same( value, row.default ) then
			if not listed and row.kind == "number" and tonumber( current ) ~= nil and tonumber( current ) < tonumber( value ) then
				add( current, current, false, true )
				listed = true
			end
			add( row.labels[index], value, false, not atDefault and same( current, value ) )
		end
	end
	if not listed then
		add( string.upper( current ), current, false, true )
	end
	options[1].properties.first = true
	options[#options].properties.last = true

	DataSources[source] = DataSourceHelpers.ListSetup( source, function ( controller )
		return options
	end, nil, nil, nil )

	return {
		models = {
			name = row.dvar,
			desc = row.hint,
			optionsDatasource = source
		},
		properties = {}
	}
end

local defineSources = function ()
	DataSources[TABS] = DataSourceHelpers.ListSetup( TABS, function ( controller )
		local tabs = {}
		for index, p in ipairs( PAGES ) do
			table.insert( tabs, {
				models = {
					name = p.key,
					zpPage = index
				},
				properties = {
					zpPage = index
				}
			} )
		end
		return tabs
	end, true )

	DataSources[ROWS] = DataSourceHelpers.ListSetup( ROWS, function ( controller )
		local rows = {}
		local p = PAGES[page] or PAGES[1]
		if p ~= nil then
			for _, row in ipairs( p.rows ) do
				table.insert( rows, rowItem( row ) )
			end
		end
		return rows
	end, nil, nil, nil )
end

-- ------------------------------------------------------------------------
-- Reset
-- ------------------------------------------------------------------------

-- Every setting back to DEFAULT: the same empty value picking DEFAULT on each
-- one writes.
local resetAll = function ( controller )
	for _, p in ipairs( PAGES ) do
		for _, row in ipairs( p.rows ) do
			set( controller, row.dvar, "" )
			save( controller, row.dvar, "" )
		end
	end
	refresh()
end

-- Asked first, the way Shield asks before it resets its own custom game
-- settings, with NO under the cursor. The overlay localizes its title and its
-- choices, so those are keys the manifest registers; the description it
-- leaves alone.
local askReset = function ( menu, controller )
	CoD.OverlayUtility.Overlays[RESET] = {
		menuName = "SystemOverlay_Compact",
		title = "zpause/lobby_reset_title",
		description = "Put every ZPause setting back to its default?",
		categoryType = CoD.OverlayUtility.OverlayTypes.Settings,
		listDatasource = function ()
			DataSources[RESET .. "_List"] = DataSourceHelpers.ListSetup( RESET .. "_List", function ( controller )
				return {
					{
						models = {
							displayText = "zpause/lobby_no"
						},
						properties = {
							action = function ( self, element, controller, param, menu )
								GoBack( menu, controller )
							end
						}
					},
					{
						models = {
							displayText = "zpause/lobby_yes"
						},
						properties = {
							action = function ( self, element, controller, param, menu )
								try( "reset", resetAll, controller )
								GoBack( menu, controller )
							end
						}
					}
				}
			end, true, nil )
			return RESET .. "_List"
		end,
		[CoD.OverlayUtility.GoBackPropertyName] = CoD.OverlayUtility.DefaultGoBack
	}
	CoD.OverlayUtility.CreateOverlay( controller, menu, RESET )
end

-- ------------------------------------------------------------------------
-- The page
-- ------------------------------------------------------------------------

local tint = function ( element )
	local ok, colour = pcall( Engine[@"getdvarint"], "shield_ui_color" )
	if not ok then
		return
	elseif colour == 0 then
		element:setRGB( 0, 1, 1 )
	elseif colour == 1 then
		element:setRGB( 1, 0, 0 )
	elseif colour == 2 then
		element:setRGB( 0, 1, 0 )
	end
end

local white = function ( element )
	if ColorSet ~= nil and ColorSet.T8__OFF__WHITE ~= nil then
		element:setRGB( ColorSet.T8__OFF__WHITE.r, ColorSet.T8__OFF__WHITE.g, ColorSet.T8__OFF__WHITE.b )
	end
end

local newButton = function ( menu, controller, text, l, r, t, b, action )
	local button = CoD.DirectorSelectButtonMiniInternal.new( menu, controller, 0.5, 0.5, l, r, 0.5, 0.5, t, b )
	button.MiddleText:setTTF( "notosans_bold" )
	button.MiddleText:setText( text )
	button.MiddleTextFocus:setText( text )
	button.MiddleTextFocus:setTTF( "notosans_bold" )
	button:linkToElementModel( menu, nil, false, function ( model )
		button:setModel( model, controller )
	end )
	menu:AddButtonCallbackFunction( button, controller, CONFIRM, "ui_confirm", function ( element, menu, controller, model )
		PlaySoundAlias( "uin_paint_image_flip_toggle" )
		try( text, action, menu, controller )
		return true
	end, function ( element, menu, controller )
		if IsGamepad( controller ) then
			CoD.Menu.SetButtonLabel( menu, CONFIRM, @"menu/select", nil, "ui_confirm" )
			return true
		end
		return false
	end, false )
	return button
end

local defineMenu = function ()
	CoD[POPUP] = InheritFrom( CoD.Menu )

	CoD[POPUP].__resetProperties = function ( self )
	end

	CoD[POPUP].__clipsPerState = {
		DefaultState = {
			DefaultClip = function ( self, event )
				self:__resetProperties()
				self:setupElementClipCounter( 0 )
			end
		}
	}

	CoD[POPUP].__onClose = function ( self )
		openList = nil
		for _, name in ipairs( { "Popup", "Container", "Tabs", "Reset" } ) do
			if self[name] ~= nil then
				self[name]:close()
			end
		end
	end
end

-- The layout is Shield's Blackout rules popup, number for number: the tab
-- bar across the top, the list on the left of a container under it, and the
-- description to the right of a divider.
local newPopup = function ( controller, userdata )
	local self = CoD.Menu.NewForUIEditor( POPUP, controller )
	local menu = self
	self:setClass( CoD[POPUP] )
	self.soundSet = "none"
	self:setOwner( controller )
	self:setLeftRight( 0, 1, 0, 0 )
	self:setTopBottom( 0, 1, 0, 0 )
	self:playSound( "menu_open", controller )
	self.anyChildUsesUpdateState = true
	menu:addElementToPendingUpdateStateList( self )

	-- Every element on the way to something clickable carries an id equal to
	-- the field its parent keeps it under, set before it is added. The menu
	-- finds what the cursor is over by walking those ids -- menu[id][id] --
	-- so one missing, or one that is not its field's name, and nothing
	-- beneath it takes a click. Shield's own pages are written that way.
	local frame = CoD.RulesCommonCenteredPopup or CoD.CommonCenteredPopup
	local popup = frame.new( menu, controller, 0, 1, 0, 0, 0, 1, 0, 0 )
	popup.TitleText:setText( "ZPause Settings" )
	popup.HeaderBackground:setAlpha( 0 )
	popup.HeaderTopBar:setAlpha( 0 )
	popup.HeaderBottomBar:setAlpha( 0 )
	popup.id = "Popup"
	self:addElement( popup )
	self.Popup = popup

	-- Shield's rules frame brings a Reset Options button of its own, and what
	-- it resets is Shield's Blackout custom game settings. Not on this page.
	-- The frame closes that button when it closes, so an element with nothing
	-- in it takes its place.
	if popup.reset_defaults ~= nil then
		popup.reset_defaults:close()
		popup.reset_defaults = LUI.UIElement.new( 0, 0, 0, 0, 0, 0, 0, 0 )
	end

	local container = LUI.UIElement.new( 0.5, 0.5, -257.49, 242.51, 0.5, 0.5, -154.76, 345.24 )
	container.id = "Container"
	container.soundSet = "default"
	container.onlyChildrenFocusable = true
	container.anyChildUsesUpdateState = true
	self:addElement( container )
	self.Container = container
	menu:addElementToPendingUpdateStateList( container )

	local list = LUI.UIList.new( menu, controller, 3, 3, nil, false, false, false, false )
	list.id = "List"
	list:setLeftRight( 0.5, 0.5, -700, 250 )
	list:setTopBottom( 0, 0, -180, -120 )
	if CoD.verticalCounter_no_buttons ~= nil then
		list:setVerticalCounter( CoD.verticalCounter_no_buttons )
	end
	list:setVerticalCount( 10 )
	list:setHorizontalCount( 1 )
	list:setAutoScaleContent( true )
	list:setWidgetType( CoD.CustomGames_SettingSliderNoCustom_NoLocalize or CoD.CustomGames_SettingSliderNoCustom )
	list:setAlignment( ALIGN_LEFT )
	tint( list )
	container:addElement( list )
	container.List = list
	container.__defaultFocus = list
	openList = list

	local divider = LUI.UIImage.new( 0.5, 0.5, 294, 296, 0.5, 0.5, -550, 350 )
	divider:setAlpha( 0.25 )
	container:addElement( divider )

	local desc = LUI.UIText.new( 0.5, 0.5, 320.51, 896.51, 0.55, 0.55, -460, -420 )
	white( desc )
	desc:setTTF( "notosans_regular" )
	desc:setAlignment( ALIGN_LEFT )
	desc:setAlignment( ALIGN_TOP )
	container:addElement( desc )
	desc:linkToElementModel( list, "desc", true, function ( model )
		local text = model:get()
		if text ~= nil then
			desc:setText( text )
		end
	end )

	local tip = LUI.UIText.new( 0.5, 0.5, -464, 300, 0.55, 0.55, 232.49, 260 )
	tip:setText( "Saved as you change it, for every match you host. The pause menu in a match changes the same settings." )
	white( tip )
	tip:setTTF( "notosans_regular" )
	tip:setAlignment( ALIGN_LEFT )
	tip:setAlignment( ALIGN_TOP )
	container:addElement( tip )

	local tabs = CoD.Common_Tabbar_Center.new( menu, controller, 0.5, 0.5, -448.25, 468.75, 0.5, 0.5, -428.76, -367.76 )
	tabs.id = "Tabs"
	tabs.Tabs.grid:setHorizontalCount( #PAGES )
	tabs.Tabs.grid:setDataSource( TABS )
	tabs:registerEventHandler( "list_active_changed", function ( element, event )
		if element.zpPage ~= nil and element.zpPage ~= page then
			page = element.zpPage
			refresh()
		end
	end )
	self:addElement( tabs )
	self.Tabs = tabs

	-- Where that button was, in the frame's own footer style, beside BACK --
	-- a little wider, so its name fits on one line.
	local reset = nil
	if CoD.featureOverlay_Button ~= nil then
		reset = CoD.featureOverlay_Button.new( menu, controller, 0.5, 0.5, 367, 603, 0.5, 0.5, 424, 484 )
		reset.id = "Reset"
		reset.ButtonContainer.Title:setText( "Reset to Defaults" )
		reset:registerEventHandler( "gain_focus", function ( element, event )
			local result = nil
			if element.gainFocus then
				result = element:gainFocus( event )
			elseif element.super.gainFocus then
				result = element.super:gainFocus( event )
			end
			CoD.Menu.UpdateButtonShownState( element, menu, controller, CONFIRM )
			return result
		end )
		menu:AddButtonCallbackFunction( reset, controller, CONFIRM, "ui_confirm", function ( element, menu, controller, model )
			try( "Reset to Defaults", askReset, menu, controller )
			return true
		end, function ( element, menu, controller )
			return false
		end, false )
	else
		reset = newButton( menu, controller, "Reset to Defaults", 313.02, 623.02, 300, 350, askReset )
		reset.id = "Reset"
	end
	self:addElement( reset )
	self.Reset = reset

	list:setDataSource( ROWS )

	menu:AddButtonCallbackFunction( self, controller, BACK, nil, function ( element, menu, controller, model )
		GoBack( self, controller )
		ClearMenuSavedState( menu )
		return true
	end, function ( element, menu, controller )
		CoD.Menu.SetButtonLabel( menu, BACK, @"menu/back", nil, nil )
		return true
	end, false )
	popup.buttons:setModel( self.buttonModel, controller )

	self:processEvent( {
		name = "menu_loaded",
		controller = controller
	} )
	self.__defaultFocus = container
	if CoD.isPC and (IsKeyboard( controller ) or self.ignoreCursor) then
		self:restoreState( controller )
	end
	LUI.OverrideFunction_CallOriginalSecond( self, "close", self.__onClose )
	return self
end

-- A page that failed to build still has to be something to back out of: an
-- overlay that opens to nothing leaves the lobby waiting on a menu that is not
-- there.
local emptyPopup = function ( controller )
	local self = CoD.Menu.NewForUIEditor( POPUP, controller )
	self:setClass( CoD[POPUP] )
	self:setOwner( controller )
	self:setLeftRight( 0, 1, 0, 0 )
	self:setTopBottom( 0, 1, 0, 0 )
	self:AddButtonCallbackFunction( self, controller, BACK, nil, function ( element, menu, controller, model )
		GoBack( self, controller )
		return true
	end, function ( element, menu, controller )
		return false
	end, false )
	return self
end

local openPopup = function ( controller, userdata )
	page = 1
	local ok, result = try( "opening the settings page", newPopup, controller, userdata )
	if ok and result ~= nil then
		return result
	end
	ok, result = try( "opening an empty page", emptyPopup, controller )
	if ok then
		return result
	end
	return nil
end

-- ------------------------------------------------------------------------
-- The button
-- ------------------------------------------------------------------------

-- Above Shield's difficulty list, clear of its first row, in the gap between
-- it and the game settings list above: the host's zombies custom game setup
-- is where ZPause's settings belong, and it is the page only the host opens.
local addButton = function ( menu, controller )
	if menu == nil or menu.ZPauseSettingsButton ~= nil or menu.Zombies_Difficulty == nil then
		return
	end
	if IsZombies ~= nil and not IsZombies() then
		return
	end
	local button = CoD.DirectorSelectButtonMiniInternal.new( menu, controller, 0.75, 0.75, 0, 350, 0.75, 0.75, -125, -75 )
	button.MiddleText:setTTF( "notosans_bold" )
	button.MiddleText:setText( "ZPause Settings" )
	button.MiddleTextFocus:setText( "ZPause Settings" )
	button.MiddleTextFocus:setTTF( "notosans_bold" )
	button:linkToElementModel( menu, nil, false, function ( model )
		button:setModel( model, controller )
	end )
	menu:addElement( button )
	menu.ZPauseSettingsButton = button
	button.id = "ZPauseSettingsButton"
	menu:AddButtonCallbackFunction( button, controller, CONFIRM, "ui_confirm", function ( element, menu2, controller2, model )
		PlaySoundAlias( "uin_paint_image_flip_toggle" )
		OpenOverlay( menu, POPUP, controller2 )
		return true
	end, function ( element, menu2, controller2 )
		if IsGamepad( controller2 ) then
			CoD.Menu.SetButtonLabel( menu2, CONFIRM, @"menu/select", nil, "ui_confirm" )
			return true
		end
		return false
	end, false )
end

-- Shield replaces the setup page from a file on the same hook as this one, so
-- which of the two runs first is not something to count on. The page is
-- wrapped now if Shield's is already there, and again whenever an overlay is
-- about to open, which is always after both files have run.
local wrapped = nil
local wrap = function ()
	local current = LUI.createMenu.DirectorCustomGameSetUpWZ
	if current == nil or current == wrapped then
		return
	end
	local original = current
	wrapped = function ( controller, userdata )
		local menu = original( controller, userdata )
		try( "adding the button", addButton, menu, controller )
		return menu
	end
	LUI.createMenu.DirectorCustomGameSetUpWZ = wrapped
end

local hookOpen = function ()
	local utility = CoD.DirectorUtility
	if utility == nil or utility.DirectorOpenOverlayWithCurrentMenuMode == nil then
		return
	end
	local original = utility.DirectorOpenOverlayWithCurrentMenuMode
	utility.DirectorOpenOverlayWithCurrentMenuMode = function ( ... )
		pcall( wrap )
		return original( ... )
	end
end

-- ------------------------------------------------------------------------

if CoD ~= nil and CoD.ShieldInitLuaFile ~= nil then
	try( "Shield's init", CoD.ShieldInitLuaFile )
end
for _, path in ipairs( {
	"ui/uieditor/widgets/common/commoncenteredpopup",
	"ui/uieditor/widgets/common/common_tabbar_center",
	"ui/uieditor/widgets/director/directorselectbuttonminiinternal",
	"ui/uieditor/widgets/systemoverlays/featureoverlay_button",
	"ui/uieditor/widgets/customgames/customgames_settingslidernocustom",
	"ui/uieditor/widgets/scrollbars/verticalcounter"
} ) do
	pcall( require, path )
end

-- The saved settings first, and on their own: they are what a match reads,
-- whether or not anything after them manages to draw a page.
try( "restoring saved settings", restore )

if try( "reading the engine's names", constants ) and try( "defining the page", defineMenu ) then
	try( "defining the rows", defineSources )
	try( "registering the page", function ()
		LUI.createMenu[POPUP] = openPopup
	end )
	try( "wrapping the setup page", wrap )
	try( "watching overlays open", hookOpen )
end
