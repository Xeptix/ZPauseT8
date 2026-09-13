/*
    ZPAUSE T8 v1.4 -- Black Ops 4 / Project BO4 (Shield)

    A synced co-op pause for Black Ops 4 zombies. Fork of the T7 port; see
    docs/porting-t8.md for the survey behind every decision here.

    Three things are genuinely different from T7 and everything else falls
    out of the same design:

      The world pause is free twice over. scripts/zm_common/zm_round_logic
      already waits on the "world_is_paused" flag, so the round loop parks
      itself with nothing patched -- the same gift T7 got. And while there
      is no disablezombies() here, there is setentitypaused(), which stock
      freezes AI with; pause_zombies() is the red herring, being a nuke
      rather than a freeze. So this port holds AI the way T6 and T7 do,
      not the way T5 and T4 have to.

      Player state is arbitrated. val::set( owner, property, value ) with a
      matching val::reset, rather than calling freezecontrols() directly.
      That is better than what the other ports do: our hold cannot be
      released by an unrelated system, and ours cannot stomp somebody
      else's. Everything here owns its values under #"zpause".

      The HUD is Shield's, and it is the easiest of the five. Elements are
      addressed by an id we choose, with anchor, align and scale as plain
      parameters. No parent bookkeeping, no configstring pool, and none of
      the destroy()-does-not-detach trap that costs T6 and T7 real code.
*/

#using scripts\core_common\system_shared.gsc;
#using scripts\core_common\flag_shared.gsc;
#using scripts\core_common\values_shared.gsc;
#using scripts\core_common\util_shared.gsc;
#using scripts\core_common\callbacks_shared.gsc;
#using scripts\core_common\lui_shared.gsc;

#namespace zpause;

/*
    Black Ops 4 spells this correctly. Black Ops 3 does not, and the T7 port
    reproduces its typo -- __init__sytem__ -- because it has to.
*/
function autoexec __init__system__()
{
    system::register(#"zpause", &__init__, undefined, undefined);
}

function __init__()
{
    if (zp_true(level.zp_loaded))
    {
        return;
    }

    zp_file_read();
    zp_load_config();

    level.zp_loaded = 1;
    level.zp_paused = 0;
    level.zp_busy = 0;
    level.zp_pause_start = 0;
    level.zp_pause_count = 0;
    level.zp_pauser_name = "someone";
    level.zp_last_toggle = 0;
    level.zp_held_vars = [];
    level.zp_pending = 0;
    level.zp_vote_active = 0;
    level.zp_vote_serial = 0;
    level.zp_vote_last_fail = 0;
    level.zp_vote_approval = 0;
    level.zp_vote_provisional = 0;
    level.zp_spawn_flag_was_set = 0;
    level.zp_hud_up = 0;

    /*
        The flag stock round logic waits on. A map that never uses it will
        not have created it, so it is initialised here rather than assumed
        -- the same care the T7 port takes.
    */
    if (!level flag::exists("world_is_paused"))
    {
        level flag::init("world_is_paused");
    }

    ShieldLog("ZPause T8 loaded");

    callback::on_connect(&zp_on_connect);
    callback::on_spawned(&zp_on_spawned);

    zp_build_watermark();

    level thread zp_config_watcher();
    level thread zp_round_watcher();
}

/*
    is_true() has no equivalent a Shield script can reach, so the same
    behaviour is done by hand. Same reason the T7 and T4 ports carry one.
*/
function zp_true(v)
{
    return isdefined(v) && v;
}

/*
    Whether the match is far enough along to be paused at all.

    Same flag T6 and T7 use, and _zm initialises it during setup, so a
    request during the opening blackscreen is refused rather than
    freezing a game that has not started.
*/
function zp_game_ready()
{
    if (zp_true(level.gameended))
    {
        return 0;
    }

    if (!level flag::exists("initial_blackscreen_passed"))
    {
        return 0;
    }

    return level flag::get("initial_blackscreen_passed");
}

function zp_msg_all(txt)
{
    foreach (player in level.players)
    {
        if (isdefined(player))
        {
            player iprintln(txt);
        }
    }
}

function zp_sound_all(alias)
{
    if (!isdefined(alias) || alias == "")
    {
        return;
    }

    /*
        Hashed before it goes in. Sound aliases are hashes on this engine --
        stock writes them as #"mus_level_up" -- and this one arrives as a
        string out of a dvar, so it has to be converted or it names nothing.
    */
    id = hash(alias);

    foreach (player in level.players)
    {
        if (isdefined(player))
        {
            player playlocalsound(id);
        }
    }
}

/*
    The version and the moment it was built, written between the markers by
    tools/build_t8.py on every build. Empty in a release build, which is
    what makes the watermark below disappear from one.

    Generated. Never edit that line by hand.
*/
function zp_build()
{
    // ZP_BUILD_BEGIN
    return "ZPause v1.4  09/13/2026 12:02 AM";
    // ZP_BUILD_END
}

/*
    Draws the stamp in the corner of a development build.

    Worth having early rather than late: on T7 a stale compiled artifact
    shipped beside newer sources and nothing on screen said so, which cost
    a run of builds to notice. A number on screen makes that impossible.
*/
function zp_build_watermark()
{
    stamp = zp_build();

    if (stamp == "")
    {
        return;
    }

    // Anchored to the top-right corner and right-aligned on itself, so a
    // longer stamp grows leftwards instead of off the edge.
    ShieldRegisterHudElem("zp_build", stamp, zp_gold(), -10, 12, 2, 0, 2, 0, 0.6);
}


/* ==================================================================
    CONFIG

    Every value below is also a dvar of the same name, and on this engine
    the dvar is *registered* rather than merely set -- which is the one
    thing Black Ops 3 has no answer for. On T7 the zp_ dvars work but never
    appear in console suggestions; here they complete, and show their
    value, default and domain.

    The description is left empty on purpose. The README's dvar table is
    the canonical one, release_check.py already forces that table to agree
    with this script, and a second copy of the prose in here would be a
    second thing to keep in step with nothing policing it. Worth revisiting
    once release_check can compare the two.
   ================================================================== */

/*
    Registering a name and creating a dvar are two different things, and
    the console needs both.

    ShieldRegisterDVarName fills Shield's name table. Its console then
    only offers a name whose dvar the game can actually find:

        if (dvars::find_dvar(dvar.fnv1a) && match(input, dvar.name) ...)

    and getdvarint( name, default ) hands back the default without
    creating anything -- so every setting here was invisible until
    somebody set it by hand, which meant already knowing the name. Same
    problem T7 has, and the same answer: create it once, with our
    default, and leave anything already set alone.
*/
/*
    The settings file, read once at load.

    Every other port lets its installer rewrite the default in each
    zp_cfg_ call of the installed script. Nothing can do that here --
    what installs is compiled -- so the installer writes this instead,
    and Shield hands it over as ordinary GSC values.

        project-bo4/saved/server/zpause.json

    Read once rather than on every config pass: the config is re-read
    every five seconds, and a file is not. Editing it takes effect
    on the next match, which is exactly what rewriting a script does on
    the other ports.
*/
function zp_file_read()
{
    level.zp_file = ShieldFromJson("zpause");
}

/*
    What the file says a setting should be, or the built-in default.

    A list of { name, value } rather than one object of pairs, because
    Shield turns a JSON object into a GSC struct and a struct's fields
    can only be read by a name written into the script. Written this
    way, .name and .value are literals and the search is an ordinary
    loop -- nothing depends on indexing an array by a runtime string.
*/
function zp_file_value(dvar, def)
{
    if (!isdefined(level.zp_file))
    {
        return def;
    }

    foreach (entry in level.zp_file)
    {
        if (!isdefined(entry) || !isdefined(entry.name) || !isdefined(entry.value))
        {
            continue;
        }

        if (entry.name == dvar)
        {
            return entry.value;
        }
    }

    return def;
}

function zp_cfg_register(dvar, def)
{
    ShieldRegisterDVarName(dvar, "");

    // An unset dvar reads as empty, which is what tells the two apart.
    if (getdvar(dvar, "") == "")
    {
        setdvar(dvar, def);
    }
}

function zp_cfg_int(dvar, def)
{
    def = zp_file_value(dvar, def);
    zp_cfg_register(dvar, "" + def);

    return getdvarint(dvar, def);
}

function zp_cfg_float(dvar, def)
{
    def = zp_file_value(dvar, def);
    zp_cfg_register(dvar, "" + def);

    return getdvarfloat(dvar, def);
}

function zp_cfg_str(dvar, def)
{
    def = zp_file_value(dvar, def);
    zp_cfg_register(dvar, def);

    return getdvar(dvar, def);
}

function zp_load_config()
{
    /*
        Reuse the struct rather than making a new one. This runs on a timer
        as well as on every pause request, and allocating each time walks a
        long session into running out of script variables. Every field is
        overwritten on each pass, so there is nothing stale to clear.
    */
    if (!isdefined(level.zp))
    {
        level.zp = spawnstruct();
    }

    // --- input -----------------------------------------------------
    /*
        Hold crouch + melee together to toggle the pause. Chat commands are
        not here: Black Ops 4 gives a script no say callback to bind to,
        the same as Black Ops 3 and the two Plutonium forks below T6.
    */
    level.zp.button_combo = zp_cfg_int("zp_button_combo", 1);
    level.zp.button_hold_time = zp_cfg_float("zp_button_hold_time", 0.3);

    /*
        Which two buttons. Same names, same default and same meaning as
        every other port, so one config carries across the family.
    */
    level.zp.combo = zp_cfg_str("zp_combo", "crouch_melee");

    /*
        Down on the floor, stance and melee stop registering, so the
        fallback is two buttons that survive it.
    */
    level.zp.button_combo_dead = zp_cfg_str("zp_button_combo_dead", "use_ads");

    // Carried so one config file reads the same on all five ports. There
    // are no chat commands on this engine to widen, the same as T7.
    level.zp.allow_short_words = zp_cfg_int("zp_allow_short_words", 0);

    // Also carried rather than used: Shield loads one mod folder, so
    // there is no second copy here to turn off.
    level.zp.only_script = zp_cfg_int("zp_only_script", 0);
    level.zp.only_mod = zp_cfg_int("zp_only_mod", 0);

    // Prints each player the buttons the server actually receives from
    // them, which is how the two settings above get chosen.
    level.zp.input_debug = zp_cfg_int("zp_input_debug", 0);

    // --- who decides -----------------------------------------------
    /*
        Only the host can pause or resume; everyone else's combo is
        ignored. On a dedicated server there is no host, so this turns
        itself off rather than locking everybody out.
    */
    level.zp.host_only = zp_cfg_int("zp_host_only", 0);

    /*
        Resuming waits for the room to say it is back.

        Not a vote: nobody says no and it cannot fail, so it needs no
        zp_vote, and the resume input marks you ready instead of
        resuming. The last person to press it is what starts the game.
    */
    level.zp.ready_check = zp_cfg_int("zp_ready_check", 0);
    level.zp.ready_percent = zp_cfg_int("zp_ready_percent", 100);

    /*
        The host pauses at once; anybody else has to ask, and the host
        answers yes or no.

        It runs as a vote only the host can cast, so the yes/no input,
        the HUD and the timeout are all a vote's. Pausing only --
        resuming still follows zp_vote. zp_host_only wins where both are
        set, because there is then nobody to ask.
    */
    level.zp.host_approve = zp_cfg_int("zp_host_approve", 0);

    // --- voting ----------------------------------------------------
    level.zp.vote = zp_cfg_int("zp_vote", 0);
    level.zp.vote_min = zp_cfg_int("zp_vote_min", 2);
    level.zp.vote_percent = zp_cfg_int("zp_vote_percent", 51);
    level.zp.vote_time = zp_cfg_float("zp_vote_time", 30);
    level.zp.vote_unpause = zp_cfg_int("zp_vote_unpause", 0);

    /*
        Freeze the game while the vote runs, and hand it back if the vote
        fails. Off by default: it makes a pause vote unloseable in the
        sense that matters -- the horde stops either way -- which is not
        what everyone wants.
    */
    level.zp.vote_hold = zp_cfg_int("zp_vote_hold", 0);
    level.zp.vote_initiator_yes = zp_cfg_int("zp_vote_initiator_yes", 1);
    level.zp.vote_lockout = zp_cfg_float("zp_vote_lockout", 10);
    level.zp.vote_hud = zp_cfg_int("zp_vote_hud", 1);
    level.zp.vote_show_voters = zp_cfg_int("zp_vote_show_voters", 1);
    level.zp.vote_hud_position = zp_cfg_str("zp_vote_hud_position", "top");

    /*
        Spectators and downed players do not count towards the
        electorate. A room where half the players are dead should not
        need their agreement to carry on.
    */
    level.zp.vote_alive_only = zp_cfg_int("zp_vote_alive_only", 1);
    level.zp.vote_result_time = zp_cfg_float("zp_vote_result_time", 2);

    // The combo that votes no. The resume combo is a yes while a vote is
    // open, so no needs one of its own.
    level.zp.vote_no_combo = zp_cfg_str("zp_vote_no_combo", "jump_melee");
    level.zp.vote_no_combo_dead = zp_cfg_str("zp_vote_no_combo_dead", "use_attack");

    // --- timing ----------------------------------------------------
    level.zp.countdown = zp_cfg_int("zp_countdown", 3);
    level.zp.grace = zp_cfg_float("zp_grace", 2);
    level.zp.cooldown = zp_cfg_float("zp_cooldown", 2);
    level.zp.max_pause_time = zp_cfg_int("zp_max_pause_time", 0);
    level.zp.max_pauses = zp_cfg_int("zp_max_pauses", 0);

    /*
        Ramp time down into the pause and back out of it, rather than
        stopping dead. setslowmotion is the same call T7 uses and stock
        Black Ops 4 uses it twenty times over.
    */
    level.zp.ease = zp_cfg_int("zp_ease", 1);
    level.zp.ease_time = zp_cfg_float("zp_ease_time", 0.35);

    // Hold the pause until the round is over, rather than taking it now.
    level.zp.round_pause = zp_cfg_int("zp_round_pause", 0);

    // Pause by itself when somebody drops.
    level.zp.pause_on_disconnect = zp_cfg_int("zp_pause_on_disconnect", 0);

    // --- what gets frozen ------------------------------------------
    level.zp.godmode = zp_cfg_int("zp_godmode", 1);

    /*
        Everything the pause did to a player, re-applied on a tick.

        Less load-bearing here than on the other ports, because val::
        holds are arbitrated and another system releasing its own cannot
        release ours. It is still worth having: a script that calls
        freezecontrols() directly goes round val:: entirely, and that is
        exactly the case this exists for on T6 and T7.
    */
    level.zp.control_guard = zp_cfg_int("zp_control_guard", 1);

    /*
        The four things that keep running while everything else stops.

        The game clock ticks on real time, powerups time out, insta-kill
        and double points burn down, and a downed player bleeds out --
        none of which the entity pause touches, because none of them is
        an entity. Every field these use exists on this engine with the
        same name and the same shape as on T7.
    */
    level.zp.freeze_clock = zp_cfg_int("zp_freeze_clock", 1);
    level.zp.freeze_powerups = zp_cfg_int("zp_freeze_powerups", 1);
    level.zp.freeze_effects = zp_cfg_int("zp_freeze_effects", 1);
    level.zp.freeze_bleedout = zp_cfg_int("zp_freeze_bleedout", 1);

    /*
        Hold the AI with setentitypaused(), which is what stock's own
        freeze() uses. Turning it off falls back to the enforcer alone --
        ignoreall and a pinned goal -- which is what T5 and T4 have to do
        for want of any engine call at all.
    */
    level.zp.engine_freeze = zp_cfg_int("zp_engine_freeze", 1);

    /*
        Put back any AI that manages to move anyway. A backup to the
        engine freeze rather than a replacement for it, which is exactly
        how T6 and T7 carry the same setting.
    */
    level.zp.drift_guard = zp_cfg_int("zp_drift_guard", 1);

    // Compared against distancesquared, so this is eight units of travel.
    level.zp.drift_tolerance = 64;

    // No effect here, the same as on T7: the entity pause already stops
    // animation. Carried so one config file reads the same everywhere.
    level.zp.freeze_anims = zp_cfg_int("zp_freeze_anims", 1);

    /*
        Shut the zombies up while the game is held.

        T6 does this by flagging each zombie is_inert, which its vocals
        function checks. Black Ops 4 has the same idea under a worse
        name: zm_audio::zmbaivox_playvox returns before it plays anything
        if var_e8920729 is set on the zombie, whatever the vox type or
        priority. Widow's Wine sets it on a webbed zombie and clears it
        again, so it is both precedented and safe to borrow -- and it is
        put back the way it was found rather than cleared.
    */
    level.zp.silence_zombies = zp_cfg_int("zp_silence_zombies", 1);

    /*
        zp_control_guard and zp_silence_zombies are not here yet.
        Declaring a setting the script never reads again is how a dvar
        comes to do nothing quietly, so they arrive with the code that
        honours them.

        Silence is not an oversight, it is blocked: T5 cuts a held
        zombie's growling with stopsounds(), and on this engine that is a
        player call. It stopped the server with "entity is not a player"
        on the first pause that had zombies in it. Nothing in the AI
        scripts calls it, there is no AI-safe equivalent in the dump, and
        the vocals themselves come out of the behaviour tree with no
        is_inert check to lean on.
    */

    // --- presentation ----------------------------------------------
    level.zp.hud = zp_cfg_int("zp_hud", 1);
    level.zp.hud_position = zp_cfg_str("zp_hud_position", "center");
    level.zp.hud_timer = zp_cfg_int("zp_hud_timer", 1);
    level.zp.show_hint = zp_cfg_int("zp_show_hint", 1);
    level.zp.hud_binds = zp_cfg_int("zp_hud_binds", 1);

    /*
        Black out the screen while paused, at whatever alpha is asked
        for. Off by default on every port -- it hides the game, which is
        the point when somebody has to step away and a nuisance the rest
        of the time.

        Same implementation as T7, down to the call: lui::screen_fade
        takes a colour and a target alpha, and is reached from zombies
        script already, so it is certain to be loaded.
    */
    level.zp.blackout = zp_cfg_int("zp_blackout", 1);
    level.zp.blackout_alpha = zp_cfg_float("zp_blackout_alpha", 0.2);

    /*
        Blur the screen while paused. setblur() is a player call here the
        same as on T7, and zm_player.gsc uses it, so this is the one
        piece of presentation that ports across without changing a word.

        1.5 reads as "the game has stepped back" without hiding it; 2 is
        the family default.
    */
    level.zp.blur = zp_cfg_int("zp_blur", 1);
    level.zp.blur_amount = zp_cfg_float("zp_blur_amount", 2);

    /*
        Stock aliases, so the script stays one drop-in file -- a custom
        sound would have to be installed by every player rather than just
        the host.

        None of T6's or T7's three exist on this engine, so these are the
        Black Ops 4 equivalents. In Plain Sight is the gum that makes the
        world ignore you, which is near enough to what is happening, and
        it has a matching pair of start and end stings.

        Set any of them to "" for silence.
    */
    level.zp.pause_sound = zp_cfg_str("zp_pause_sound", "zmb_bgb_plainsight_start");
    level.zp.countdown_sound = zp_cfg_str("zp_countdown_sound", "zmb_trap_ready");
    level.zp.resume_sound = zp_cfg_str("zp_resume_sound", "zmb_bgb_plainsight_end");

    /*
        No zp_blur. T7 blurs with a post-process the client applies, and
        reaching one from here needs a registered clientfield and a client
        script to answer it -- a second compiled artifact and a second VM,
        not a line of config. It is the one setting on this port that is
        missing for want of work rather than for want of an engine call.
    */
}

/*
    Picks up a dvar changed mid-game. Pausing re-reads the config anyway,
    so this is for the settings the watchers read continuously -- the combo
    above all, which could not otherwise be changed by hand, because
    changing it needs a pause and the combo is what asks for one.

    Not while paused: the HUD is built from these when the pause starts and
    nothing rebuilds it in place.
*/
function zp_config_watcher()
{
    level endon(#"end_game");

    for (;;)
    {
        wait(5);

        if (zp_true(level.zp_paused) || zp_true(level.zp_busy))
        {
            continue;
        }

        zp_load_config();
    }
}


/* ==================================================================
    THE PAUSE

    Four holds, and only the last of them is in doubt. See
    docs/porting-t8.md.
   ================================================================== */

function zp_do_pause(player)
{
    if (zp_true(level.zp_busy) || zp_true(level.zp_paused))
    {
        return;
    }

    level.zp_busy = 1;
    zp_load_config();

    level.zp_paused = 1;
    level.zp_pause_start = gettime();

    if (isdefined(player) && isdefined(player.name))
    {
        level.zp_pauser_name = player.name;
        level.zp_pause_count = level.zp_pause_count + 1;
    }

    level notify(#"zp_paused");

    // 1. The round loop parks itself on this.
    level flag::set("world_is_paused");

    // 2. The spawner gate.
    /*
        Whether it was *set*, not merely whether it exists.

        Spawning is already off between rounds and while some map scripts
        run, and putting back a flag that was not on turns spawning on --
        so a pause taken during a round transition would resume into a
        horde nobody asked for. T7 tests both halves; this tested only the
        first.
    */
    level.zp_spawn_flag_was_set = 0;

    if (level flag::exists("spawn_zombies") && level flag::get("spawn_zombies"))
    {
        level.zp_spawn_flag_was_set = 1;
        level flag::clear("spawn_zombies");
    }

    // 3. The players.
    zp_ease_in();

    zp_freeze_players();

    if (level.zp.control_guard)
    {
        level thread zp_player_enforcer();
    }

    if (level.zp.freeze_clock)
    {
        level thread zp_clock_locker();
    }

    if (level.zp.freeze_powerups || level.zp.freeze_effects)
    {
        level thread zp_powerup_enforcer();
    }

    if (level.zp.freeze_bleedout)
    {
        level thread zp_bleedout_enforcer();
    }

    // 4. The zombies.
    zp_ready_clear();
    zp_freeze_zombies();
    level thread zp_ai_enforcer();

    zp_hud_show();

    if (level.zp.max_pause_time > 0)
    {
        level thread zp_auto_unpause();
    }

    zp_msg_all("^3[Pause]^7 game paused by ^3" + level.zp_pauser_name);
    zp_sound_all(level.zp.pause_sound);

    ShieldLog("ZPause T8: paused by " + level.zp_pauser_name);

    // Everything is held now, so putting time back cannot be seen -- and
    // it means the pause itself runs at ordinary speed however long it
    // lasts.
    zp_ease_settle();

    level.zp_busy = 0;
}

function zp_do_unpause(player)
{
    if (zp_true(level.zp_busy) || !zp_true(level.zp_paused))
    {
        return;
    }

    level.zp_busy = 1;

    /*
        Count it down before letting go. Coming back from a pause straight
        into a horde is how somebody loses a run to a mod that was supposed
        to help, so the same countdown every other port draws happens here
        -- and zp_busy is already set, so nothing can be toggled part way
        through it.
    */
    if (level.zp.countdown > 0 && zp_true(level.zp_hud_up))
    {
        // The clock and the byline go first, and the closing line moves
        // up into the room they leave -- otherwise the countdown reads
        // with a hole in the middle of it.
        level notify(#"zp_clock_off");
        ShieldRemoveHudElem("zp_clock");
        ShieldRemoveHudElem("zp_meta");
        ShieldHudElemSetText("zp_sub", "hold still");

        if (isdefined(level.zp_hud_top))
        {
            ShieldHudElemSetY("zp_sub", level.zp_hud_top + zp_pause_yoff("clock"));
        }

        for (i = level.zp.countdown; i > 0; i--)
        {
            ShieldHudElemSetText("zp_main", "RESUMING IN " + i);
            zp_sound_all(level.zp.countdown_sound);
            wait(1);
        }
    }

    // Drop to the eased rate while everything is still held -- invisible,
    // same as the settle -- so releasing ramps up instead of snapping.
    zp_ease_out();

    level notify(#"zp_thaw");

    zp_hud_hide();
    zp_thaw_zombies();
    zp_thaw_players();

    // Held values are per-pause. Keeping them would write a stale
    // insta-kill window back over a fresh one on the next pause.
    level.zp_held_vars = [];
    zp_ready_clear();

    // A resume vote that is still open when the game resumes has nothing
    // left to decide.
    if (zp_true(level.zp_vote_active))
    {
        zp_vote_stop();
    }

    if (isdefined(level.active_powerups))
    {
        foreach (powerup in level.active_powerups)
        {
            if (isdefined(powerup))
            {
                powerup.zp_held = undefined;
            }
        }
    }

    // Not "player": this function takes one by that name, and a foreach
    // over the same name would quietly overwrite it.
    foreach (p in level.players)
    {
        if (isdefined(p))
        {
            p.zp_bleedout = undefined;
        }
    }

    /*
        A moment of grace on the way out. Controls are back before the
        zombies can reach anybody, which is the point -- the alternative is
        being hit during the frame you got your hands back.
    */
    if (level.zp.grace > 0)
    {
        level thread zp_grace_window();
    }

    // The spawner goes back before the round loop is released, so the
    // round cannot resume into a closed gate.
    if (zp_true(level.zp_spawn_flag_was_set) && level flag::exists("spawn_zombies"))
    {
        level flag::set("spawn_zombies");
    }

    level flag::clear("world_is_paused");

    // Last, so the world is already moving again as time ramps back up.
    zp_ease_release();

    level.zp_paused = 0;
    level.zp_busy = 0;

    zp_msg_all("^3[Pause]^7 resumed");
    zp_sound_all(level.zp.resume_sound);

    ShieldLog("ZPause T8: resumed");
}

/*
    Invulnerable for zp_grace seconds after the world starts again, held
    under our own owner tag so releasing it cannot disturb anything else's
    hold on the same value.
*/
function zp_grace_window()
{
    level endon(#"end_game");
    level endon(#"zp_paused");

    foreach (player in level.players)
    {
        if (isdefined(player))
        {
            player val::set(#"zpause_grace", "takedamage", 0);
        }
    }

    wait(level.zp.grace);

    foreach (player in level.players)
    {
        if (isdefined(player))
        {
            player val::reset(#"zpause_grace", "takedamage");
        }
    }
}

function zp_auto_unpause()
{
    level endon(#"zp_thaw");
    level endon(#"end_game");

    wait(level.zp.max_pause_time);

    zp_do_unpause(undefined);
}


/* ==================================================================
    PLAYERS

    val:: rather than direct calls, tagged #"zpause" so nothing else can
    release our hold and we cannot release anything else's.
   ================================================================== */

function zp_freeze_players()
{
    foreach (player in level.players)
    {
        if (!isdefined(player))
        {
            continue;
        }

        player val::set(#"zpause", "freezecontrols", 1);
        player val::set(#"zpause", "ignoreme", 1);

        if (level.zp.godmode)
        {
            player val::set(#"zpause", "takedamage", 0);
        }

        if (level.zp.blackout)
        {
            player zp_blackout_on();
        }

        if (level.zp.blur)
        {
            player zp_blur_on();
        }
    }
}

/*
    setblur() is a post-process on the client, not a HUD element, so
    there is nothing to destroy -- it has to be zeroed on the way out.
*/
function zp_blur_on()
{
    if (zp_true(self.zp_blurred) || level.zp.blur_amount <= 0)
    {
        return;
    }

    self.zp_blurred = 1;
    self setblur(level.zp.blur_amount, 0.4);
}

function zp_blur_off()
{
    if (!zp_true(self.zp_blurred))
    {
        return;
    }

    self.zp_blurred = undefined;
    self setblur(0, 0.25);
}

/*
    A screen fade rather than a black HUD element, which is what T7 does
    and for the same reason -- there is no material to pull in from an
    injected script. Per player, so a spectator sees what the player it
    is watching sees.
*/
function zp_blackout_on()
{
    if (zp_true(self.zp_black))
    {
        return;
    }

    self.zp_black = 1;
    self lui::screen_fade(0.4, level.zp.blackout_alpha, 0, "black");
}

function zp_blackout_off()
{
    if (!zp_true(self.zp_black))
    {
        return;
    }

    self.zp_black = undefined;

    // Back from the alpha it actually went to, not from 1 -- clearing a
    // partial blackout from full black would flash the screen first.
    self lui::screen_fade(0.4, 0, level.zp.blackout_alpha, "black", 1);
}

/*
    The players' half of the hold: everything the pause did to a player,
    re-applied on a tick, for the one case val:: cannot arbitrate -- a
    script that calls freezecontrols() directly.

    Re-applying a value that is already set is free, so this does not
    check first.
*/
function zp_player_enforcer()
{
    level endon(#"zp_thaw");
    level endon(#"end_game");

    for (;;)
    {
        wait(0.1);

        foreach (player in level.players)
        {
            if (!isdefined(player))
            {
                continue;
            }

            player val::set(#"zpause", "freezecontrols", 1);
            player val::set(#"zpause", "ignoreme", 1);

            if (level.zp.godmode)
            {
                player val::set(#"zpause", "takedamage", 0);
            }
        }
    }
}

function zp_thaw_players()
{
    foreach (player in level.players)
    {
        if (!isdefined(player))
        {
            continue;
        }

        player val::reset(#"zpause", "freezecontrols");
        player val::reset(#"zpause", "ignoreme");
        player val::reset(#"zpause", "takedamage");

        player zp_blackout_off();
        player zp_blur_off();
    }
}


/* ==================================================================
    ZOMBIES

    The open question of this port, and the reason it is written as its own
    pair of functions rather than inline: whatever the answer turns out to
    be, it changes here and nowhere else.

    ignoreall is what stock sets on every zombie at end of game, so it is
    the mildest candidate with real precedent. If it stops them chasing but
    not moving, the next levers are ai::set_behavior_attribute with
    move_mode or control, then pinning the goal to their own position --
    which is what T5 and T4 do in spirit, both of those engines also having
    no single freeze.
   ================================================================== */

function zp_freeze_zombies()
{
    n_held = 0;

    foreach (ai in getaiteamarray(level.zombie_team))
    {
        if (!isactor(ai) || !isalive(ai))
        {
            continue;
        }

        // Read before anything below writes to either of them.
        ai.zp_had_inert = zp_true(ai.is_inert);
        ai.zp_had_cleanup = zp_true(ai.b_ignore_cleanup);

        if (level.zp.engine_freeze)
        {
            ai setentitypaused(1);
        }

        ai.zp_anchor = ai.origin;
        ai val::set(#"zpause", "ignoreall", 1);

        // Stop the cleanup system reclaiming a held zombie, and the
        // round failsafe culling one for standing still.
        ai.b_ignore_cleanup = 1;
        ai.is_inert = 1;

        if (level.zp.silence_zombies)
        {
            ai zp_silence();
        }

        if (level.zp.godmode)
        {
            ai val::set(#"zpause", "takedamage", 0);
        }

        n_held++;
    }

    level.zp_held = n_held;
    ShieldLog("ZPause T8: held " + n_held + " zombies");
}

/*
    Mute one zombie, and cut whatever it is part way through saying.

    var_e8920729 is the flag zm_audio::zmbaivox_playvox returns on, and
    stopsound() is what that same function calls on a zombie to cut a
    lower-priority line short -- so both are used the way stock uses
    them, on the entity stock uses them on.
*/
function zp_silence()
{
    if (!isdefined(self.zp_had_mute))
    {
        self.zp_had_mute = zp_true(self.var_e8920729);
    }

    self.var_e8920729 = 1;

    if (isdefined(self.currentvox))
    {
        self stopsound(self.currentvox);
    }
}

/*
    The backup to the engine freeze, and the whole of the hold when
    zp_engine_freeze is off.

    T6 and T7 both run one of these alongside their engine call rather
    than instead of it, and this port does the same: anything that spawns
    mid-pause, or slips through a spawn already in flight, is caught on
    the next tick rather than left running around a stopped game.

    setgoal( self.origin ) is stock Black Ops 4's own way of stopping an
    AI where it stands -- archetype_elephant and archetype_tiger both do
    it -- and forceteleport is the AI version of setorigin, which is a
    player call on this engine and stops the server on anything else.
*/
function zp_ai_enforcer()
{
    level endon(#"zp_thaw");
    level endon(#"end_game");

    for (;;)
    {
        wait(0.05);

        foreach (ai in getaiteamarray(level.zombie_team))
        {
            if (!isactor(ai) || !isalive(ai))
            {
                continue;
            }

            if (!isdefined(ai.zp_anchor))
            {
                // One that arrived after the pause started.
                ai.zp_had_inert = zp_true(ai.is_inert);
                ai.zp_had_cleanup = zp_true(ai.b_ignore_cleanup);
                ai.zp_anchor = ai.origin;

                if (level.zp.engine_freeze)
                {
                    ai setentitypaused(1);
                }

                ai.b_ignore_cleanup = 1;
                ai.is_inert = 1;

                if (level.zp.silence_zombies)
                {
                    ai zp_silence();
                }

                if (level.zp.godmode)
                {
                    ai val::set(#"zpause", "takedamage", 0);
                }
            }

            ai val::set(#"zpause", "ignoreall", 1);
            ai setgoal(ai.zp_anchor);

            // Cheap, and it catches a line that started between ticks.
            if (level.zp.silence_zombies)
            {
                ai zp_silence();
            }

            if (level.zp.drift_guard &&
                distancesquared(ai.origin, ai.zp_anchor) > level.zp.drift_tolerance)
            {
                ai forceteleport(ai.zp_anchor);
            }
        }
    }
}

/*
    Both flags go back to what they were, rather than to zero.

    They belong to stock, not to us: is_inert is the round failsafe's,
    and leaving it set would exempt every zombie alive during a pause
    from the cull for the rest of the match -- so one that genuinely got
    stuck later would hang the round forever. Stock's own unfreeze()
    restores both the same way, from a struct it saved on the way in.
*/
function zp_thaw_zombies()
{
    foreach (ai in getaiteamarray(level.zombie_team))
    {
        if (!isdefined(ai) || !isactor(ai))
        {
            continue;
        }

        ai setentitypaused(0);

        ai val::reset(#"zpause", "takedamage");
        ai val::reset(#"zpause", "ignoreall");

        if (isdefined(ai.zp_had_inert))
        {
            ai.is_inert = ai.zp_had_inert;
        }

        if (isdefined(ai.zp_had_cleanup))
        {
            ai.b_ignore_cleanup = ai.zp_had_cleanup;
        }

        if (isdefined(ai.zp_had_mute))
        {
            ai.var_e8920729 = ai.zp_had_mute;
        }

        ai.zp_anchor = undefined;
        ai.zp_had_inert = undefined;
        ai.zp_had_cleanup = undefined;
        ai.zp_had_mute = undefined;
    }
}


/* ==================================================================
    WHAT DOES NOT STOP BY ITSELF

    setentitypaused holds entities. None of the four below is an entity:
    the game clock is real time, a powerup times out on a thread, the
    insta-kill and double-points windows burn down in zombie_vars, and a
    downed player's bleedout is a number. Each one is held the way T7
    holds it, against the same field names.
   ================================================================== */

/*
    The game clock runs on real time and level.discardtime is what stock
    subtracts from it, so giving back every tick the pause consumes stops
    the clock without touching it.
*/
function zp_clock_locker()
{
    level endon(#"zp_thaw");
    level endon(#"end_game");

    for (;;)
    {
        currtime = gettime();
        wait(0.05);

        if (isdefined(level.discardtime) && !zp_true(level.timerstopped))
        {
            level.discardtime = level.discardtime + (gettime() - currtime);
        }
    }
}

function zp_powerup_enforcer()
{
    level endon(#"zp_thaw");
    level endon(#"end_game");

    for (;;)
    {
        if (level.zp.freeze_powerups)
        {
            zp_powerups_hold();
        }

        if (level.zp.freeze_effects)
        {
            zp_effects_hold();
        }

        wait(0.05);
    }
}

/*
    A powerup on the floor times out on its own thread. The notify is
    what that thread ends on, so sending it stops the countdown, and the
    show() puts back a powerup already blinking towards its own end.
*/
function zp_powerups_hold()
{
    if (!isdefined(level.active_powerups))
    {
        return;
    }

    foreach (powerup in level.active_powerups)
    {
        if (!isdefined(powerup) || zp_true(powerup.zp_held))
        {
            continue;
        }

        powerup.zp_held = 1;
        powerup notify(#"powerup_reset");
        powerup show();
    }
}

/*
    Insta-kill and double points are windows in zombie_vars, indexed by
    team on this engine exactly as on T7. Holding the value means writing
    the first one seen back over whatever it has counted down to.
*/
function zp_effects_hold()
{
    if (!isdefined(level.zombie_vars) || !isdefined(level.teams))
    {
        return;
    }

    foreach (team in level.teams)
    {
        if (!isdefined(level.zombie_vars[team]))
        {
            continue;
        }

        zp_hold_var(team, "zombie_powerup_insta_kill_time");
        zp_hold_var(team, "zombie_powerup_double_points_time");
        zp_hold_var(team, "zombie_insta_kill");
        zp_hold_var(team, "zombie_point_scalar");
    }
}

function zp_hold_var(team, key)
{
    if (!isdefined(level.zombie_vars[team][key]))
    {
        return;
    }

    id = team + "|" + key;

    if (!isdefined(level.zp_held_vars[id]))
    {
        level.zp_held_vars[id] = level.zombie_vars[team][key];
    }
    else
    {
        level.zombie_vars[team][key] = level.zp_held_vars[id];
    }
}

/*
    A downed player bleeds out on a number, not a timer, so it is held by
    writing back the first value seen. Only for somebody actually down --
    bleedout_time is defined on everybody.
*/
function zp_bleedout_enforcer()
{
    level endon(#"zp_thaw");
    level endon(#"end_game");

    for (;;)
    {
        foreach (player in level.players)
        {
            if (!isdefined(player) || !isdefined(player.bleedout_time))
            {
                continue;
            }

            if (!isdefined(player.revivetrigger) && !zp_true(player.laststand))
            {
                continue;
            }

            if (!isdefined(player.zp_bleedout))
            {
                player.zp_bleedout = player.bleedout_time;
            }
            else
            {
                player.bleedout_time = player.zp_bleedout;
            }
        }

        wait(0.05);
    }
}


/* ==================================================================
    EASING

    Time ramps down into the pause and back up out of it. Both the
    settle and the drop happen while the world is already held, so
    neither can be seen -- what they buy is a pause that runs at
    ordinary speed however long it lasts, and a resume that ramps up
    rather than snapping to full speed.
   ================================================================== */

function zp_ease_scale()
{
    return 0.25;
}

function zp_ease_in()
{
    if (!level.zp.ease || level.zp.ease_time <= 0)
    {
        return;
    }

    setslowmotion(1, zp_ease_scale(), level.zp.ease_time);
    wait(level.zp.ease_time);
}

function zp_ease_settle()
{
    if (!level.zp.ease || level.zp.ease_time <= 0)
    {
        return;
    }

    setslowmotion(zp_ease_scale(), 1, 0);
}

function zp_ease_out()
{
    if (!level.zp.ease || level.zp.ease_time <= 0)
    {
        return;
    }

    setslowmotion(1, zp_ease_scale(), 0);
}

function zp_ease_release()
{
    if (!level.zp.ease || level.zp.ease_time <= 0)
    {
        return;
    }

    setslowmotion(zp_ease_scale(), 1, level.zp.ease_time);
}


/* ==================================================================
    HUD

    Shield's, and the simplest of the five ports. An element is an id we
    choose plus its text, colour, position, anchor, align and scale:

        ShieldRegisterHudElem( id, text, color, x, y,
                               anchor_x, anchor_y, align_x, align_y, scale )

    Nothing is parented, so nothing has to be detached, and the ids are
    fixed strings so there is no handle to lose track of.

    Three things about it are not guessable from that signature, and all
    three were guessed wrong first time round.

    **x and y are real screen pixels measured from the anchor.** Shield
    reads realViewportSize and adds x to it -- there is no virtual 640 x
    480 and no centre origin, so a layout written around the middle of
    the screen lands in the top-left corner at every resolution.

    **anchor and align are 0, 1 or 2, not fractions.** anchor picks the
    point on the screen the element is measured from -- x: 0 left, 1
    centre, 2 right; y: 0 top, 1 middle, 2 bottom -- and align does the
    same for the element's own box, so anchor 2 with align 2 pins a line
    to the right edge whatever it happens to say. Both default to 0,
    which is why everything piled into the corner.

    **The colour is 0xAABBGGRR.** Red is the low byte, not the high one:
    Shield reads `rgba & 0xFF` into red and shifts up from there, so the
    0xRRGGBBAA the parameter name suggests arrives with red and blue
    swapped -- which is how the family gold reached the screen as
    magenta. Alpha 0 reads as fully opaque rather than invisible.
   ================================================================== */

/*
    The family palette, byte-swapped once here rather than at each call.

    Every other port writes these as ( 1, 0.82, 0.15 ), ( 0.85, 0.85,
    0.85 ) and ( 0.7, 0.7, 0.7 ); these are the same three colours in the
    order Shield reads them.
*/
function zp_gold()
{
    return 0xFF26D1FF;
}

function zp_grey()
{
    return 0xFFD9D9D9;
}

function zp_dim()
{
    return 0xFFB3B3B3;
}

function zp_hud_show()
{
    if (!level.zp.hud)
    {
        return;
    }

    // The result of a vote stands in its own slot; only pull it early if
    // this block is about to land on top of it.
    if (level.zp.hud_position == level.zp.vote_hud_position)
    {
        zp_vote_outcome_clear();
    }

    place = zp_hud_place(level.zp.hud_position);

    ax = place["anchor_x"];
    ay = place["anchor_y"];
    lx = place["align_x"];
    x = place["x"];
    y = place["y"];

    // Kept for the countdown, which redraws the block shorter.
    level.zp_hud_top = y;

    // Every line is anchored the same way and stacks downwards, so each
    // one carries the height of the line above it rather than an offset
    // that has to be kept in step by hand.
    ShieldRegisterHudElem("zp_main", "GAME PAUSED", zp_gold(), x, y, ax, ay, lx, 1, 1.1);

    if (level.zp.hud_timer)
    {
        ShieldRegisterHudElem("zp_clock", zp_elapsed_text(), zp_grey(),
                              x, y + zp_pause_yoff("clock"), ax, ay, lx, 1, 0.65);
        level thread zp_clock_updater();
    }

    ShieldRegisterHudElem("zp_meta", "paused by " + level.zp_pauser_name,
                          zp_dim(), x, y + zp_pause_yoff("name"), ax, ay, lx, 1, 0.55);

    ShieldRegisterHudElem("zp_sub", zp_sub_text(), zp_grey(),
                          x, y + zp_pause_yoff("hint"), ax, ay, lx, 1, 0.8);

    /*
        Records that the block is actually on screen, which is not the same
        as zp_hud being on. The config is re-read when a resume is asked
        for, so zp_hud can go from 0 to 1 during a pause -- and the
        countdown would then write to elements that were never created,
        which on this engine is a script error and a dropped match rather
        than a no-op.
    */
    level.zp_hud_up = 1;

}

/*
    Where each line of the block sits, measured down from the top of it.

    These are T7's own offsets in pixels. That port lays its HUD out in a
    480-unit space and this one in real screen pixels, so the conversion
    is 1080 / 480, or 2.25: T7's 34, 58 and 80 become 76, 130 and 180.
    Keeping its ladder rather than deriving one from the font is what
    makes the two read as the same mod -- a spacing worked out from the
    line heights was correct and looked nothing like it, because the
    family's spacing is not proportional to its text.

    The scales are the one thing here that cannot be carried across.
    Everywhere else in the family a scale below 1 draws *larger*, so
    every element asks for 1.0 or more; here it reaches R_AddCmdDrawText
    as a plain multiplier on a font already sized for a full-screen HUD,
    and T7's 1.9 banner filled a third of the screen.
*/
function zp_pause_yoff(line)
{
    if (line == "clock")
    {
        return 76;
    }

    // Everything below the clock closes up when there is no clock.
    if (line == "name")
    {
        if (level.zp.hud_timer)
        {
            return 130;
        }

        return 76;
    }

    // "hint"
    if (level.zp.hud_timer)
    {
        return 180;
    }

    return 130;
}

/*
    Where the block sits: an anchor to measure from, and an offset from it.

    These are T6 and T7's own numbers. Both ports place every element with
    hud::setPoint and both use the same offsets, so those offsets are the
    family spec rather than one port's taste:

        top     CENTER -> TOP     0,  12
        center  CENTER -> TOP     0,  56     the classic banner spot
        middle  CENTER -> CENTER  0, -40
        bottom  CENTER -> BOTTOM  0, -124
        left    LEFT   -> LEFT   24, -46
        right   RIGHT  -> RIGHT -24, -46

    setPoint works in the 640 x 480 virtual HUD space; Shield works in real
    screen pixels. The gaps between lines convert at x2.25 down -- 1080
    over 480 -- and that is confirmed rather than assumed: measured off a
    T6 screenshot, its 34, 58 and 80 land at 77, 130 and 182 pixels.

    The origin does not convert the same way, and this is the part worth
    writing down. TOP on the other ports is the top of level.uiparent,
    which is the safe area rather than the screen, so an offset from it
    starts about 116 pixels down at 1080p. Converting 56 straight to 126
    put the banner most of a line and a half too high; the same T6
    screenshot puts its centre at 208. The inset is added to the two
    top-anchored slots, taken off the bottom-anchored one, and ignored by
    the middle three, where it cancels.

    x for the two side slots is still a straight conversion. Nothing has
    been measured against it, and a horizontal inset would move it the
    same way -- worth checking before anyone trusts left or right.

    The first argument to setPoint is what the offset positions, and on
    every slot but the two side ones it is CENTER. So each line is centred
    on its point rather than hanging below it, which is why every element
    here asks for align_y 1.
*/
function zp_hud_place(position)
{
    place = [];

    // Centred on the screen, and centred on itself, unless said otherwise.
    place["anchor_x"] = 1;
    place["align_x"] = 1;
    place["anchor_y"] = 1;
    place["x"] = 0;

    if (position == "top")
    {
        place["anchor_y"] = 0;
        place["y"] = 143;
        return place;
    }

    if (position == "bottom")
    {
        /*
            Higher than the conversion asks for, because this game keeps
            something there. Black Ops 4 draws the perk icons across the
            bottom centre, and T6's -124 converts to a block whose closing
            line lands on top of them -- the one slot where the other
            ports' number cannot be used as it stands, since it is measured
            against a HUD that has nothing in that corner.
        */
        place["anchor_y"] = 2;
        place["y"] = -460;
        return place;
    }

    if (position == "middle")
    {
        place["y"] = -90;
        return place;
    }

    if (position == "left")
    {
        place["anchor_x"] = 0;
        place["align_x"] = 0;
        place["x"] = 72;
        place["y"] = -103;
        return place;
    }

    if (position == "right")
    {
        place["anchor_x"] = 2;
        place["align_x"] = 2;
        place["x"] = -72;
        place["y"] = -103;
        return place;
    }

    // center -- the classic banner spot, and the default.
    place["anchor_y"] = 0;
    place["y"] = 242;
    return place;
}

/*
    What to do about it. With the combo off there is nothing to tell
    anybody, so it says only that the game is held -- the same thing T5 and
    T4 say in that case.
*/
function zp_sub_text()
{
    if (!level.zp.button_combo)
    {
        return "paused";
    }

    // Words, never bind markers -- Shield draws this one. See
    // zp_combo_label.
    return "hold " + zp_combo_words(level.zp.combo) + " to resume";
}

function zp_hud_hide()
{
    level.zp_hud_up = 0;
    level notify(#"zp_clock_off");
    ShieldRemoveHudElem("zp_main");
    ShieldRemoveHudElem("zp_meta");
    ShieldRemoveHudElem("zp_clock");
    ShieldRemoveHudElem("zp_sub");
}

/*
    Minute granularity, and text rather than a timer element. That is what
    T5 and T4 do, for the same reason a ticking clock is not worth the
    strings it costs -- and this engine's HUD has no timer element at all.
*/
function zp_elapsed_text()
{
    secs = int((gettime() - level.zp_pause_start) / 1000);

    if (secs < 0)
    {
        secs = 0;
    }

    mins = int(secs / 60);

    if (mins > 60)
    {
        return "over an hour";
    }

    if (mins < 1)
    {
        return "under a minute";
    }

    if (mins == 1)
    {
        return "1 minute";
    }

    return mins + " minutes";
}

/*
    Ends on its own notify, not on zp_thaw.

    zp_thaw comes after the countdown, and the countdown is where the
    clock is taken off the screen -- so for those three seconds this was
    still running against an element that no longer existed, and Shield
    stops the server with "can't find hud element" for that.
*/
function zp_clock_updater()
{
    level endon(#"zp_clock_off");
    level endon(#"zp_thaw");
    level endon(#"end_game");

    for (;;)
    {
        wait(5);

        ShieldHudElemSetText("zp_clock", zp_elapsed_text());
    }
}


/* ==================================================================
    INPUT

    The same two-button hold as every other port, with the same combo
    names, the same default and the same fallback while down -- so a
    config written for T6 means the same thing here.

    No chat commands: Black Ops 4 gives a script no say callback to bind
    to, the same as Black Ops 3 and the two Plutonium forks below T6.
   ================================================================== */

function zp_on_connect()
{
    self thread zp_player_think();
    self thread zp_disconnect_watcher();
    self thread zp_input_debug();
    self thread zp_vote_no_watcher();
}

function zp_on_spawned()
{
    // zp_player_think() waits on spawns itself; this is only here so a
    // player who was already in before the script came up gets a watcher.
    if (!zp_true(self.zp_thinking))
    {
        self thread zp_player_think();
    }
}

/*
    Prints which buttons the server actually receives from this player,
    which is how zp_combo and zp_button_combo_dead get chosen -- the set
    that arrives while down is not the set that arrives while standing.
*/
function zp_input_debug()
{
    self endon(#"disconnect");
    level endon(#"end_game");

    for (;;)
    {
        wait(0.5);

        if (!level.zp.input_debug)
        {
            continue;
        }

        txt = "";

        if (self stancebuttonpressed()) { txt = txt + "stance "; }
        if (self usebuttonpressed())    { txt = txt + "use "; }
        if (self fragbuttonpressed())   { txt = txt + "frag "; }
        if (self adsbuttonpressed())    { txt = txt + "ads "; }
        if (self attackbuttonpressed()) { txt = txt + "attack "; }
        if (self meleebuttonpressed())  { txt = txt + "melee "; }
        if (self jumpbuttonpressed())   { txt = txt + "jump "; }

        if (txt == "")
        {
            continue;
        }

        if (zp_true(self.laststand))
        {
            txt = txt + "(down)";
        }

        self iprintln("^3[Pause]^7 " + txt);
    }
}

function zp_player_think()
{
    self endon(#"disconnect");
    level endon(#"end_game");

    if (zp_true(self.zp_thinking))
    {
        return;
    }

    self.zp_thinking = 1;
    self thread zp_button_watcher();

    for (;;)
    {
        self waittill(#"spawned_player");

        // Late joiner, or a respawn into a pause that is already running.
        if (zp_true(level.zp_paused))
        {
            self val::set(#"zpause", "freezecontrols", 1);
        }

        if (level.zp.show_hint)
        {
            self thread zp_hint();
        }
    }
}

function zp_hint()
{
    self endon(#"disconnect");

    wait(8);

    if (!level.zp.button_combo)
    {
        return;
    }

    self iprintln("^3[Pause]^7 hold " + zp_combo_label(level.zp.combo)
                  + " to pause or resume");
}

/*
    Which combo applies to this player right now. Down on the floor, stance
    and melee stop registering, so the fallback takes over -- the same
    switch every other port makes.
*/
function zp_active_combo(standing, downed)
{
    if (!isdefined(standing))
    {
        standing = level.zp.combo;
        downed = level.zp.button_combo_dead;
    }

    if (zp_true(self.laststand))
    {
        return downed;
    }

    return standing;
}

function zp_player_is_spectating(player)
{
    if (!isdefined(player))
    {
        return 0;
    }

    if (isdefined(player.sessionstate) && player.sessionstate == "spectator")
    {
        return 1;
    }

    return !isalive(player);
}

function zp_combo_pressed(combo)
{
    if (combo == "crouch_use")
    {
        return self stancebuttonpressed() && self usebuttonpressed();
    }

    if (combo == "crouch_frag")
    {
        return self stancebuttonpressed() && self fragbuttonpressed();
    }

    if (combo == "crouch_ads")
    {
        return self stancebuttonpressed() && self adsbuttonpressed();
    }

    if (combo == "crouch_melee")
    {
        return self stancebuttonpressed() && self meleebuttonpressed();
    }

    // The two that survive last stand.
    if (combo == "use_frag")
    {
        return self usebuttonpressed() && self fragbuttonpressed();
    }

    // Deliberately excludes use, so it cannot fire while use_frag is held.
    if (combo == "frag_only")
    {
        return self fragbuttonpressed() && !(self usebuttonpressed());
    }

    if (combo == "use_ads")
    {
        return self usebuttonpressed() && self adsbuttonpressed();
    }

    if (combo == "use_attack")
    {
        return self usebuttonpressed() && self attackbuttonpressed();
    }

    if (combo == "attack_ads")
    {
        return self attackbuttonpressed() && self adsbuttonpressed();
    }

    return self jumpbuttonpressed() && self meleebuttonpressed();
}

/*
    What to call the combo on screen: bind markers where the game will
    resolve them -- stock uses [{+activate}] -- and plain words otherwise.

    Which of the two is even possible depends on who is drawing it, and
    that is the divergence on this port. iprintln goes through the game's
    own string handling and turns a marker into the key the player
    actually bound. Shield's HUD hands the string to R_AddCmdDrawText as
    it stands and resolves nothing, so the pause block read "hold
    [{+stance}] + [{+melee}] to resume" on screen, markers and all.

    So zp_hud_binds governs the hint, which can honour it, and the pause
    block always asks for words.
*/
function zp_combo_label(combo)
{
    if (!level.zp.hud_binds)
    {
        return zp_combo_words(combo);
    }

    if (combo == "crouch_use")   { return "[{+stance}] + [{+activate}]"; }
    if (combo == "crouch_frag")  { return "[{+stance}] + [{+frag}]"; }
    if (combo == "crouch_ads")   { return "[{+stance}] + [{+speed_throw}]"; }
    if (combo == "crouch_melee") { return "[{+stance}] + [{+melee}]"; }
    if (combo == "use_frag")     { return "[{+activate}] + [{+frag}]"; }
    if (combo == "frag_only")    { return "[{+frag}]"; }
    if (combo == "use_ads")      { return "[{+activate}] + [{+speed_throw}]"; }
    if (combo == "use_attack")   { return "[{+activate}] + [{+attack}]"; }
    if (combo == "attack_ads")   { return "[{+attack}] + [{+speed_throw}]"; }

    return "[{+gostand}] + [{+melee}]";
}

function zp_combo_words(combo)
{
    if (combo == "crouch_use")   { return "crouch + use"; }
    if (combo == "crouch_frag")  { return "crouch + grenade"; }
    if (combo == "crouch_ads")   { return "crouch + aim"; }
    if (combo == "crouch_melee") { return "crouch + melee"; }
    if (combo == "use_frag")     { return "use + grenade"; }
    if (combo == "frag_only")    { return "grenade"; }
    if (combo == "use_ads")      { return "use + aim"; }
    if (combo == "use_attack")   { return "use + fire"; }
    if (combo == "attack_ads")   { return "fire + aim"; }

    return "jump + melee";
}

/*
    One hold is one toggle. The release wait at the end is what stops a
    held combo toggling over and over.
*/
function zp_button_watcher()
{
    self endon(#"disconnect");
    level endon(#"end_game");

    for (;;)
    {
        wait(0.05);

        if (!level.zp.button_combo)
        {
            continue;
        }

        combo = self zp_active_combo();

        if (combo == "" || !(self zp_combo_pressed(combo)))
        {
            continue;
        }

        held = 0;

        while (self zp_combo_pressed(combo) && held < level.zp.button_hold_time)
        {
            wait(0.05);
            held = held + 0.05;
        }

        if (held < level.zp.button_hold_time)
        {
            continue;
        }

        level thread zp_request_toggle(self);

        while (self zp_combo_pressed(combo))
        {
            wait(0.05);
        }
    }
}


/* ==================================================================
    VOTING

    Ballots live on the players as .zp_vote -- 1 yes, 0 no, undefined for
    not voted yet -- so a disconnect takes its vote with it and every
    count is taken fresh from whoever is actually in the room.

    A serial number rather than a notify ends the watcher: two votes in
    quick succession would otherwise leave the first one's thread running
    against the second one's state.
   ================================================================== */

function zp_host_approving()
{
    return level.zp.host_approve && isdefined(zp_host_player());
}

function zp_player_is_host(player)
{
    host = zp_host_player();

    return isdefined(host) && isdefined(player) && player == host;
}

/*
    Whether a pause has to be put to somebody rather than simply done. In
    approval mode everybody but the host is put to the host, whatever
    zp_vote says, and the host's own pause never waits on anyone.
*/
function zp_vote_wanted(player)
{
    if (zp_host_approving())
    {
        return !zp_player_is_host(player);
    }

    return level.zp.vote && !zp_vote_is_moot(player);
}

function zp_vote_eligible(player)
{
    if (!isdefined(player))
    {
        return 0;
    }

    // An approval is a vote of one. See zp_host_approve.
    if (zp_true(level.zp_vote_approval))
    {
        return zp_player_is_host(player);
    }

    if (!level.zp.vote_alive_only)
    {
        return 1;
    }

    return !zp_player_is_spectating(player);
}

function zp_vote_electorate()
{
    n = 0;

    foreach (player in level.players)
    {
        if (zp_vote_eligible(player))
        {
            n++;
        }
    }

    return n;
}

function zp_vote_needed()
{
    n = zp_vote_electorate();

    if (n < 1)
    {
        return 1;
    }

    needed = level.zp.vote_min;
    pct = int(ceil(n * level.zp.vote_percent / 100));

    if (pct > needed)
    {
        needed = pct;
    }

    // Never ask for more votes than there are people to cast them.
    if (needed > n)
    {
        needed = n;
    }

    if (needed < 1)
    {
        needed = 1;
    }

    return needed;
}

/*
    A vote the initiator alone already carries is a pause with extra steps
    -- solo play, or any lobby whose threshold lands on one.
*/
function zp_vote_is_moot(player)
{
    /*
        With zp_host_only on the host is the only player who can act on a
        pause, so there is nobody to put it to.
    */
    if (level.zp.host_only && isdefined(zp_host_player()))
    {
        return 1;
    }

    if (!level.zp.vote_initiator_yes)
    {
        return 0;
    }

    // A spectator's automatic yes does not count, so it cannot carry a
    // vote on its own however small the room is.
    if (!zp_vote_eligible(player))
    {
        return 0;
    }

    return zp_vote_needed() <= 1;
}

function zp_vote_locked_out()
{
    if (level.zp.vote_lockout <= 0)
    {
        return 0;
    }

    if (level.zp_vote_last_fail == 0)
    {
        return 0;
    }

    return gettime() - level.zp_vote_last_fail < level.zp.vote_lockout * 1000;
}

function zp_vote_count(want)
{
    c = 0;

    foreach (player in level.players)
    {
        if (isdefined(player) && isdefined(player.zp_vote) &&
            player.zp_vote == want && zp_vote_eligible(player))
        {
            c++;
        }
    }

    return c;
}

function zp_vote_clear_ballots()
{
    foreach (player in level.players)
    {
        if (isdefined(player))
        {
            player.zp_vote = undefined;
        }
    }
}

function zp_cast_vote(player, want)
{
    if (!zp_true(level.zp_vote_active) || !isdefined(player))
    {
        return;
    }

    if (isdefined(player.zp_vote) && player.zp_vote == want)
    {
        return;
    }

    player.zp_vote = want;

    if (want)
    {
        player iprintln("^2[Pause]^7 your vote: ^2yes");
    }
    else
    {
        player iprintln("^1[Pause]^7 your vote: ^1no");
    }
}

function zp_vote_start(player, kind)
{
    level.zp_vote_serial = level.zp_vote_serial + 1;
    level.zp_vote_active = 1;
    level.zp_vote_kind = kind;

    /*
        Recorded on the vote rather than read from the dvar while it runs,
        so an ordinary vote opened later cannot inherit an electorate of
        one. Cleared again in zp_vote_stop().
    */
    level.zp_vote_approval = 0;

    if (kind == "pause" && zp_host_approving() && !zp_player_is_host(player))
    {
        level.zp_vote_approval = 1;
    }

    level.zp_vote_end_time = gettime() + int(level.zp.vote_time * 1000);
    level.zp_vote_initiator = player;
    level.zp_vote_provisional = 0;

    level.zp_vote_name = "someone";
    if (isdefined(player) && isdefined(player.name))
    {
        level.zp_vote_name = player.name;
    }

    zp_vote_clear_ballots();

    /*
        The vote HUD stands in for the pause HUD while it is open. They
        would otherwise overlap in any shared slot, and the pause HUD's
        "hold crouch + melee to resume" contradicts the vote, where that
        same combo is a yes.
    */
    zp_hud_hide();

    if (level.zp.vote_initiator_yes && isdefined(player))
    {
        player.zp_vote = 1;
    }

    verb = "pause";
    if (kind == "unpause")
    {
        verb = "resume";
    }

    if (zp_true(level.zp_vote_approval))
    {
        zp_msg_all("^3[Pause]^7 ^3" + level.zp_vote_name + "^7 is asking the host to pause");
    }
    else
    {
        zp_msg_all("^3[Pause]^7 ^3" + level.zp_vote_name + "^7 called a vote to " + verb);
    }

    // The HUD spells out how to vote; only repeat it in chat without one.
    if (!level.zp.vote_hud)
    {
        foreach (voter in level.players)
        {
            if (isdefined(voter))
            {
                voter iprintln("^3[Pause]^7 " + zp_vote_hint_text());
            }
        }
    }

    if (level.zp.vote_hold && kind == "pause" && !zp_true(level.zp_paused))
    {
        level.zp_vote_provisional = 1;
        level thread zp_do_pause(player);
    }

    level thread zp_vote_watcher(level.zp_vote_serial);
}

function zp_vote_watcher(serial)
{
    level endon(#"end_game");

    for (;;)
    {
        if (!zp_true(level.zp_vote_active) || level.zp_vote_serial != serial)
        {
            return;
        }

        needed = zp_vote_needed();
        yes = zp_vote_count(1);
        no = zp_vote_count(0);
        n = zp_vote_electorate();

        left = level.zp_vote_end_time - gettime();
        secs = int(left / 1000);

        if (secs < 0)
        {
            secs = 0;
        }

        zp_vote_hud_update(yes, needed, secs);

        if (yes >= needed)
        {
            zp_vote_finish(1, yes, needed);
            return;
        }

        // Enough noes that everyone left saying yes still would not carry it.
        if (n - no < needed)
        {
            zp_vote_finish(0, yes, needed);
            return;
        }

        if (left <= 0)
        {
            zp_vote_finish(0, yes, needed);
            return;
        }

        wait(0.1);
    }
}

function zp_vote_finish(passed, yes, needed)
{
    kind = level.zp_vote_kind;
    initiator = level.zp_vote_initiator;
    provisional = zp_true(level.zp_vote_provisional);

    zp_vote_stop();

    if (passed)
    {
        zp_msg_all("^2[Pause]^7 vote passed ^2" + yes + "^7/" + needed);
        zp_vote_outcome("^2VOTE PASSED   " + yes + " / " + needed);

        if (kind == "unpause")
        {
            level.zp_last_toggle = gettime();
            level thread zp_do_unpause(initiator);
        }
        else if (!zp_true(level.zp_paused))
        {
            level.zp_last_toggle = gettime();
            zp_begin_pause(initiator);
        }
        else
        {
            // zp_vote_hold already paused us on the way in; all that is
            // left is to give the pause HUD back.
            zp_hud_show();
        }

        return;
    }

    level.zp_vote_last_fail = gettime();
    zp_msg_all("^1[Pause]^7 vote failed ^1" + yes + "^7/" + needed);
    zp_vote_outcome("^1VOTE FAILED   " + yes + " / " + needed);

    // zp_vote_hold pauses on the way in, so a failed vote has to hand the
    // game back.
    if (provisional && zp_true(level.zp_paused))
    {
        level.zp_last_toggle = gettime();
        level thread zp_do_unpause(undefined);
        return;
    }

    // A resume vote that failed leaves the game paused, so the pause HUD
    // comes back.
    if (zp_true(level.zp_paused))
    {
        zp_hud_show();
    }
}

function zp_vote_stop()
{
    level.zp_vote_approval = 0;
    level.zp_vote_serial = level.zp_vote_serial + 1;
    level.zp_vote_active = 0;
    level.zp_vote_provisional = 0;
    level.zp_vote_initiator = undefined;

    zp_vote_clear_ballots();
    zp_vote_hud_destroy();
}


/* ==================================================================
    THE VOTE HUD

    Its own elements rather than the pause block's, because the two can be
    on screen in either order and a shared id would leave whichever was
    torn down second removing the other one's line.
   ================================================================== */

function zp_vote_hud_update(yes, needed, secs)
{
    if (!level.zp.vote_hud)
    {
        return;
    }

    place = zp_hud_place(level.zp.vote_hud_position);

    ax = place["anchor_x"];
    ay = place["anchor_y"];
    lx = place["align_x"];
    x = place["x"];
    y = place["y"];

    title = "VOTE TO PAUSE";
    if (level.zp_vote_kind == "unpause")
    {
        title = "VOTE TO RESUME";
    }

    if (zp_true(level.zp_vote_approval))
    {
        title = "WAITING ON THE HOST";
    }

    ShieldRegisterHudElem("zp_vote_title", title, zp_gold(), x, y, ax, ay, lx, 1, 1.1);

    ShieldRegisterHudElem("zp_vote_clock", yes + " / " + needed + "     " + secs + "s",
                          zp_grey(), x, y + zp_pause_yoff("clock"), ax, ay, lx, 1, 0.8);

    ShieldRegisterHudElem("zp_vote_by", "called by " + level.zp_vote_name,
                          zp_dim(), x, y + zp_pause_yoff("name"), ax, ay, lx, 1, 0.55);

    ShieldRegisterHudElem("zp_vote_hint", zp_vote_hint_text(), zp_grey(),
                          x, y + zp_pause_yoff("hint"), ax, ay, lx, 1, 0.65);

    zp_vote_hud_rows(x, y + zp_pause_yoff("hint") + 34, ax, ay, lx);
}

/*
    One line per player, saying how they voted.

    Shield addresses elements by an id we choose, so the rows are
    zp_vote_row0 upwards and the ones past the player count are removed
    rather than left holding a name that has gone. ZP_VOTE_ROWS is the
    cap; four is the lobby size, and eight is room to spare.
*/
function zp_vote_hud_rows(x, y, ax, ay, lx)
{
    rows = 8;
    i = 0;

    if (level.zp.vote_show_voters)
    {
        foreach (player in level.players)
        {
            if (i >= rows || !isdefined(player))
            {
                continue;
            }

            name = "player";
            if (isdefined(player.name))
            {
                name = player.name;
            }

            if (!zp_vote_eligible(player))
            {
                txt = "^7" + name + "   ^3spectating";
            }
            else if (!isdefined(player.zp_vote))
            {
                txt = "^7" + name + "   ^3-";
            }
            else if (player.zp_vote == 1)
            {
                txt = "^7" + name + "   ^2yes";
            }
            else
            {
                txt = "^7" + name + "   ^1no";
            }

            ShieldRegisterHudElem("zp_vote_row" + i, txt, zp_dim(),
                                  x, y + i * 22, ax, ay, lx, 1, 0.55);
            i++;
        }
    }

    // Anything past the last player goes, or a row keeps a name that
    // left the game.
    while (i < rows)
    {
        ShieldRemoveHudElem("zp_vote_row" + i);
        i++;
    }
}

/*
    How to vote. Words rather than bind markers for the same reason the
    pause block uses them -- Shield draws the string as given.
*/
function zp_vote_hint_text()
{
    if (!level.zp.button_combo)
    {
        return "";
    }

    return "hold " + zp_combo_words(level.zp.combo) + " for yes, "
           + zp_combo_words(level.zp.vote_no_combo) + " for no";
}

function zp_vote_hud_destroy()
{
    ShieldRemoveHudElem("zp_vote_title");
    ShieldRemoveHudElem("zp_vote_clock");
    ShieldRemoveHudElem("zp_vote_by");
    ShieldRemoveHudElem("zp_vote_hint");

    for (i = 0; i < 8; i++)
    {
        ShieldRemoveHudElem("zp_vote_row" + i);
    }
}

/*
    The result, left up for a moment after the vote itself has gone.
*/
function zp_vote_outcome(txt)
{
    if (!level.zp.vote_hud || level.zp.vote_result_time <= 0)
    {
        return;
    }

    level thread zp_vote_outcome_hold(txt);
}

function zp_vote_outcome_hold(txt)
{
    level notify(#"zp_vote_outcome");
    level endon(#"zp_vote_outcome");
    level endon(#"end_game");

    place = zp_hud_place(level.zp.vote_hud_position);

    ShieldRegisterHudElem("zp_vote_result", txt, zp_grey(), place["x"], place["y"],
                          place["anchor_x"], place["anchor_y"], place["align_x"], 1, 0.9);

    wait(level.zp.vote_result_time);

    ShieldRemoveHudElem("zp_vote_result");
}

function zp_vote_outcome_clear()
{
    level notify(#"zp_vote_outcome");
    ShieldRemoveHudElem("zp_vote_result");
}

/*
    The no side of the input. The resume combo is a yes while a vote is
    open, so no needs a combo of its own -- and it has to survive last
    stand the same way, which is what the second pair is for.
*/
function zp_vote_no_watcher()
{
    self endon(#"disconnect");
    level endon(#"end_game");

    for (;;)
    {
        wait(0.05);

        if (!zp_true(level.zp_vote_active) || !level.zp.button_combo)
        {
            continue;
        }

        combo = self zp_active_combo(level.zp.vote_no_combo, level.zp.vote_no_combo_dead);

        if (!(self zp_combo_pressed(combo)))
        {
            continue;
        }

        held = 0;

        while (zp_true(level.zp_vote_active) && (self zp_combo_pressed(combo)) &&
               held < level.zp.button_hold_time)
        {
            held = held + 0.05;
            wait(0.05);
        }

        if (held < level.zp.button_hold_time)
        {
            continue;
        }

        zp_cast_vote(self, 0);

        while (self zp_combo_pressed(combo))
        {
            wait(0.05);
        }

        wait(0.5);
    }
}


/* ==================================================================
    REQUESTS
   ================================================================== */

/*
    The host, or undefined when there is not one.

    Black Ops 4 ships this test itself, the same as Black Ops 3, and the
    engine's own answer beats a guess at one: gethostplayer() walks the
    players asking isHost(). The two Plutonium ports below T6 check for
    entity number 0 instead, because that is what their stock get_host()
    does -- nothing says a newer engine numbers its players the same way.
*/
function zp_host_player()
{
    return util::gethostplayer();
}

/*
    True when zp_host_only should turn this request away. Says so once
    rather than failing silently, since a combo that does nothing reads
    as a broken mod.
*/
function zp_host_blocked(player)
{
    if (!level.zp.host_only)
    {
        return 0;
    }

    host = zp_host_player();

    // Nobody is the host, so there is nothing to restrict to.
    if (!isdefined(host))
    {
        return 0;
    }

    if (isdefined(player) && player == host)
    {
        return 0;
    }

    if (isdefined(player))
    {
        player iprintln("^1[Pause]^7 only the host can pause");
    }

    return 1;
}


/* ==================================================================
    THE READINESS CHECK

    Deliberately not a vote. Nobody says no, it cannot fail, and it
    needs no zp_vote to be on -- while it is running the resume input
    marks you ready rather than resuming, and the last person to press
    it is what starts the game again.
   ================================================================== */

/*
    The sub-line is the natural place for the tally: it is otherwise
    telling people to hold a combo to resume, which is not what the
    combo does right now.
*/
function zp_ready_show(have, needed)
{
    if (!level.zp.hud || !zp_true(level.zp_paused))
    {
        return;
    }

    if (have < 1 && needed < 1)
    {
        ShieldHudElemSetText("zp_sub", zp_sub_text());
        return;
    }

    ShieldHudElemSetText("zp_sub", "READY  " + have + " / " + needed);
}

function zp_ready_clear()
{
    foreach (player in level.players)
    {
        if (isdefined(player))
        {
            player.zp_ready = undefined;
        }
    }
}

function zp_ready_count()
{
    c = 0;

    foreach (player in level.players)
    {
        if (isdefined(player) && zp_true(player.zp_ready))
        {
            c++;
        }
    }

    return c;
}

function zp_ready_needed()
{
    n = level.players.size;

    if (n < 1)
    {
        return 1;
    }

    needed = int(ceil(n * level.zp.ready_percent / 100));

    // Never ask for more people than are here to answer.
    if (needed > n)
    {
        needed = n;
    }

    if (needed < 1)
    {
        needed = 1;
    }

    return needed;
}

/*
    Somebody saying they are back.
*/
function zp_mark_ready(player)
{
    if (isdefined(player))
    {
        if (zp_true(player.zp_ready))
        {
            return;
        }

        player.zp_ready = 1;
        player iprintln("^2[Pause]^7 you are ready");
    }

    needed = zp_ready_needed();
    have = zp_ready_count();

    if (have < needed)
    {
        zp_ready_show(have, needed);
        return;
    }

    zp_ready_show(0, 0);
    level.zp_last_toggle = gettime();
    level thread zp_do_unpause(player);
}

function zp_on_cooldown()
{
    return level.zp.cooldown > 0 &&
           gettime() - level.zp_last_toggle < int(level.zp.cooldown * 1000);
}

function zp_pauses_spent()
{
    return level.zp.max_pauses > 0 && level.zp_pause_count >= level.zp.max_pauses;
}

function zp_request_toggle(player)
{
    if (zp_true(level.zp_paused))
    {
        zp_request_unpause(player);
    }
    else
    {
        zp_request_pause(player);
    }
}

function zp_request_pause(player)
{
    zp_load_config();

    if (zp_host_blocked(player))
    {
        return;
    }

    if (zp_true(level.zp_busy) || zp_true(level.zp_paused))
    {
        return;
    }

    if (!zp_game_ready())
    {
        return;
    }

    if (zp_pauses_spent())
    {
        if (isdefined(player))
        {
            player iprintln("^1[Pause]^7 no pauses left this match");
        }

        return;
    }

    /*
        With a vote already open, the pause combo is a ballot rather than
        a request -- pressing it again is how you say yes.
    */
    if (zp_true(level.zp_vote_active))
    {
        zp_cast_vote(player, 1);
        return;
    }

    if (zp_on_cooldown())
    {
        return;
    }

    if (zp_vote_wanted(player))
    {
        if (zp_vote_locked_out())
        {
            if (isdefined(player))
            {
                player iprintln("^1[Pause]^7 a vote just failed -- wait a moment");
            }

            return;
        }

        level.zp_last_toggle = gettime();
        level thread zp_vote_start(player, "pause");
        return;
    }

    level.zp_last_toggle = gettime();
    zp_begin_pause(player);
}

/*
    The last step of a pause request, once whatever had to agree has.
    Either it happens now, or it waits for the round to be over.

    A player dropping does not come through here: that pauses at once,
    since waiting for the round to end is the opposite of what is wanted
    when somebody has already gone.
*/
function zp_begin_pause(player)
{
    if (!level.zp.round_pause)
    {
        level thread zp_do_pause(player);
        return;
    }

    if (zp_true(level.zp_pending))
    {
        level.zp_pending = 0;
        level.zp_pending_by = undefined;
        zp_msg_all("^3[Pause]^7 end-of-round pause called off");
        return;
    }

    level.zp_pending = 1;
    level.zp_pending_by = player;

    zp_msg_all("^3[Pause]^7 pausing at the end of the round -- ask again to call it off");
}

/*
    Fires a held pause at the round boundary.
*/
function zp_round_watcher()
{
    level endon(#"end_game");

    for (;;)
    {
        level waittill(#"end_of_round");

        if (!zp_true(level.zp_pending))
        {
            continue;
        }

        level.zp_pending = 0;
        by = level.zp_pending_by;
        level.zp_pending_by = undefined;

        zp_load_config();

        if (zp_true(level.zp_paused) || zp_true(level.zp_busy) || !zp_game_ready())
        {
            continue;
        }

        level.zp_last_toggle = gettime();
        level thread zp_do_pause(by);
    }
}

/*
    Pause when somebody drops, if that is asked for.

    The config is read fresh rather than trusted: this waits out the
    whole match before it decides anything.
*/
function zp_disconnect_watcher()
{
    level endon(#"end_game");

    self waittill(#"disconnect");

    zp_load_config();

    if (!level.zp.pause_on_disconnect)
    {
        return;
    }

    if (zp_true(level.zp_paused) || zp_true(level.zp_busy) || !zp_game_ready())
    {
        return;
    }

    // Nobody left to start it again.
    if (level.players.size < 1)
    {
        return;
    }

    zp_msg_all("^3[Pause]^7 somebody dropped -- paused");
    level.zp_last_toggle = gettime();
    level thread zp_do_pause(undefined);
}

function zp_request_unpause(player)
{
    zp_load_config();

    if (zp_host_blocked(player))
    {
        return;
    }

    if (zp_true(level.zp_busy) || !zp_true(level.zp_paused))
    {
        return;
    }

    // Same as the pause side: with a vote open, the combo is a ballot.
    if (zp_true(level.zp_vote_active))
    {
        zp_cast_vote(player, 1);
        return;
    }

    if (zp_on_cooldown())
    {
        return;
    }

    /*
        With the readiness check on, the resume input is not a resume --
        it is one person saying they are back. The last one to press it
        is what actually starts the game.
    */
    if (level.zp.ready_check)
    {
        zp_mark_ready(player);
        return;
    }

    if (level.zp.vote && level.zp.vote_unpause && !zp_vote_is_moot(player))
    {
        if (zp_vote_locked_out())
        {
            if (isdefined(player))
            {
                player iprintln("^1[Pause]^7 a vote just failed -- wait a moment");
            }

            return;
        }

        level.zp_last_toggle = gettime();
        level thread zp_vote_start(player, "unpause");
        return;
    }

    level.zp_last_toggle = gettime();
    zp_do_unpause(player);
}
