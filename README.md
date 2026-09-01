# Skilled Trucker Ace

Top-down semi-trailer parking. Back a 53-foot rig into a bay that has no business fitting it.
Inspired by the drone footage of truck stops that circulates as "crazy trucker skills".

**Fail early:** any scrape ends the run.

Folding the cab into the trailer stops dead at 83 degrees rather than ending the run. Set
`JACKKNIFE_ENDS_RUN = true` in `core.js` for the extra-hard version, where hitting that
limit is a fail.

## Play

Open `index.html`. No build step, no dependencies.

- **Drive** — `W`/`S` or `Up`/`Down`
- **Steer** — `A`/`D` or `Left`/`Right`
- **Restart** — `R`

## Handling presets

Keys `1`-`5`, or the buttons under the canvas, switch between rig configurations so handling
can be compared directly. The world is specified in metres in `SPEC` and scaled to pixels by
the active preset, so switching rescales the rig *and* the lot together and you are comparing
handling rather than how much room you were given.

Each preset sets two independent knobs:

- `pxPerM` — zoom only.
- `wheelbase` — handling only. What matters is `wheelbase / kingpinToAxle`, and since both are
  in metres that ratio is scale-invariant.

That ratio decides whether a held wheel settles or runs away:

| | W/D | turn radius | in rig lengths | forward at full lock |
|---|---|---|---|---|
| 1 Current | 0.29 | 76px | 0.38 | jackknifes |
| 2 A sleeper wheelbase | 0.50 | 131px | 0.66 | settles at 64° |
| 3 B zoomed out | 0.50 | 85px | 0.66 | settles at 64° |
| 4 C docile | 0.70 | 119px | 0.92 | settles at 40° |
| 5 D very docile | 1.00 | 170px | 1.32 | settles at 27° |

A real WB-67 semi is 0.62 rig lengths. Turn radius on its own is the wrong thing to compare;
radius relative to rig length is what decides whether the lot has room.

## Reading the rig

Three cues, in different places and different shapes, so they never compete:

- **Wedge at the cab nose** — the steering angle. Straight edges always mean wheel angle.
  It resolves 1.69px per degree, against 0.088 for the front wheels and 1.33 for a HUD bar,
  because angular precision is linear in length and a wheel is 10px long.
- **Ghost trailer outlines** — where the box ends up if you hold this wheel and reverse. Three
  of them, fading, colour escalating cyan → orange → red as the fold nears the stop. Toggle
  with `P`. They come from stepping the real model rather than extrapolating an arc, since a
  reversing rig never reaches steady state. This started life as a line traced by the trailer's
  tail, which corkscrews once the fold accelerates: correct, and unreadable.
- **Front wheels** — diegetic, always on. Drawn 1.6x their true angle: full lock is 24°, which
  on a 13px wheel moves the tip under 3px. Real steer axles reach ~50°, so 1.6x stays possible.

## Layout

- `index.html` — rendering, input, game state
- `core.js` — the metre spec, presets, rig kinematics, collision, level. Shared by the page and both checks.
- `smoke.js` — runs the page's own script against a stub canvas.

## Check

    node core.js    # rig math, collision, level geometry
    node smoke.js   # the page itself, against a stub canvas

Asserts the separating-axis tests, that the trailer converges going forward and diverges in
reverse, that 600 steps stay NaN-free, and that the level parks no truck inside another.

## Physics

Tractor is a rear-axle bicycle model. The fifth wheel sits over the drive axle, so the hitch is
the tracked point and the trailer equation is exact:

    trailerAngle += (v / kingpinToAxle) * sin(cabAngle - trailerAngle)

Forward that converges — the trailer tracks. Reverse it diverges. That instability is the game.

One convention throughout: local `+x` is forward, and `angle` is the direction the nose points.

## Open decisions

**1. Trailer-direction steering in reverse.** The player's whole question is "if I reverse now,
which way does the trailer's back end go?" Four on-screen cues were tried and stacked into
noise. The alternative is to remove the question rather than answer it: in reverse, `A`/`D`
mean *send the trailer left / right* and the game solves for the wheel angle, the way Ford's
Pro Trailer Backup Assist knob works. We already have the formula, `δ = atan((W/D)·sin γ)`.

If built, it should land as a toggle against the classic scheme, and the HUD wheel bar and the
nose wedge probably come out with it. Classic counter-steering stays for a hard mode, next to
`JACKKNIFE_ENDS_RUN`.

**2. Whether the HUD wheel bar can go.** The nose wedge measures 1.69px per degree against the
bar's 1.33, so it should be redundant. Untested by a human.

**3. Is the lot solvable?** The geometry is verified — nothing overlaps, everything is on
screen, the bay is reachable in principle. Nobody has parked in it yet.

**4. Reference-photo work, not started.** Cracked asphalt with tyre scuffs (the biggest visual
gap to the drone footage), worn rather than crisp bay markings, and the rig is drawn ~1.6x too
wide for its length.

## Notes

- `~/Downloads/trucker-refs` holds 714MB of manufacturer body-builder manuals, kept only in
  case the rig geometry is revisited. Safe to delete otherwise. They were downloaded into a
  tmpfs `/tmp` and had to be moved out because they were eating RAM.
- There is a stale copy of the game published as a claude.ai artifact from before GitHub Pages
  worked. It should be retired; this repo is the only source of truth.
