# ZPause T8 — a synced co-op pause for Black Ops 4 zombies

Hold **crouch + melee** and the game stops: zombies, spawns, the round, everybody's
controls. Hold it again and it counts you back in. Everyone sees it, nobody has to trust
anybody else to alt-tab quietly.

For **Black Ops 4** on [Project BO4 / Shield](https://shield-client.gitbook.io/shield-documentation/).
Part of the ZPause family — the same mod exists for
[Black Ops III](https://github.com/Xeptix/ZPauseT7),
[Black Ops II](https://github.com/Xeptix/ZPause),
[Black Ops](https://github.com/Xeptix/ZPauseT5) and
[World at War](https://github.com/Xeptix/ZPauseT4). Same settings, same names, same
defaults, so one config carries across all five.

> **This is the newest port.** It carries 58 of the other ports' 62 settings and shares
> their version number. The four it does not have are `zp_hud_glow`, `zp_hud_panel`,
> `zp_hud_panel_alpha` and `zp_hud_panel_width` — Black Ops 4 has no scriptable HUD to put
> a shader in. `zp_blackout` does their job instead; see **Not here yet**.

## Requirements

- Black Ops 4 with Project BO4 / Shield
- Only the **host** needs it. Nobody else has to install anything.

## Install

Run **`installer/windows/install.bat`** and press Enter. It finds Black Ops 4 — every Steam
library Steam knows about, plus the `Games`, `COD` and `Call of Duty` folders on any drive —
copies the mod in, and remembers where it went, so the next run asks nothing.

It is the same installer that ships with every ZPause download: it knows all five games,
and a copy kept on your PC can install any of them, fetching a game's release from GitHub
when the files are not beside it.

On Linux, `installer/linux/install.sh`, or the **Install ZPause** desktop entry beside it
in Steam Deck's desktop mode. KDE will not run a desktop entry until you tick *Is
executable* in its properties.

```
install.bat -Find              report what it found, change nothing
install.bat -List              what is installed, then stop
install.bat -Install -Yes      install, asking nothing
install.bat -Uninstall -Yes    put it back as it was
install.bat -Configure         open the settings editor
install.bat -To "X:\Games\BlackOps4"
```

It backs up anything it replaces before replacing it, and logs every write to
`%LOCALAPPDATA%\ZPause\zpause.log`. Removing takes out the files it wrote and nothing else;
the folder itself is left where it was.

Or do it by hand — Shield reads a mod folder, so there is only one place it goes:

```
project-bo4\mods\zpause\metadata.json
project-bo4\mods\zpause\zpause.gscc
project-bo4\mods\zpause\zpause_lobby.luac
```

Start a zombies match. `project-bo4.log` will say so:

```
[ INFO ] loading mod ZPause...
[ INFO ] [ GSC VM ] ZPause T8 loaded
```

**The settings editor** is `install.bat -Configure`, or item 4 in the menu. It is the
same editor the other ports have — sections, search, profiles, import and export — but it
applies your settings differently, and has to: theirs write new defaults into the installed
script, and what installs here is compiled — nothing to rewrite. So the names come from
`zpause.settings`, written from the script on every build, and your values go to
`project-bo4\saved\server\zpause.json`, which the script reads when it loads, and to the
lobby menu's file beside it. It opens on what those files already hold, so a change made in
game is there to see. A dvar set in the console still wins over the file, the same way it
wins over a rewritten default elsewhere. Editing takes effect on the next match.

## Usage

**Hold crouch + melee for about a third of a second.** The game stops and everybody sees
`GAME PAUSED`, who paused it, and how long it has been. Hold the same two buttons again and
it counts down from three before letting go, with a moment of invulnerability on the way
out so nobody loses a run to the frame they got their hands back.

Down on the floor, stance and melee stop registering — so while down the combo becomes
**use + aim**, which survives it. `zp_button_combo_dead` changes that.

There are no chat commands. Shield registers no chat function for a script and has no chat
component at all, so this is the one port without them.

### Who decides

Five settings answer the same question — who may pause, and who has to agree. They can all
be on at once, so this is the order the script applies them in.

**Asking to pause:**

| | Setting | What happens |
|---|---|---|
| 1 | `zp_host_only` | Anybody but the host is turned away here. Nothing below runs for them. |
| 2 | — | Refused while the game is still starting. |
| 3 | `zp_max_pauses` | Refused once the match has spent its budget. |
| 4 | — | With a vote already open, the input is a yes instead. |
| 5 | `zp_cooldown` | Refused if the last pause was too recent. |
| 6 | `zp_host_approve` | A non-host's ask goes to the host to answer. **Takes precedence over `zp_vote`.** |
| 7 | `zp_vote` | Otherwise, with voting on, it goes to a vote. |
| 8 | `zp_round_pause` | Once it is agreed — outright, approved or voted — it waits for the round to end instead of happening now. Asking again calls it off. |

**Asking to resume:**

| | Setting | What happens |
|---|---|---|
| 1 | `zp_host_only` | Anybody but the host is turned away. |
| 2 | — | With a vote already open, the input is a yes instead. |
| 3 | `zp_cooldown` | Refused if the last toggle was too recent. |
| 4 | `zp_ready_check` | The input marks you ready rather than resuming. **Takes precedence over `zp_vote_unpause`.** |
| 5 | `zp_vote_unpause` | Otherwise, with `zp_vote` on as well, it goes to a vote. |

Three things sit outside all of that:

- **`zp_max_pause_time` ends a pause whatever else is set.** It is the way out of a ready
  check nobody answers, or a request the host never sees. Leave it at `0` and there is no
  way out but somebody pressing something.
- **A pause nobody asked for skips the lot.** `zp_pause_on_disconnect` pauses immediately:
  it does not wait for the round, does not spend the budget, and asks nobody.
- **`zp_host_only` with `zp_host_approve` is just `zp_host_only`.** The first turns the
  request away before there is anything left to approve.

### The settings menu

While the game is paused, the host can change ZPause's settings without the console. Hold
**fire + melee** to open the menu:

| Button | Does |
|---|---|
| aim / fire | move up and down the list |
| grenade | change the setting |
| melee | close |

A switch flips, a list moves on to its next choice, and a number steps up through a few
common values and back round to the lowest — exact values are still the console's. A
change lands when play resumes, the same as one typed into the console, and is saved as the
menu closes — see [Where settings are saved](#where-settings-are-saved). The menu closes
itself when a vote opens, since the host needs the buttons back to vote. `zp_menu 0` turns
it off.

**Everybody sees it on this game.** Shield's HUD elements belong to the screen rather than
to one player, so the room watches the host change things; only the host's buttons move
it. It draws as text in whichever half of the screen the pause banner isn't using.

#### In the lobby

The same settings are in the lobby too. In a zombies lobby, open the custom game setup —
the page with Shield's difficulty setting — and the host gets a **ZPause Settings** button
above that list. It opens a page laid out like Shield's own settings: a tab for each part
of ZPause, the settings under it, and what the setting under the cursor does and what its
default is beside them. Left and right change a setting. **DEFAULT** leaves it to the
script's own default — or to the one the installer wrote, if you configured it there — and
**Reset to Defaults** puts every setting back there at once.

A change made there is saved as you make it, so it is still set the next time the game
starts, and a match picks it up as it loads.

## Configuration

Every setting is a dvar, and on this engine each one is **registered** with the console —
type `zp` and they complete, showing the value, the default and the domain. That is
something the Black Ops III port cannot do, where the dvars work but never appear.

The config is re-read every five seconds while the game runs, and again whenever a
pause is requested, so a change takes effect almost straight away with no map restart. The
periodic re-read is skipped while paused, because the HUD is built from these when the
pause starts.

### Where settings are saved

Black Ops 4 keeps no dvar of its own between sessions, so what makes a setting permanent
here is a file — two, beside each other:

```
project-bo4\saved\server\zpause.json
project-bo4\saved\server\zpause_lobby.json
```

`zpause.json` is the one the script reads as a match loads. The pause menu writes it as
the menu closes and the installer's config editor writes it whenever you save, so a
setting changed in either is what the other shows next time. It supplies the **default**
for each setting, so anything set in the console outranks it while the game is running.

`zpause_lobby.json` is the lobby menu's. The lobby saves each change there as you make it,
and puts them back as the game starts, ahead of `zpause.json`. The installer writes it
along with `zpause.json`, so the two always agree after you save there; and closing the
pause menu after a change clears it, since everything the lobby had set is in
`zpause.json` by then. Only settings that differ from their default are listed in either,
which is what keeps a default that changes in a later version applying to everything you
never touched.

| Dvar | Default | What it does |
|---|---|---|
| `zp_button_combo` | `1` | Enable the button combo. |
| `zp_button_hold_time` | `0.3` | How long the combo must be held. |
| `zp_combo` | `crouch_melee` | Which two buttons: `crouch_melee`, `crouch_use`, `crouch_frag`, `crouch_ads`, `use_frag`, `use_ads`, `use_attack`, `attack_ads`, `frag_only`, or `jump_melee`. |
| `zp_button_combo_dead` | `use_ads` | The combo used while down, when stance and melee stop registering. |
| `zp_input_debug` | `0` | Print each player which buttons the server receives from them, for picking the two above. |
| `zp_allow_short_words` | `0` | **No effect on this engine** — there are no chat commands to widen. |
| `zp_only_script` | `0` | **No effect on this engine** — Shield loads one mod folder, so there is no second copy to turn off. |
| `zp_only_mod` | `0` | The same, the other way round. |
| `zp_menu` | `1` | Let the host change settings from a menu while the game is paused: hold fire and melee to open it. |
| `zp_host_only` | `0` | Only the host can pause or resume. Everyone else's combo is ignored. On a dedicated server there is no host, so it turns itself off rather than locking everybody out. |
| `zp_ready_check` | `0` | Resuming waits for the players to say they're back. Not a vote — nobody says no and it can't fail. |
| `zp_ready_percent` | `100` | How much of the room has to be ready. `100` is everybody. |
| `zp_host_approve` | `0` | The host pauses at once; anyone else has to ask and the host answers yes or no. It runs as a vote only the host can cast, so the yes/no input, the HUD and the timeout are a vote's. Pausing only — resuming still follows `zp_vote`. `zp_host_only` wins where both are set. |
| `zp_vote` | `0` | Put pauses to a vote. |
| `zp_vote_min` | `2` | Minimum yes votes, whatever the player count. |
| `zp_vote_percent` | `51` | Percent of players who must vote yes. |
| `zp_vote_time` | `30` | Seconds a vote stays open. |
| `zp_vote_unpause` | `0` | Resuming needs a vote too. |
| `zp_vote_hold` | `0` | Freeze the game while the vote runs, and resume it if the vote fails. |
| `zp_vote_initiator_yes` | `1` | Whoever called the vote counts as a yes. |
| `zp_vote_lockout` | `10` | Seconds before another vote can be called after one fails. |
| `zp_vote_hud` | `1` | Show the vote tally on screen. |
| `zp_vote_show_voters` | `1` | List each player and how they voted. |
| `zp_vote_hud_position` | `top` | Where the vote tally sits. Same slots as `zp_hud_position`. |
| `zp_vote_alive_only` | `1` | Leave bled-out spectators out of the threshold and the count. |
| `zp_vote_result_time` | `2` | Seconds the result stands on the tally after a vote resolves. `0` = clear at once. |
| `zp_vote_no_combo` | `jump_melee` | Combo for a no vote. Same list as `zp_combo`. |
| `zp_vote_no_combo_dead` | `use_attack` | The same, for a no vote while down. |
| `zp_countdown` | `3` | Seconds counted down before the game starts again. `0` resumes at once. |
| `zp_grace` | `2` | Seconds of invulnerability after resuming. |
| `zp_cooldown` | `2` | Seconds before the pause can be toggled again. |
| `zp_max_pause_time` | `0` | Resume automatically after this many seconds. `0` is no limit. |
| `zp_max_pauses` | `0` | How many times one match can be paused. `0` is no cap. |
| `zp_ease` | `1` | Ease time down into the pause and back out, instead of cutting to a stop. |
| `zp_ease_time` | `0.35` | Seconds of ramp at each end. |
| `zp_round_pause` | `0` | Hold a pause until the round is over instead of freezing the game mid-horde. Asking again calls it off. |
| `zp_pause_on_disconnect` | `0` | Pause when somebody drops, so whoever is left isn't overrun while they rejoin. Nothing un-pauses on its own, so `zp_max_pause_time` is the way out if they don't come back. |
| `zp_godmode` | `1` | Nobody can be hurt while paused. |
| `zp_freeze_players` | `1` | Lock players in place while paused. `0` lets them walk around with their weapons down, locked again for the countdown — not recommended, because doors, the box, perks, traps and pickups can all still be used while the zombies are held. |
| `zp_engine_freeze` | `1` | Use `setentitypaused()`, the call stock's own AI freeze is built on. |
| `zp_drift_guard` | `1` | Snap back any AI that still manages to move. |
| `zp_freeze_anims` | `1` | **No effect on this engine** — the entity pause already stops animation. |
| `zp_silence_zombies` | `1` | Stop zombies growling while paused. |
| `zp_control_guard` | `1` | Re-apply the freeze on a tick, in case another script releases somebody mid-pause. |
| `zp_freeze_clock` | `1` | Hold the match timer. |
| `zp_freeze_powerups` | `1` | Stop ground powerups timing out. |
| `zp_freeze_effects` | `1` | Hold insta-kill / double-points countdowns. |
| `zp_freeze_bleedout` | `1` | Stop downed players bleeding out. |
| `zp_hud` | `1` | Draw the pause block at all. |
| `zp_hud_position` | `center` | Where it sits: `center`, `top`, `middle`, `bottom`, `left` or `right`. |
| `zp_hud_timer` | `1` | Show how long the pause has run. |
| `zp_show_hint` | `1` | Tell players how to pause when they spawn. |
| `zp_hud_binds` | `1` | Show the combo as key names rather than plain words. Applies to the spawn hint; the pause block always uses words. |
| `zp_blackout` | `1` | Dim everyone's screen while paused, which keeps the pause text readable over a bright skybox. Raise `zp_blackout_alpha` for the anti-scouting blackout this used to be. |
| `zp_blackout_alpha` | `0.2` | How far it dims. `0.2` is a light darkening; `1` is fully black. |
| `zp_blur` | `1` | Blur the screen while paused. |
| `zp_blur_amount` | `2` | How much. `1.5` reads as a step back without hiding the game. |
| `zp_pause_sound` | `zmb_bgb_plainsight_start` | Played to everyone on pause. `none` for silence. |
| `zp_countdown_sound` | `zmb_trap_ready` | Played on each countdown tick. |
| `zp_resume_sound` | `zmb_bgb_plainsight_end` | Played when play resumes. |

## How it works

**The round loop stops itself.** `scripts/zm_common/zm_round_logic.gsc` already waits on
the `world_is_paused` flag, so setting it parks the round with no stock script patched —
the same gift the Black Ops III port gets.

**The spawner gate** is the `spawn_zombies` flag, as on every port.

**Players are held through `val::`**, Black Ops 4's arbitrated value system:
`val::set(#"zpause", "freezecontrols", 1)` with a matching `val::reset`. That is better
than the direct calls the other ports make — an unrelated system releasing its own hold
cannot release ours, and ours cannot stomp anybody else's.

**The zombies stop at the engine.** Black Ops 4 has no `disablezombies()` — the call the
Black Ops II and III ports lean on — and its own `pause_zombies()` clears the field rather
than freezing it. It has `setentitypaused()` instead, which is what stock's own AI
`freeze()` uses and what the two teleporter maps park a zombie with. So this port holds
the horde the way Black Ops II and III do, not the way Black Ops and World at War have to.

An enforcer runs alongside it, exactly as it does on those two ports: `ignoreall` and a
pinned goal on a tick, so anything that spawns mid-pause or slips through a spawn already
in flight is caught rather than left running around a stopped game. `zp_drift_guard` puts
back anything that moves anyway. A zombie still on its way in through a window keeps its own
goal instead: its walk ends the moment it is at its goal, and what it plays next is lined up
against the window, so a goal at its feet would read as arrival.

Two stock flags go with it, both saved and put back on resume rather than cleared.
`b_ignore_cleanup` keeps the cleanup system from reclaiming a held zombie, and `is_inert`
keeps `round_spawn_failsafe` — which kills anything that has not moved 24 units in 30
seconds — from culling the whole horde. Stock's `unfreeze()` restores the same pair the
same way.

**Four things do not stop by themselves.** `setentitypaused` holds entities, and none of
these is one: the match clock runs on real time, a ground powerup times out on its own
thread, the insta-kill and double-points windows burn down in `zombie_vars`, and a downed
player's bleedout is a number. Each is held the way the Black Ops III port holds it, against
the same field names — `level.discardtime`, `level.active_powerups`,
`level.zombie_vars[team]` and `bleedout_time` all exist here unchanged.

**The HUD is Shield's**, not the game's, and it is the one part measured in real screen
pixels rather than a fixed grid. Each slot is anchored to the edge or the centre it is
named after, so the block sits in the same place at any resolution. `left` and `right` pin
it to that edge rather than centring it near it — a line long enough to say `hold crouch +
melee to resume` does not fit beside the edge any other way.

It also draws its text directly, without the pass that turns `[{+melee}]` into the key you
actually bound. So the pause block names the buttons in words on this port, and
`zp_hud_binds` applies to the spawn hint, which is an `iprintln` and does resolve them.

Text is all it draws, which is why `zp_hud_glow` and `zp_hud_panel` are the two settings
this port does not have. That is not Shield being thin — **Black Ops 4 has no scriptable
HUD at all.** Its GSC element creators live inside developer blocks and build on
`newdebughudelem`; there are 49 uses of that in the stock scripts and every one is
dev-only, while `newhudelem`, `newclienthudelem` and `createserverfontstring` do not exist
in the game. The real HUD is LUI, which a server script cannot reach. Drawing its own text
is the only reason Shield can put anything on screen.

A glow needs a shader behind a line and a panel needs a slab behind the block, and neither
is something text can be. **`zp_blackout` covers what they were for.** It is on by default
on all five ports at `0.2` — a light dimming that keeps the pause text readable over a
bright skybox, which is the job the glow does on the other four.

Shield can register a LUI file of its own, and that route was taken far enough to know it
is not a dead end: the file loads against the Zombies/Hud hook, a `UIImage` paints a solid
rectangle at real pixel co-ordinates, and Shield's text draws **over** it rather than under.
What stopped it is the last link — a `luinotifyevent` from the script never reaches a
handler registered on the LUI root, so the script cannot tell the panel when to appear.
`docs/porting-t8.md` has the whole of what was learned, for anyone who wants to finish it.

See `docs/porting-t8.md` in the project tree for the survey behind all of it.

## Not here yet

Everything the other four ports do is here, bar the HUD glow and panel: `zp_hud_glow`,
`zp_hud_panel`, `zp_hud_panel_alpha` and `zp_hud_panel_width` all need a shader behind the
text, and Black Ops 4 has no scriptable HUD to put one in. `zp_blackout` does their job
instead — see **How it works**.

Three more settings are carried but do nothing — `zp_allow_short_words`, `zp_only_script`
and `zp_only_mod` — so that one config file reads the same on all five games.

Nothing else is missing. `zp_blur` and `zp_silence_zombies` were the last two open
questions and both are answered: the blur is the same `setblur()` the other ports call, and
zombies go quiet through the same vox flag Widow's Wine uses to shut them up.

## Ports

| Game | Repo |
|---|---|
| Black Ops 4 (T8) | ZPauseT8 — you are here |
| Black Ops III (T7) | [ZPauseT7](https://github.com/Xeptix/ZPauseT7) |
| Black Ops II (T6) | [ZPause](https://github.com/Xeptix/ZPause) |
| Black Ops (T5) | [ZPauseT5](https://github.com/Xeptix/ZPauseT5) |
| World at War (T4) | [ZPauseT4](https://github.com/Xeptix/ZPauseT4) |

Versions are kept in step: the same version number means the same feature set, allowing
for what each engine can actually do.

---

## Changelog

### v1.5

- **A zombie paused on its way in through a window picks up where it was.** The pause holds
  zombies with `setentitypaused()` and, behind it, pins each one's goal to where it stands.
  A zombie's walk to a window ends the moment it is at its goal, and what it plays next is
  lined up against the window — so a goal at its feet reads as arrival, and the resume put
  it onto the window. While the engine freeze holds it, a zombie that isn't through its
  window yet keeps the goal the game gave it, which is how stock's own `freeze()` holds it.

- **`zp_freeze_players`** — set it to `0` and players can walk around a paused game with
  their weapons down, and are locked again for the countdown back in. Players are still
  locked by default, and roaming isn't recommended: doors, the box, perks, traps and
  pickups can all still be used while the zombies are held.

- **A settings menu for the host.** While the game is paused, hold **fire + melee** to
  change ZPause's settings without the console: aim and fire move through the list,
  grenade changes the setting, melee closes it. Everybody sees it on this game. See
  [The settings menu](#the-settings-menu); `zp_menu` turns it off.

- **The same settings in the lobby.** The zombies custom game setup, where Shield puts its
  difficulty setting, gets a **ZPause Settings** button for the host, with a tab for each
  part of ZPause, what each setting does and its default, and Reset to Defaults. See
  [In the lobby](#in-the-lobby).

- **Settings are kept wherever you change them.** The pause menu saves to
  `zpause.json` as it closes, the lobby saves as you go, and the installer's config editor
  opens on what either of them saved. See
  [Where settings are saved](#where-settings-are-saved).

- **`none` empties a setting from the console.** `set zp_pause_sound ""` was put back to
  its default the next time the config was read. `none` does it from the console, the
  config file or the settings menu.

- **The installer's `-To` works when it already remembers a folder.** It was only read when
  the installer had to ask where the game is, so once it remembered one, `-To` was ignored.
  It comes first now, for that run, and a `-To` that is not the game's folder says so. On
  Linux, the question itself now shows when the installer has to ask.

### v1.4

First release. Feature equal to ZPause v1.4 for Black Ops II, except where the engine
doesn't allow it:

- **No HUD glow or panel.** `zp_hud_glow`, `zp_hud_panel`, `zp_hud_panel_alpha` and
  `zp_hud_panel_width` all need a shader behind the text, and Black Ops 4 has no scriptable
  HUD to put one in. `zp_blackout` does their job instead, which is why it is on by default
  at `0.2` on every port now — see **Not here yet**.
- **No chat commands.** Shield registers no chat function for a script, so everything is
  on the button combos. `zp_allow_short_words` is carried and does nothing.
- **`zp_only_script` and `zp_only_mod` do nothing here.** Shield reads one mod folder, so
  there is never a second copy to choose between. Both are carried so one config reads the
  same on every port.
- **The settings editor works the other way round.** What installs is a compiled artifact
  with no text in it to rewrite, so the installer writes your settings to
  `project-bo4\saved\server\zpause.json` and the script reads them when it loads. A dvar
  set in the console still wins — see [Configuration](#configuration).

Zombies are held by the engine, through the same call stock uses to freeze AI, so a paused
horde stands still rather than straining against the hold. The match clock, ground
powerups, insta-kill, double points and bleedout all hold for the length of a pause, and
time eases down into a pause and back out of it rather than cutting to a stop.

## Credits

Xep — [github.com/Xeptix](https://github.com/Xeptix)

Project BO4 / Shield for the client, and ate47's
[atian-cod-tools](https://github.com/ate47/atian-cod-tools) for the compiler.
