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
