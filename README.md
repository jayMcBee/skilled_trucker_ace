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

## Layout

- `index.html` — rendering, input, game state
- `core.js` — rig kinematics, collision, level data. Shared by the page and the self-check.

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
