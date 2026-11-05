# Starglider Remake (Godot 4)

EVERYTHING (EXCEPT THIS LINE) INCLUDING THIS README WAS CREATED BY CLAUDE CODE!! JUST A FUN TIME PASSER GAME. IS IT POLISHED? YES AND IT PLAYS SMOOTH. IS IT MORE THAN 1 STAGE? NO. I MAY ADD MORE THINGS AS I GO.

A wireframe tribute to Argonaut's 1986 *Starglider*. Fly over Novenia, shoot Egron walkers,
tanks and flyers, raid their bases, then take down Starglider One.

## Run it

1. Install **Godot 4.3 or newer** (standard, not .NET) from https://godotengine.org/download/linux
   (not the `godot3` package from the Ubuntu repos).
2. Start Godot, click **Import**, pick `project.godot`, then press **F5**.

## Controls (all rebindable: press Esc)

| Key | Action |
| --- | --- |
| Arrow keys / WASD | Climb, dive, turn (also steer inside bases) |
| Q / E | Slow down / speed up (works inside bases too) |
| Space | Fire lasers |
| M or Ctrl | Fire missile (homes on the bracketed target) |
| Esc | Options menu |
| F11 or Alt+Enter | Toggle fullscreen |
| R | Restart after game over / win |

**Mouse flight** (turn it on in the options menu): move the mouse to steer,
left button fires lasers, right button fires a missile, wheel changes speed.
Invert-pitch and sensitivity are in the menu too.

Settings and key bindings are saved to `user://starglider.cfg`.

## Gameplay

- **Enemies:** walkers (3 hits), tanks (2 hits), flyers (1 hit). 14 kills summons **Starglider One** (30 hits).
- **Pylons** are shootable (25 points); flying into one hurts. Destroyed pylons are replaced elsewhere.
- **Missiles:** start with 6 (max 9). A `[ ]` bracket shows the current lock when an enemy is near your crosshair.
  Blasts damage everything nearby, including pylons.
- **Radar** (bottom right) is heading-up, range 1200 m: red square = walker, orange dot = tank,
  magenta diamond = flyer, yellow = boss, blue triangle = base.
- **Bases:** fly into the glowing gate of a blue base (the HUD says where the nearest one is).
  Inside you speed down a tunnel, fly through the yellow gaps in the red barriers, and shoot the
  reactor core at the end. Success restores shields, gives +4 missiles and bonus points, and destroys the base.
  Barriers are solid to your lasers too (shots only pass through the gaps) and laser range is short in there.
  Hitting a barrier costs 20 shields; missing the core costs 30 and ejects you.
- Don't scrape the ground (altitude under 3) and dodge the orange bolts.

## Files

- `main.gd`: the game (everything is drawn as line meshes, so no Blender assets needed)
- `synth.gd`: retro sound effects via `AudioStreamGenerator`
- `radar.gd`: the radar widget

If you later want custom models, export glTF from Blender and load them in place of the `*_segs()` functions.
