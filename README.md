# Supernatural Ability Wheel

A Roblox prototype for a supernatural game: two ability wheels (Q and R), a spells editor, and server-validated abilities. Written in Luau, synced with Rojo.

## Features

- **Two wheels, one catalog.** Hold **Q** for the Q wheel, hold **R** for the R wheel. Release the key to select the highlighted slot and close. Switch wheels by pressing the other key or clicking the center badge.
- **Spells editor.** Click **SPELLS** (or hold R, then click the center) to open the editor. Abilities are shown in a grid, grouped by category with their own colors. Click an ability to equip it into the first empty slot, or click an equipped ability to remove it. Click a slot first to choose where the next ability goes.
- **One ability, one wheel.** An ability can sit in one slot across both wheels. The server refuses duplicates.
- **Server-authoritative loadouts.** The client sends requests; the server decides and saves.
- **Abilities:**
  - *Vampiric Speed* (Vampire): a short dash, with afterimages and a server-driven cooldown.
  - *Telekinetic Choke* (Witch): lifts and holds a target in front of you, then deals damage over time.
- **Training dummies** with health bars, to test abilities without a second player.

Controls: hold **Q** or **R**, left-click the world or the **USE** button to cast the selected ability, **Esc** or **CLOSE** to leave the wheel without selecting.

## Project structure

```
default.project.json          Rojo mapping (ReplicatedStorage/Shared, ServerScriptService/Server, StarterPlayerScripts/Client)
src/
  shared/
    Config.lua                All ability data: names, categories, cooldowns, durations, animations, gameplay settings
    Remotes.lua               Creates the RemoteEvents on the server and waits for them on the client
  server/
    Main.server.lua           Entry point
    AbilityService.lua        Validates every ability request: loadout, cooldown, state, then runs the ability module
    LoadoutService.lua        Loadouts per player, the one-ability-one-wheel rule, DataStore saving
    TrainingDummies.lua       Test targets with health bars
    Abilities/
      VampiricSpeed.lua       Dash: server-owned LinearVelocity, visuals sent to clients
      TelekineticChoke.lua    Target checks (range, facing, line of sight), lift, damage ticks, cleanup
  client/
    Main.client.lua           Input (Q, R, click, Esc), wheel/HUD wiring, server responses
    RadialWheel.lua           The wheel: slot layout, hover, selection, cooldowns, edit mode
    SpellBook.lua             The Spells panel
    AbilityHud.lua            Bottom HUD: selected ability, cooldown, USE and SPELLS buttons
    AbilityAnimations.lua     Plays ability animations locally
    AbilityVisuals.lua        Cosmetic effects (afterimages, particles) on each client
    Loadout.lua               Client mirror of the server loadouts
    Icons.lua                 Icons drawn with UI frames (no image assets)
    Theme.lua                 Colors and tween presets
```

## How the pieces talk

- `AbilityRequest` (client → server): `(abilityId, target?, direction?)`. The server checks the loadout, cooldown, character state and target before running anything. The reply is `AbilityResponse`.
- `AbilityVisual` (server → all clients): tells clients which ability started on which character, so they create effects locally.
- `LoadoutRequest` (client → server): `("toggle" | "equip" | "unequip" | "sync", wheel, value, slot?)`. The reply is `LoadoutState`, with both wheels and an optional reason such as `full` or `in_other_wheel`.

## Adding an ability

1. Add an entry to `Config.Abilities` in `src/shared/Config.lua`: `DisplayName`, `Description`, `ShortName`, `Category`, `Icon`, `Cooldown`, `EffectDuration`, `Animation`, and a settings table for the server.
2. Create `src/server/Abilities/YourAbility.lua` with two functions:
   - `Validate(ctx, request)` returns `ok, reason, data`.
   - `Run(ctx, data, finish)` starts the effect and returns a cancel function.
3. Register the module in the `Abilities` table in `src/server/AbilityService.lua`.
4. If it needs client visuals, add a handler in `src/client/AbilityVisuals.lua`. Add its message text to `REASON_TEXT` in `Main.client.lua` if it has new refusal reasons.

Categories are defined in `Config.Categories`. Add a category there and use its key in `Category`.

## Setup

1. Install [Rojo](https://rojo.space) 7.x and the Rojo plugin in Roblox Studio.
2. In this folder run `rojo serve default.project.json` (add `--port 34873` if another Rojo server uses the default port).
3. In Studio, open a baseplate and click **Connect** in the Rojo panel.

To produce a place file without Studio: `rojo build default.project.json -o SupernaturalAbilityWheel.rbxlx`.

**Saving loadouts.** Loadouts are stored with `DataStoreService`, under the store `SupernaturalLoadouts`. Each change is saved right away. To test saving in Studio:

1. Publish the place once (**File → Publish to Roblox**).
2. Turn on **Studio access to API services**: in Studio, open the experience settings, go to **Security** (*Segurança*), and enable *Permitir acesso do Studio aos serviços API*.
3. Press Play, change a loadout, stop, and press Play again. The change should still be there.

Without step 2, Studio logs `StudioAccessToApisNotAllowed` and the loadout lasts only for the session. Nothing already stored is overwritten in that case.

## Testing

Tested in Roblox Studio (evidence from the Studio console and tool output):

- Build: `rojo build` succeeds.
- Vampiric Speed: the server accepts the cast and the HUD shows the cooldown. The dash moves the character, and afterimages appear on the client.
- Telekinetic Choke: target validation returns the expected result for in-range, out-of-range, behind, self, and bad-type cases. The full effect runs: the target is held and lifted, takes 12 damage, and all changes are restored once.
- Locomotion: the default Animate script switches to run and idle as expected.
- DataStore: without Studio API access, Studio refuses the request as expected, and the loadout works for the session only.

Not yet tested:

- Multiplayer: visibility of effects to other players, and two players using the same wheels.
- The full wheel and Spells flows end to end (equip, remove, full wheel, duplicate, switching wheels with Q and R). These were inspected in screenshots and code, but not run as a test plan.
- Mobile controls.
- Saving and reloading a loadout from a published place.

## Known limitations

- Only two wheels (Q and R) have key bindings. Adding E or T means adding bindings in `Config.Input` and extending `Config.Loadout.Wheels`.
- The dash uses the client's physics ownership for movement, so a determined exploiter can change their own movement.
- Loadouts are per player, not per character. Character selection and species are not implemented.
- Some UI text is still in Portuguese; ability names and descriptions are in English.
