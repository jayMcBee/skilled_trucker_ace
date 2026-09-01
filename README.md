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
- **Steering scheme** — `T`
- **Restart** — `R`

## Steering schemes

`T` flips between them, mid-run and mid-manoeuvre, because they are only comparable on the same
approach to the same bay.

**Classic.** `A`/`D` are the wheel. Reversing, the fold always grows and you countersteer against
a clock.

**Trailer-direction.** Reversing — and stopped, so you can aim before you move — `A`/`D` are the
*trailer*: `D` sends it clockwise, and the truck solves for the wheel angle. `A`/`D` still mean the
same on-screen direction they did in classic; the assist just skips the part where the cab goes the
other way first. Going forward the wheel is the wheel again, since the trailer merely follows.

The command is a fold angle, because a held fold *is* a trailer turn rate:
`d(trailerAngle)/d(travel) = sin(fold)/D`. Holding one needs the same equilibrium that decides
whether a held wheel settles going forward, `tan(steer) = (W/D)·sin(fold)`, plus a term that closes
the error. So the reverse instability is not simulated away — it is still there, being cancelled
frame by frame, and you can watch the steer axle do it.

The command stops short of the tightest holdable fold. At that fold full lock exactly *holds* and
nothing shrinks it: reverse cannot unwind it, only pulling forward can, which is a jackknife by a
politer name. `FOLD_HEADROOM` keeps the last 20% as unwind authority, and costs about a quarter of
the trailer's tightest turn:

| | fold the wheel can hold | assist commands up to | tightest trailer radius |
|---|---|---|---|
| 1 Standard | 64° | 46° | 106px, against a 129px rig |
| 2 Forgiving | 40° | 31° | 149px |
| 3 Very forgiving | 27° | 21° | 213px |

## Handling presets

Keys `1`-`3`, or the buttons under the canvas, switch between rig configurations so handling
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
| 1 Standard | 0.50 | 85px | 0.66 | settles at 64° |
| 2 Forgiving | 0.70 | 119px | 0.92 | settles at 40° |
| 3 Very forgiving | 1.00 | 170px | 1.32 | settles at 27° |

A real WB-67 semi is 0.62 rig lengths. Turn radius on its own is the wrong thing to compare;
radius relative to rig length is what decides whether the lot has room.

## Reading the rig

Cues in different places and different shapes, so they never compete:

- **Wedge at the cab nose** — the steering angle. Straight edges always mean wheel angle.
  It resolves 1.69px per degree, against 0.088 for the front wheels and 1.33 for a HUD bar,
  because angular precision is linear in length and a wheel is 10px long.
  Under trailer-direction steering the wedge is not drawn at all: it answers "where is the wheel",
  which stops being the player's question the moment the truck is working the wheel itself.
- **The HUD bar** — the wheel angle under classic steering, and the *trailer command* under
  trailer-direction steering, filling the way the trailer is being sent. It changes colour and
  label with the scheme, which is also how you see the assist take over as you shift into reverse.
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

For the assist, at every preset: a held direction *settles* the fold on the commanded angle
instead of running away, that angle is reachable in reverse from either side, the fold stop is
never reached, `D` swings the trailer the same way it does under classic steering, engaging
mid-fold adopts the fold it finds, and forward steering is left alone. `smoke.js` drives half of
each preset's run under the assist and flips schemes mid-reverse, since the handover is the part
worth driving through.

## Physics

Tractor is a rear-axle bicycle model. The fifth wheel sits over the drive axle, so the hitch is
the tracked point and the trailer equation is exact:

    trailerAngle += (v / kingpinToAxle) * sin(cabAngle - trailerAngle)

Forward that converges — the trailer tracks. Reverse it diverges. That instability is the game.

One convention throughout: local `+x` is forward, and `angle` is the direction the nose points.

## Open decisions

**1. Which scheme ships.** Trailer-direction steering is built, on `T`, against classic — see
*Steering schemes*. Both work; nobody has decided which is the game. Three numbers in it were set
by argument rather than by play, and are the things to change first if it feels wrong:

- `FOLD_GAIN = 2.5` — how hard the assist chases the commanded fold. The error closes over
  `D/GAIN` of travel, about 1.1s of reversing. Lower is soggier, higher snaps the wheel about.
- `FOLD_HEADROOM = 0.8` — how much unwind authority is held back. Raising it buys a tighter
  trailer turn and takes away the ability to change your mind in reverse.
- Command rate reuses `steerRate`, so winding the trailer command lock to lock takes ~2.7s
  against the wheel's 1.2s. It may want to be its own number.

The instability is intact underneath; the assist only cancels it. So classic stays as the hard
mode, next to `JACKKNIFE_ENDS_RUN`, unless it turns out nobody wants it.

**2. Whether the HUD wheel bar can go.** The nose wedge measures 1.69px per degree against the
bar's 1.33, so it should be redundant — but under trailer-direction steering the wedge is gone and
the bar is the only readout of the trailer command, so this can no longer be a straight deletion.
Untested by a human either way.

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
