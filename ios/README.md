# iPad port — SpriteKit, UIKit

Swift port of the web game. The web build in the repo root stays the reference: it is the
one that has been played and measured.

**None of this Swift has been compiled.** It was written on Linux, where there is no Swift
toolchain and no SpriteKit. Expect to fix build errors on the first run.

## Files

| file | what it is |
|---|---|
| `Rig.swift` | Physics, collision, level. No SpriteKit, no UIKit. Port of `core.js`. |
| `GameScene.swift` | The scene: draws the lot, steps the rig, reads two thumb pads. |
| `ViewController.swift` | Replaces the template's empty one. Presents the scene in an `SKView`. |
| `RigTests.swift` | Port of the self-check in `core.js`. Needs a test target. |

## Putting it together

1. Copy `Rig.swift`, `GameScene.swift` and `ViewController.swift` into
   `CrazySkilledTrucker/CrazySkilledTrucker/`, replacing the template's `ViewController.swift`.
2. Add the two new files to the app target in Xcode.
3. For the tests: File → New → Target → Unit Testing Bundle, then add `RigTests.swift` to it.
   The template has no test target.
4. Run. The storyboard needs no changes — `loadView()` swaps its plain view for an `SKView`.

Landscape is forced in `ViewController`. The scene is 850 x 650 and uses `.aspectFit`, so every
iPad sees the same lot letterboxed, rather than more or less of it.

## Two traps

**The y-axis is flipped.** `Rig.swift` works in canvas coordinates, where +y points DOWN.
SpriteKit's +y points UP. Every conversion goes through `scenePosition(_:)` and
`sceneRotation(_:)` in `GameScene`, and nowhere else. Bypassing them mirrors the whole game.
It looks plausible and plays backwards.

**A drawn shape must be the shape it collides as.** `GameScene` builds its paths straight from
the collision corners, so the two cannot drift apart. The web build did not do this, and every
parked truck carried an invisible 0.83m kill zone down each side for months: a run could end
with 5px of daylight still on screen. No screenshot and no playtest can catch that class of bug,
which is why `RigTests` measures the drawn sizes rather than trusting them.

## What changed from the web build, on purpose

- **Steering takes a target angle, not a nudge.** A thumb's position across the pad IS the wheel
  angle, which is the one thing a touch screen does better than a key. The rig's own steer rate
  still limits how fast the wheel gets there, so the feel is unchanged. This also made the web
  build's snap-to-centre detent unnecessary — moving toward a target lands exactly on it.
- **The speed dials are gone.** They were tuning tools, and a review found they could be pushed
  past the game's own safety limits: enough presses put the stopping distance beyond the gap
  between parked trucks, and shortened the fold clock below what is catchable.
- **Preset switching is not exposed.** All three presets still exist in `Preset.all` and the
  tests run against every one of them.
- **`centred(_:)` bounds the start pose by the rig's real extent.** The web version measured it
  as a parked-rig box about the tracked point, which is wrong by 35px — the rig reaches a full
  trailer length behind that point. The web build clears the bottom wall partly by luck.

## Numbers worth not re-deriving

- Reverse is 24 km/h, capped by the fold clock: 2.3s of full lock before it jams.
- Forward is 40 km/h and costs nothing. The fold converges going forward.
- Braking is 3.7g, set by the lot and not by physics. There is 42cm between parked trucks and
  any scrape ends the run, so releasing the throttle has to stop inside about that. A realistic
  0.7g slid six gaps and read as sluggish — uncontrollable rather than slow.
- The fold stop at 83° is a tuned number. It is NOT derivable from the boxes: the cab box and
  the trailer box overlap at every fold angle including zero.
- At the fold stop the rig is genuinely jammed. No steer angle permits reverse motion, for any
  preset, so `step` refuses the whole timestep. Clamping only the angle made the trailer rotate
  about the kingpin and drag its axle sideways at twice the reverse speed.
- The reverse point of no return is `asin((D/L) * tan(maxSteer))` = 64° / 40° / 27° for the three
  presets. Past it, reverse cannot recover — only pulling forward can.
