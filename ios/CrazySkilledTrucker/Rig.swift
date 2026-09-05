//	==================================================
//	'Rig.swift'
//	--------------------------------------------------
//	Tractor and trailer kinematics, separating-axis collision, and the truck-stop
//	level. Contains no SpriteKit and no UIKit, so it is testable on its own.
//
//	Ported from 'core.js', which stays the reference implementation. Two conventions
//	come across unchanged, because changing either silently mirrors the whole game:
//	local +x is forward, 'heading' is the direction the nose points, and +y points
//	DOWN as it does on a canvas. SpriteKit's +y points up, so GameScene flips at the
//	boundary and nothing in this file knows about it.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import Foundation

typealias ConvexQuad = [Point]

// MARK: - Geometry

struct Point
{
	var x: Double
	var y: Double
}

struct Placement
{
	var position: Point
	var heading: Double
}

struct Rect
{
	var x: Double
	var y: Double
	var width: Double
	var height: Double
}

// MARK: - Specification, in metres

/// Every dimension of the world, in metres. Pixels appear only after a `Preset`
/// scales these, so the rig and the lot can never rescale independently.
enum TruckSpec
{
	static let trailerLength = 16.15			// 53 ft box
	static let trailerWidth = 4.38				// stylised ~1.7x wide, and consistent lot-wide
	static let cabLength = 4.58
	static let cabWidth = 3.96
	static let kingpinToAxle = 12.29			// the trailer's wheelbase, the D in every formula
	static let parkedRigLength = 20.83
	static let parkedRigWidth = 6.04

	// Two independent speeds, not a speed and a factor. The fold develops per METRE
	// travelled, so reverse speed buys nothing but reaction time, and forward speed
	// costs nothing at all because the fold converges going forward.
	static let forwardSpeed = 11.20				// m/s = 40.3 km/h
	static let reverseSpeed = 6.60				// m/s = 23.8 km/h, capped by the fold clock
	static let acceleration = 7.00

	// Braking is set by the LOT, not by physics: 42cm between parked trucks and any
	// scrape ends the run, so releasing the throttle has to stop inside about that.
	// 3.7g, which no loaded semi can do. A realistic 0.7g slid six gaps and read as
	// sluggish -- uncontrollable rather than slow.
	static let braking = 36.00

	static let maxSteerAngle = 0.42				// 24 degrees
	static let steerRate = 0.7					// 0.6 s centre to lock

	// ~83 degrees. A TUNED number, not derived from the boxes: the cab box and the
	// trailer box overlap at every fold angle including zero, because the kingpin sits
	// inside the cab box and the trailer's front edge is at the kingpin. Re-deriving
	// this from the geometry yields zero.
	static let maxArticulation = 1.45
}

/// The lot layout. `laneTurnRadii` is a multiple of the rig's own turning circle
/// rather than a typed-in width, so the lot stays solvable if the geometry changes.
enum LotSpec
{
	static let laneTurnRadii = 1.75
	static let rowPitch = 6.46					// 6.04m rigs: 42cm of daylight between neighbours
	static let slotCount = 9
	static let targetSlot = 4
	static let firstSlotY = 15.0
	static let laneCentreX = 40.0
}

enum Canvas
{
	static let width = 850.0
	static let height = 650.0
}

/// What the edge of the lot does. Open: the asphalt goes on and nothing stops the
/// truck. Kerb: the four edges collide and a scrape on them ends the run.
enum LotEdge: Int
{
	case open = 0
	case kerb = 1
}

// MARK: - Presets

/// `pixelsPerMetre` is zoom and nothing else. `wheelbase` is handling and nothing
/// else: what matters is wheelbase / kingpinToAxle, a ratio of two metre values, so
/// it is scale-invariant and the two knobs never interfere.
struct Preset: Equatable
{
	let name: String
	let pixelsPerMetre: Double
	let wheelbase: Double

	static let standard = Preset(name: "Standard", pixelsPerMetre: 6.19, wheelbase: 6.10)
	static let forgiving = Preset(name: "Forgiving", pixelsPerMetre: 6.19, wheelbase: 8.59)
	static let veryForgiving = Preset(name: "Very forgiving", pixelsPerMetre: 6.19, wheelbase: 12.29)

	static let all = [standard, forgiving, veryForgiving]
}

/// The two speed dials from the web build. Separate, because they trade against
/// completely different things: forward speed against nothing at all, reverse speed
/// against the fold clock. The reverse ceiling is deliberately tight: the base reverse
/// speed is already high, and 1.6x is the most that keeps the fold catchable.
struct Tuning: Equatable
{
	let forwardFactor: Double
	let reverseFactor: Double
	let jackknifeEndsRun: Bool

	static let lowestFactor = 0.3
	static let highestForwardFactor = 2.5
	static let highestReverseFactor = 1.6

	init(forwardFactor: Double = 1, reverseFactor: Double = 1, jackknifeEndsRun: Bool = false)
	{
		self.forwardFactor = clamped(forwardFactor, Tuning.lowestFactor, Tuning.highestForwardFactor)
		self.reverseFactor = clamped(reverseFactor, Tuning.lowestFactor, Tuning.highestReverseFactor)
		self.jackknifeEndsRun = jackknifeEndsRun
	}
}

/// Every world dimension in pixels, scaled from `TruckSpec` exactly once.
struct TruckDimensions
{
	let trailerLength: Double
	let trailerWidth: Double
	let cabLength: Double
	let cabWidth: Double
	let parkedRigLength: Double
	let parkedRigWidth: Double
}

// MARK: - Angles and helpers

/// Wraps to (-pi, pi]. Every angle difference in this file goes through here.
func normalizedAngle(_ radians: Double) -> Double
{
	return atan2(sin(radians), cos(radians))
}

func clamped(_ value: Double, _ lowest: Double, _ highest: Double) -> Double
{
	return min(highest, max(lowest, value))
}

/// Moves `value` toward `target` by at most `step`, landing exactly on it.
func movedToward(_ value: Double, _ target: Double, _ step: Double) -> Double
{
	if abs(target - value) <= step
	{
		return target
	}
	return value + (target > value ? step : -step)
}

// MARK: - Collision

struct Collision
{
	static func boxCorners(centre: Point, length: Double, width: Double, heading: Double) -> ConvexQuad
	{
		let cosine = cos(heading)
		let sine = sin(heading)
		let halfLength = length / 2.0
		let halfWidth = width / 2.0
		return [
			Point(x: centre.x - halfLength * cosine + halfWidth * sine,
				  y: centre.y - halfLength * sine - halfWidth * cosine),
			Point(x: centre.x + halfLength * cosine + halfWidth * sine,
				  y: centre.y + halfLength * sine - halfWidth * cosine),
			Point(x: centre.x + halfLength * cosine - halfWidth * sine,
				  y: centre.y + halfLength * sine + halfWidth * cosine),
			Point(x: centre.x - halfLength * cosine - halfWidth * sine,
				  y: centre.y - halfLength * sine + halfWidth * cosine)
		]
	}

	static func rectangleCorners(_ rectangle: Rect) -> ConvexQuad
	{
		return [
			Point(x: rectangle.x, y: rectangle.y),
			Point(x: rectangle.x + rectangle.width, y: rectangle.y),
			Point(x: rectangle.x + rectangle.width, y: rectangle.y + rectangle.height),
			Point(x: rectangle.x, y: rectangle.y + rectangle.height)
		]
	}

	/// True when `point` lies inside the convex quad, whichever way it winds.
	static func contains(_ quad: ConvexQuad, _ point: Point) -> Bool
	{
		var sawPositive = false
		var sawNegative = false
		for index in quad.indices
		{
			let start = quad[index]
			let end = quad[(index + 1) % quad.count]
			let cross = (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
			if cross > 0
			{
				sawPositive = true
			}
			if cross < 0
			{
				sawNegative = true
			}
		}
		return !(sawPositive && sawNegative)
	}

	/// Where two overlapping quads touch, for placing an effect: the mean of every corner
	/// of either quad that lies inside the other. Two edges crossing with no corner inside
	/// falls back to the midpoint between the two centres.
	static func contactPoint(_ first: ConvexQuad, _ second: ConvexQuad) -> Point
	{
		var sumX = 0.0
		var sumY = 0.0
		var count = 0
		for corner in first where contains(second, corner)
		{
			sumX += corner.x
			sumY += corner.y
			count += 1
		}
		for corner in second where contains(first, corner)
		{
			sumX += corner.x
			sumY += corner.y
			count += 1
		}
		if count > 0
		{
			return Point(x: sumX / Double(count), y: sumY / Double(count))
		}

		let all = first + second
		let centreX = all.reduce(0.0) { $0 + $1.x } / Double(all.count)
		let centreY = all.reduce(0.0) { $0 + $1.y } / Double(all.count)
		return Point(x: centreX, y: centreY)
	}

	/// Separating-axis test on two convex quads. Both polygons' edge normals are
	/// tested, which crossed slivers need and one polygon's normals alone would miss.
	static func intersects(_ first: ConvexQuad, _ second: ConvexQuad) -> Bool
	{
		for polygon in [first, second]
		{
			for index in polygon.indices
			{
				let start = polygon[index]
				let end = polygon[(index + 1) % polygon.count]
				let normalX = end.y - start.y
				let normalY = start.x - end.x

				var firstLowest = Double.infinity
				var firstHighest = -Double.infinity
				var secondLowest = Double.infinity
				var secondHighest = -Double.infinity

				for corner in first
				{
					let projection = normalX * corner.x + normalY * corner.y
					firstLowest = min(firstLowest, projection)
					firstHighest = max(firstHighest, projection)
				}
				for corner in second
				{
					let projection = normalX * corner.x + normalY * corner.y
					secondLowest = min(secondLowest, projection)
					secondHighest = max(secondHighest, projection)
				}

				if firstHighest < secondLowest || secondHighest < firstLowest
				{
					return false
				}
			}
		}
		return true
	}
}

// MARK: - The rig

/// Tractor as a rear-axle bicycle model, trailer hitched at the tracked point.
///
/// The fifth wheel on a semi sits over the drive axle, so the hitch IS the tracked
/// point and the trailer equation is exact:
///
///		d(trailerHeading) = (travel / kingpinToAxle) * sin(heading - trailerHeading)
///
/// Forward that converges and the trailer tracks. In reverse it diverges, and the
/// reverse equilibrium is UNSTABLE: there is no safe steering angle, only a countdown
/// you countersteer against. That instability is the game.
///
/// A value type deliberately. Refusing a step at the fold limit is then a matter of
/// putting back the three numbers that moved, with no aliasing to reason about.
struct Rig
{
	// MARK: - Properties

	private(set) var position: Point
	private(set) var heading: Double
	private(set) var trailerHeading: Double
	private(set) var speed = 0.0
	private(set) var steerAngle = 0.0

	let wheelbase: Double
	let kingpinToAxle: Double
	let dimensions: TruckDimensions

	private let maxForwardSpeed: Double
	private let maxReverseSpeed: Double
	private let acceleration: Double
	private let braking: Double
	private let maxSteerAngle: Double
	private let steerRate: Double

	/// The kingpin sits at the trailer's front edge, so the body centre trails half a
	/// length behind it. Derived rather than stored: there is no second copy to fall
	/// out of step with the heading.
	var trailerCentre: Point
	{
		return Point(x: position.x - cos(trailerHeading) * dimensions.trailerLength / 2.0,
					 y: position.y - sin(trailerHeading) * dimensions.trailerLength / 2.0)
	}

	var articulation: Double
	{
		return normalizedAngle(heading - trailerHeading)
	}

	/// Cab box and trailer box, the two shapes the player is drawn as and collided as.
	var collisionBoxes: [ConvexQuad]
	{
		return Rig.collisionBoxes(tracking: position, heading: heading,
								  trailerHeading: trailerHeading, dimensions: dimensions)
	}

	private enum Constants
	{
		/// Fraction of a cab length that the cab BOX sits ahead of the tracked point, so
		/// the drive axle ends up under the fifth wheel rather than at the cab's centre.
		static let cabBoxForwardOffset = 0.18
	}

	// MARK: - Init

	init(at start: Placement, world: World)
	{
		self.init(at: start, trailerHeading: start.heading, world: world)
	}

	/// Starts with the trailer already at an angle, which is how the fold behaviour is
	/// tested: a rig that begins perfectly straight in reverse stays straight forever,
	/// because zero fold is an equilibrium even though it is an unstable one. The wheel
	/// can start turned too, so the fold clock measures from full lock as core.js does.
	init(at start: Placement, trailerHeading: Double, steerAngle: Double = 0, world: World)
	{
		self.position = start.position
		self.heading = start.heading
		self.trailerHeading = trailerHeading
		self.steerAngle = clamped(steerAngle, -TruckSpec.maxSteerAngle, TruckSpec.maxSteerAngle)
		self.wheelbase = world.preset.wheelbase * world.scale
		self.kingpinToAxle = TruckSpec.kingpinToAxle * world.scale
		self.dimensions = world.dimensions
		self.maxForwardSpeed = world.maxForwardSpeed
		self.maxReverseSpeed = world.maxReverseSpeed
		self.acceleration = world.acceleration
		self.braking = world.braking
		self.maxSteerAngle = TruckSpec.maxSteerAngle
		self.steerRate = TruckSpec.steerRate
	}

	// MARK: - Public API

	var steerLimit: Double
	{
		return maxSteerAngle
	}

	/// Free of any `Rig` instance, because the level framing needs the start pose's real
	/// extent before there is a world for a rig to be built against.
	static func collisionBoxes(tracking position: Point, heading: Double,
							   trailerHeading: Double, dimensions: TruckDimensions) -> [ConvexQuad]
	{
		let noseOffset = dimensions.cabLength * Constants.cabBoxForwardOffset
		let cabCentre = Point(x: position.x + cos(heading) * noseOffset,
							  y: position.y + sin(heading) * noseOffset)
		let trailerCentre = Point(x: position.x - cos(trailerHeading) * dimensions.trailerLength / 2.0,
								  y: position.y - sin(trailerHeading) * dimensions.trailerLength / 2.0)
		return [
			Collision.boxCorners(centre: cabCentre, length: dimensions.cabLength,
								 width: dimensions.cabWidth, heading: heading),
			Collision.boxCorners(centre: trailerCentre, length: dimensions.trailerLength,
								 width: dimensions.trailerWidth, heading: trailerHeading)
		]
	}

	/// Advances by `seconds`. `drive` is a throttle in -1 ... +1: full deflection asks for
	/// the full forward or reverse speed, exactly as the web build's keys did, and a
	/// part deflection asks for that fraction of it, which is what a thumb pad can do
	/// and a key cannot. Easing off below the current speed brakes, as releasing does.
	/// `steerTarget` is the angle the wheel is being asked to reach, in radians; the
	/// wheel travels toward it at `steerRate` and holds wherever it is left, so nothing
	/// springs to centre.
	///
	/// Returns the RAW articulation, unclamped, so the caller can tell the rig jammed
	/// even though the stored state never leaves the limit.
	@discardableResult
	mutating func step(drive: Double, steerTarget: Double, seconds: Double) -> Double
	{
		precondition(seconds > 0, "Rig.step needs a timestep in seconds, got \(seconds)")

		// A target rather than a nudge. It lands exactly on the requested angle, which
		// is what a thumb on a slider asks for and what a key held down asks for, and
		// it makes core.js's snap-to-centre detent unnecessary.
		let target = clamped(steerTarget, -maxSteerAngle, maxSteerAngle)
		steerAngle = movedToward(steerAngle, target, steerRate * seconds)

		let positionBefore = position
		let headingBefore = heading
		let trailerHeadingBefore = trailerHeading

		let throttle = clamped(drive, -1, 1)
		let targetSpeed = throttle > 0 ? throttle * maxForwardSpeed : throttle * maxReverseSpeed
		let isEasingOff = speed * targetSpeed >= 0 && abs(speed) > abs(targetSpeed)
		speed = movedToward(speed, targetSpeed, (isEasingOff ? braking : acceleration) * seconds)

		let travel = speed * seconds
		heading = normalizedAngle(heading + (travel / wheelbase) * tan(steerAngle))
		position.x += cos(heading) * travel
		position.y += sin(heading) * travel
		trailerHeading = normalizedAngle(trailerHeading
			+ (travel / kingpinToAxle) * sin(heading - trailerHeading))

		// At the limit the rig is JAMMED, so the whole step is refused. Clamping only
		// the ANGLE is not enough: the trailer then rotates about the kingpin at the
		// cab's rate, which drags its own axle sideways at twice the reverse speed,
		// through the ground its wheels are standing on. The steer angle is deliberately
		// NOT put back, so the wheel can still be turned while jammed.
		let rawArticulation = normalizedAngle(heading - trailerHeading)
		if abs(rawArticulation) > TruckSpec.maxArticulation
		{
			position = positionBefore
			heading = headingBefore
			trailerHeading = trailerHeadingBefore
			speed = 0
		}
		return rawArticulation
	}
}

// MARK: - The level

struct Level
{
	let rowPitch: Double
	let firstSlotY: Double
	let leftRowX: Double
	let rightRowX: Double
	let start: Placement
}

struct Lot
{
	/// Where the trailer must end up, and the heading it must end up at.
	let bayTrailerCentre: Point
	let bayCentre: Point
	let bayHeading: Double
	let parked: [Placement]
	let walls: [Rect]
}

/// One preset, fully resolved: scale, pixel dimensions, level and lot. Replaces the
/// mutable globals core.js carries, so two worlds can exist at once and a test does
/// not have to put anything back.
struct World
{
	// MARK: - Properties

	let preset: Preset
	let tuning: Tuning
	let lotEdge: LotEdge
	let scale: Double
	let dimensions: TruckDimensions
	let level: Level
	let lot: Lot
	let obstacles: [ConvexQuad]

	/// Pixels per second. Acceleration and braking scale with the faster dial, as in
	/// the web build, so a faster truck still stops inside the gap between parked rigs.
	let maxForwardSpeed: Double
	let maxReverseSpeed: Double
	let acceleration: Double
	let braking: Double

	var forwardKilometresPerHour: Double
	{
		return TruckSpec.forwardSpeed * tuning.forwardFactor * Constants.metresPerSecondToKilometresPerHour
	}

	var reverseKilometresPerHour: Double
	{
		return TruckSpec.reverseSpeed * tuning.reverseFactor * Constants.metresPerSecondToKilometresPerHour
	}

	private enum Constants
	{
		static let wallThickness = 15.0
		/// The start sits this many row pitches beyond the last slot, at the far end of
		/// the lane, so the bay has to be passed and reversed into.
		static let startSlotsBeyondLot = 1.5
		static let metresPerSecondToKilometresPerHour = 3.6
		/// The fold clock starts from a rig that is very slightly bent: a perfectly
		/// straight rig in reverse stays straight forever, since zero fold is an
		/// equilibrium even though it is an unstable one.
		static let foldClockInitialBend = 0.02
		static let foldClockTimestep = 1.0 / 60.0
		static let foldClockGiveUpAfterSeconds = 120.0
	}

	// MARK: - Init

	init(preset: Preset, tuning: Tuning = Tuning(), lotEdge: LotEdge = .open)
	{
		self.preset = preset
		self.tuning = tuning
		self.lotEdge = lotEdge
		let scale = preset.pixelsPerMetre
		self.scale = scale

		let fasterDial = max(tuning.forwardFactor, tuning.reverseFactor)
		self.maxForwardSpeed = TruckSpec.forwardSpeed * scale * tuning.forwardFactor
		self.maxReverseSpeed = TruckSpec.reverseSpeed * scale * tuning.reverseFactor
		self.acceleration = TruckSpec.acceleration * scale * fasterDial
		self.braking = TruckSpec.braking * scale * fasterDial

		let dimensions = TruckDimensions(
			trailerLength: TruckSpec.trailerLength * scale,
			trailerWidth: TruckSpec.trailerWidth * scale,
			cabLength: TruckSpec.cabLength * scale,
			cabWidth: TruckSpec.cabWidth * scale,
			parkedRigLength: TruckSpec.parkedRigLength * scale,
			parkedRigWidth: TruckSpec.parkedRigWidth * scale)
		self.dimensions = dimensions

		// Lane width is a multiple of the TURNING CIRCLE, so the lot stays solvable if
		// the rig geometry is ever revisited.
		let turnRadius = preset.wheelbase / tan(TruckSpec.maxSteerAngle)
		let laneWidth = LotSpec.laneTurnRadii * turnRadius

		let rowPitch = LotSpec.rowPitch * scale
		let leftRowX = (LotSpec.laneCentreX - laneWidth / 2.0 - TruckSpec.parkedRigLength / 2.0) * scale
		let rightRowX = (LotSpec.laneCentreX + laneWidth / 2.0 + TruckSpec.parkedRigLength / 2.0) * scale
		let firstSlotY = LotSpec.firstSlotY * scale
		let startY = (LotSpec.firstSlotY
			+ (Double(LotSpec.slotCount) + Constants.startSlotsBeyondLot) * LotSpec.rowPitch) * scale
		let startPlacement = Placement(position: Point(x: LotSpec.laneCentreX * scale, y: startY),
									   heading: -Double.pi / 2.0)

		let uncentred = Level(rowPitch: rowPitch, firstSlotY: firstSlotY,
							  leftRowX: leftRowX, rightRowX: rightRowX, start: startPlacement)
		self.level = World.centred(uncentred, dimensions: dimensions)
		self.lot = World.buildLot(level: self.level, dimensions: dimensions)
		self.obstacles = World.obstacles(for: self.lot, dimensions: dimensions, lotEdge: lotEdge)
	}

	// MARK: - Public API

	/// Seconds of full-lock reversing before the fold reaches the stop, or nil if it
	/// never does. This is what reverse speed buys, and the only thing it buys, so the
	/// options sheet shows it next to the reverse dial.
	func secondsOfFullLockReverseBeforeJam() -> Double?
	{
		var rig = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0),
					  trailerHeading: Constants.foldClockInitialBend,
					  steerAngle: TruckSpec.maxSteerAngle, world: self)
		let timestep = Constants.foldClockTimestep
		let steps = Int(Constants.foldClockGiveUpAfterSeconds / timestep)
		for step in 0 ..< steps
		{
			let articulation = rig.step(drive: -1, steerTarget: rig.steerLimit, seconds: timestep)
			if abs(articulation) > TruckSpec.maxArticulation
			{
				return Double(step) * timestep
			}
		}
		return nil
	}

	/// Side 0 is the left row facing east, side 1 the right row facing west. Noses point
	/// into the lane, so you back in and the cab ends up nearest the traffic.
	static func slotCentre(_ index: Int, side: Int, level: Level) -> Placement
	{
		return Placement(position: Point(x: side == 0 ? level.leftRowX : level.rightRowX,
										 y: level.firstSlotY + level.rowPitch * Double(index)),
						 heading: side == 0 ? 0 : Double.pi)
	}

	/// A parked rig collides as the two boxes it is DRAWN as. It used to collide as one
	/// box parkedRigLength x parkedRigWidth, and parkedRigWidth is 1.66m wider than the
	/// widest thing drawn, so every parked truck carried an invisible 0.83m kill zone
	/// down each side. GameScene draws from this same arithmetic.
	static func parkedBoxes(_ placement: Placement, dimensions: TruckDimensions) -> [ConvexQuad]
	{
		let forwardX = cos(placement.heading)
		let forwardY = sin(placement.heading)
		let trailerOffset = dimensions.parkedRigLength / 2.0 - dimensions.trailerLength / 2.0
		let cabOffset = dimensions.parkedRigLength / 2.0 - dimensions.cabLength / 2.0
		let trailerCentre = Point(x: placement.position.x - forwardX * trailerOffset,
								  y: placement.position.y - forwardY * trailerOffset)
		let cabCentre = Point(x: placement.position.x + forwardX * cabOffset,
							  y: placement.position.y + forwardY * cabOffset)
		return [
			Collision.boxCorners(centre: trailerCentre, length: dimensions.trailerLength,
								 width: dimensions.trailerWidth, heading: placement.heading),
			Collision.boxCorners(centre: cabCentre, length: dimensions.cabLength,
								 width: dimensions.cabWidth, heading: placement.heading)
		]
	}

	// MARK: - Private

	/// Zooming out leaves the lot hugging one corner, so every preset is shifted to sit
	/// the same way in the frame. The start pose is bounded by the rig's REAL extent --
	/// it reaches a full trailer length behind the tracked point, not half a parked-rig
	/// length, which is what core.js assumed and got wrong by 35px.
	private static func centred(_ level: Level, dimensions: TruckDimensions) -> Level
	{
		var lowestX = Double.infinity
		var highestX = -Double.infinity
		var lowestY = Double.infinity
		var highestY = -Double.infinity

		var quads: [ConvexQuad] = []
		for index in 0 ..< LotSpec.slotCount
		{
			for side in 0 ... 1
			{
				let slot = World.slotCentre(index, side: side, level: level)
				quads.append(Collision.boxCorners(centre: slot.position,
												  length: dimensions.parkedRigLength,
												  width: dimensions.parkedRigWidth,
												  heading: slot.heading))
			}
		}

		quads.append(contentsOf: Rig.collisionBoxes(tracking: level.start.position,
												   heading: level.start.heading,
												   trailerHeading: level.start.heading,
												   dimensions: dimensions))

		for quad in quads
		{
			for corner in quad
			{
				lowestX = min(lowestX, corner.x)
				highestX = max(highestX, corner.x)
				lowestY = min(lowestY, corner.y)
				highestY = max(highestY, corner.y)
			}
		}

		let shiftX = (Canvas.width - (highestX - lowestX)) / 2.0 - lowestX
		let shiftY = (Canvas.height - (highestY - lowestY)) / 2.0 - lowestY
		return Level(rowPitch: level.rowPitch,
					 firstSlotY: level.firstSlotY + shiftY,
					 leftRowX: level.leftRowX + shiftX,
					 rightRowX: level.rightRowX + shiftX,
					 start: Placement(position: Point(x: level.start.position.x + shiftX,
													  y: level.start.position.y + shiftY),
									  heading: level.start.heading))
	}

	private static func buildLot(level: Level, dimensions: TruckDimensions) -> Lot
	{
		var parked: [Placement] = []
		var bay = Placement(position: Point(x: 0, y: 0), heading: 0)

		for side in 0 ... 1
		{
			for index in 0 ..< LotSpec.slotCount
			{
				let slot = World.slotCentre(index, side: side, level: level)
				if side == 0 && index == LotSpec.targetSlot
				{
					bay = slot
				}
				else
				{
					parked.append(slot)
				}
			}
		}

		let trailerOffset = dimensions.parkedRigLength / 2.0 - dimensions.trailerLength / 2.0
		let bayTrailerCentre = Point(x: bay.position.x - cos(bay.heading) * trailerOffset,
									 y: bay.position.y - sin(bay.heading) * trailerOffset)

		let thickness = Constants.wallThickness
		let walls = [
			Rect(x: 0, y: 0, width: Canvas.width, height: thickness),
			Rect(x: 0, y: Canvas.height - thickness, width: Canvas.width, height: thickness),
			Rect(x: 0, y: 0, width: thickness, height: Canvas.height),
			Rect(x: Canvas.width - thickness, y: 0, width: thickness, height: Canvas.height)
		]

		return Lot(bayTrailerCentre: bayTrailerCentre, bayCentre: bay.position,
				   bayHeading: bay.heading, parked: parked, walls: walls)
	}

	/// Parked boxes first, then the walls if the edge is a kerb. The self-check relies
	/// on that order.
	private static func obstacles(for lot: Lot, dimensions: TruckDimensions, lotEdge: LotEdge) -> [ConvexQuad]
	{
		var quads: [ConvexQuad] = []
		for placement in lot.parked
		{
			quads.append(contentsOf: World.parkedBoxes(placement, dimensions: dimensions))
		}
		if lotEdge == .kerb
		{
			for wall in lot.walls
			{
				quads.append(Collision.rectangleCorners(wall))
			}
		}
		return quads
	}
}
