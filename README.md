# Skilled Trucker Ace

Top-down semi-trailer parking. Back a 53-foot rig into a bay that has no business fitting it.
Inspired by the drone footage of truck stops that circulates as "crazy trucker skills".

**Fail early:** any scrape ends the run.

Folding the cab into the trailer stops dead at 83 degrees rather than ending the run. The rig is
then jammed: nothing moves at all until you pull forward, which is the one direction that unwinds
the fold. Set `JACKKNIFE_ENDS_RUN = true` in `core.js` for the extra-hard version, where hitting
that limit is a fail.

## Play

Open `index.html`. No build step, no dependencies.

- **Drive** — `W`/`S` or `Up`/`Down`
- **Steer** — `A`/`D` or `Left`/`Right`
- **Restart** — `R`

The box at the top right reads how far the trailer is from the bay, in metres, and how many degrees
off square it is. Each number turns green when it alone is good enough to win. It replaced a single
"spot alignment" percentage that blended the two, where 60% could mean close and crooked or straight
and far — one number you could not act on.

## Speed

The unit that matters is truck lengths per second, not km/h. At this zoom the truck is 129px and
15.8 km/h is 27px/s: one truck length every 5 seconds, which reads as slow motion however fast the
number sounds.

Reverse is 24 km/h, up from 15.8. It is capped by the fold clock — how long full lock takes to jam —
which is 2.3s at that speed. Forward is 40 km/h, up from 20, and costs nothing at all: the fold
converges going forward, so forward speed trades against nothing. The drive to the bay halved, 7.5s
to 3.7s.

Braking is set by the lot, not by physics. There is 42cm between parked trucks — 2.6px — and any
scrape ends the run, so releasing the key has to stop the truck inside about that. `friction` is
36 m/s², or 3.7g, which no loaded semi can do, and it still takes 3.8px to stop. A realistic 0.7g
took 17px, six times the gap, and that is what read as sluggish: uncontrollable, not slow. Stopping
distance goes as v², so the self-check asserts the stop fits 1.6x the gap. That is the thing a
future speed change would silently ruin.

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
reverse, that 600 steps stay NaN-free, that the level parks no truck inside another, and that
releasing the key stops the truck inside 1.6x the gap between parked trucks.

Also that the trailer's axle never slips sideways — under 1px/s against the 77px/s of the jackknife
bug — that a jammed rig does not creep, and that pulling forward still unjams it.

`smoke.js` now captures the page's key handlers and presses the keys. They used to be dropped into
a noop, so a dead key looked exactly like a working one — which is how a mode shipped that did
nothing visible while driving forward.

## Physics

Tractor is a rear-axle bicycle model. The fifth wheel sits over the drive axle, so the hitch is
the tracked point and the trailer equation is exact:

    trailerAngle += (v / kingpinToAxle) * sin(cabAngle - trailerAngle)

Forward that converges — the trailer tracks. Reverse it diverges. That instability is the game.

Both axles roll: neither can move sideways. That is the constraint the model exists to satisfy, and
the self-check measures it directly, because the one place it was violated was invisible in every
other test. Clamping the fold angle at the 83° limit left the trailer rotating about the kingpin at
the cab's rate, which dragged the trailer's own axle sideways at 77px/s — twice the reverse speed,
straight through ground its wheels were standing on. The whole rig appeared to slide. The fix is to
refuse the step rather than to bend the angle: at the limit the rig is jammed, and jammed means
nothing moves.

One convention throughout: local `+x` is forward, and `angle` is the direction the nose points.

## Open decisions

**1. Trailer-direction steering: built, played, dropped.** `A`/`D` commanded the trailer and the
game solved the wheel angle. It worked — the fold settled on the commanded angle and could not
jackknife — and it was unintuitive in play. Three reasons, worth keeping so it is not rebuilt:

- **Pressing `D` moved the trailer's back end LEFT on screen.** Correct for a real driver, who
  faces backwards, so their right is the screen's left. Wrong for a player looking down at a
  screen. This is the one that killed it, and it is not fixable by flipping the sign: whichever
  way you map it, half the manoeuvre has the truck pointing the other way.
- The mode was invisible while driving forward, since both schemes steer the front wheels there.
- The nose wedge was tied to whether the assist was engaged, and the assist engaged at zero speed,
  so it blinked out on every stop and back on every pull-forward.

One finding survives, in case reverse speed is ever revisited: the fold clock limits *only* the
countersteering scheme. An assist that cannot fold has no speed cap from it.

Still on the table, both rejected for now as not worth the code: starting the truck 1.5 slots past
the bay instead of 5.5, and giving acceleration its own dial (at 1x speed it takes a quarter-length
nudge from 2.1s to 1.7s and does nothing to long moves). Three numbers in it were set
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
