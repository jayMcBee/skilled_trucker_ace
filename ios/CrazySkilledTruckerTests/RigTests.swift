//	==================================================
//	'RigTests.swift'
//	--------------------------------------------------
//	Port of the self-check in 'core.js'. Every assertion runs against every preset,
//	because a preset that breaks the geometry is a bug.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import XCTest
@testable import CrazySkilledTrucker

final class RigTests: XCTestCase
{
	private enum Constants
	{
		static let timestep = 1.0 / 60.0
		static let coarseTimestep = 1.0 / 30.0
		static let fineTimestep = 1.0 / 240.0
	}

	// MARK: - Collision

	func testContactPointLiesInsideTheOverlap()
	{
		let box = Collision.boxCorners(centre: Point(x: 0, y: 0), length: 100, width: 40, heading: 0)
		let other = Collision.boxCorners(centre: Point(x: 90, y: 10), length: 100, width: 40, heading: 0)
		let contact = Collision.contactPoint(box, other)
		XCTAssertTrue(Collision.contains(box, contact), "the contact point must lie in the first box")
		XCTAssertTrue(Collision.contains(other, contact), "the contact point must lie in the second box")

		let crossing = Collision.boxCorners(centre: Point(x: 0, y: 0), length: 200, width: 10, heading: .pi / 2)
		let cross = Collision.contactPoint(box, crossing)
		XCTAssertEqual(cross.x, 0, accuracy: 1e-9, "edge-on crossings fall back to the shared centre")
		XCTAssertEqual(cross.y, 0, accuracy: 1e-9, "edge-on crossings fall back to the shared centre")
	}

	func testSeparatingAxisTest()
	{
		let box = Collision.boxCorners(centre: Point(x: 0, y: 0), length: 100, width: 40, heading: 0)
		XCTAssertTrue(Collision.intersects(box, Collision.boxCorners(
			centre: Point(x: 50, y: 0), length: 100, width: 40, heading: 0)),
			"overlapping boxes must collide")
		XCTAssertFalse(Collision.intersects(box, Collision.boxCorners(
			centre: Point(x: 200, y: 0), length: 100, width: 40, heading: 0)),
			"separated boxes must not collide")
		XCTAssertFalse(Collision.intersects(box, Collision.boxCorners(
			centre: Point(x: 0, y: 75), length: 100, width: 40, heading: .pi / 2)),
			"rotated near-miss must not collide")
		XCTAssertTrue(Collision.intersects(box, Collision.boxCorners(
			centre: Point(x: 0, y: 30), length: 100, width: 40, heading: .pi / 2)),
			"rotated overlap must collide")
	}

	func testBoxLengthRunsAlongTheHeading()
	{
		let corners = Collision.boxCorners(centre: Point(x: 0, y: 0), length: 200, width: 40, heading: 0)
		XCTAssertEqual(corners.map { $0.x }.max() ?? 0, 100, accuracy: 1e-9, "length must lie along +x")
	}

	// MARK: - Kinematics

	func testForwardConvergesAndReverseDiverges()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset)

			var forward = Rig(at: Placement(position: Point(x: 400, y: 300), heading: 0),
							  trailerHeading: -0.3, world: world)
			for _ in 0 ..< Int(20 / Constants.timestep)
			{
				forward.step(drive: 1, steerTarget: 0, seconds: Constants.timestep)
			}
			XCTAssertLessThan(abs(forward.articulation), 0.05,
				"forward must converge [\(preset.name)]")

			var reverse = Rig(at: Placement(position: Point(x: 400, y: 300), heading: 0),
							  trailerHeading: -0.05, world: world)
			let startFold = abs(reverse.articulation)
			for _ in 0 ..< Int(25 / Constants.timestep)
			{
				reverse.step(drive: -1, steerTarget: 0, seconds: Constants.timestep)
			}
			XCTAssertGreaterThan(abs(reverse.articulation), startFold * 3,
				"reverse must diverge [\(preset.name)]")
		}
	}

	func testFullLockReverseStaysCatchable()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset)
			var rig = Rig(at: Placement(position: Point(x: 400, y: 300), heading: 0), world: world)
			var secondsToJam: Double? = nil

			for frame in 0 ..< Int(60 / Constants.timestep)
			{
				let articulation = rig.step(drive: -1, steerTarget: rig.steerLimit,
											seconds: Constants.timestep)
				if secondsToJam == nil && abs(articulation) > TruckSpec.maxArticulation
				{
					secondsToJam = Double(frame) * Constants.timestep
				}
			}

			// 2.2s. This catches the 1.1s original that made the game unplayable, and the
			// bar is low because braking is now 3.7g: a second of reaction buys far more
			// than it did when the truck slid six inter-truck gaps after you let go.
			XCTAssertGreaterThan(secondsToJam ?? .infinity, 2.2,
				"full-lock reverse must take over 2.2s to jam [\(preset.name)]")
		}
	}

	func testSteeringHoldsItsAngleAndLandsExactlyOnTarget()
	{
		let world = World(preset: .standard)
		var rig = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0), world: world)

		for _ in 0 ..< Int(1 / Constants.timestep)
		{
			rig.step(drive: 0, steerTarget: rig.steerLimit, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.steerAngle, rig.steerLimit, accuracy: 1e-12,
			"the wheel must reach full lock and stop exactly there")
		XCTAssertEqual(rig.heading, 0, accuracy: 1e-12, "a stopped rig must not rotate")

		let held = rig.steerAngle
		for _ in 0 ..< Int(1 / Constants.timestep)
		{
			rig.step(drive: 0, steerTarget: held, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.steerAngle, held, accuracy: 1e-12,
			"the wheel must hold its angle when nothing asks it to move")

		for _ in 0 ..< Int(2 / Constants.timestep)
		{
			rig.step(drive: 0, steerTarget: 0, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.steerAngle, 0, accuracy: 1e-12,
			"steering back must land on exact centre, with no detent needed")
	}

	func testFrameRateIndependence()
	{
		let world = World(preset: .standard)
		var slow = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0), world: world)
		var fast = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0), world: world)

		for _ in 0 ..< 60
		{
			slow.step(drive: 1, steerTarget: slow.steerLimit, seconds: 1.0 / 60.0)
		}
		for _ in 0 ..< 144
		{
			fast.step(drive: 1, steerTarget: fast.steerLimit, seconds: 1.0 / 144.0)
		}
		XCTAssertLessThan(hypot(slow.position.x - fast.position.x, slow.position.y - fast.position.y),
			2, "60Hz and 144Hz must agree")
	}

	// MARK: - The throttle and the dials

	/// Full deflection is the web build's key. The pad adds nothing and takes nothing.
	func testFullThrottleReachesTheWebBuildSpeeds()
	{
		let world = World(preset: .standard)
		var rig = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0), world: world)
		for _ in 0 ..< Int(3 / Constants.timestep)
		{
			rig.step(drive: 1, steerTarget: 0, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.speed, TruckSpec.forwardSpeed * world.scale, accuracy: 1e-9,
			"full forward must be the web build's forward speed")

		for _ in 0 ..< Int(3 / Constants.timestep)
		{
			rig.step(drive: -1, steerTarget: 0, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.speed, -TruckSpec.reverseSpeed * world.scale, accuracy: 1e-9,
			"full reverse must be the web build's reverse speed")
	}

	func testPartThrottleHoldsPartSpeedAndEasingOffBrakes()
	{
		let world = World(preset: .standard)
		var rig = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0), world: world)
		for _ in 0 ..< Int(3 / Constants.timestep)
		{
			rig.step(drive: 0.5, steerTarget: 0, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.speed, world.maxForwardSpeed * 0.5, accuracy: 1e-9,
			"half throttle must settle at half speed")

		for _ in 0 ..< Int(3 / Constants.timestep)
		{
			rig.step(drive: 1, steerTarget: 0, seconds: Constants.timestep)
		}
		let framesToEaseOff = 0.5 / Constants.timestep
		for _ in 0 ..< Int(framesToEaseOff)
		{
			rig.step(drive: 0.25, steerTarget: 0, seconds: Constants.timestep)
		}
		XCTAssertEqual(rig.speed, world.maxForwardSpeed * 0.25, accuracy: 1e-9,
			"easing off must brake down to the new target inside half a second")
	}

	/// Mirrors the web build's own check: releasing the throttle must stop the truck
	/// inside roughly the gap between parked trucks, at every dial setting.
	func testReleasingTheThrottleStopsInsideTheGap()
	{
		let dials = [Tuning(), Tuning(forwardFactor: Tuning.highestForwardFactor, reverseFactor: Tuning.highestReverseFactor)]
		for preset in Preset.all
		{
			for tuning in dials
			{
				let world = World(preset: preset, tuning: tuning)
				var rig = Rig(at: Placement(position: Point(x: 0, y: 0), heading: 0), world: world)
				for _ in 0 ..< Int(3 / Constants.timestep)
				{
					rig.step(drive: -1, steerTarget: 0, seconds: Constants.timestep)
				}
				let releasedAt = rig.position.x
				var frames = 0
				while rig.speed != 0 && frames < Int(3 / Constants.timestep)
				{
					rig.step(drive: 0, steerTarget: 0, seconds: Constants.timestep)
					frames += 1
				}
				let gap = (LotSpec.rowPitch - TruckSpec.parkedRigWidth) * world.scale
				XCTAssertLessThan(abs(rig.position.x - releasedAt), gap * 1.6,
					"the stop must fit 1.6x the gap between parked trucks [\(preset.name), reverse x\(tuning.reverseFactor)]")
			}
		}
	}

	/// The reverse dial's ceiling exists for this: it must not make the fold uncatchable.
	func testReverseDialKeepsTheFoldCatchable()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset, tuning: Tuning(reverseFactor: Tuning.highestReverseFactor))
			let clock = world.secondsOfFullLockReverseBeforeJam() ?? .infinity
			XCTAssertGreaterThan(clock, 1.5, "fold must stay catchable at the top of the reverse dial [\(preset.name)]")
		}
	}

	func testTuningIsClampedToTheDialRanges()
	{
		let wild = Tuning(forwardFactor: 99, reverseFactor: 99)
		XCTAssertEqual(wild.forwardFactor, Tuning.highestForwardFactor)
		XCTAssertEqual(wild.reverseFactor, Tuning.highestReverseFactor)
		let timid = Tuning(forwardFactor: 0, reverseFactor: -1)
		XCTAssertEqual(timid.forwardFactor, Tuning.lowestFactor)
		XCTAssertEqual(timid.reverseFactor, Tuning.lowestFactor)
	}

	// MARK: - The fold stop

	func testJammedRigDoesNotMoveAndForwardFreesIt()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset)
			var rig = Rig(at: Placement(position: Point(x: 400, y: 300), heading: 0), world: world)

			for _ in 0 ..< Int(8 / Constants.timestep)
			{
				rig.step(drive: -1, steerTarget: rig.steerLimit, seconds: Constants.timestep)
				XCTAssertLessThanOrEqual(abs(rig.articulation), TruckSpec.maxArticulation + 1e-9,
					"the stored fold must stay inside the limit [\(preset.name)]")
			}

			let jammedPosition = rig.position
			let jammedHeading = rig.heading
			for _ in 0 ..< Int(2 / Constants.timestep)
			{
				rig.step(drive: -1, steerTarget: rig.steerLimit, seconds: Constants.timestep)
			}
			XCTAssertLessThan(hypot(rig.position.x - jammedPosition.x, rig.position.y - jammedPosition.y),
				0.01, "a jammed rig must not creep [\(preset.name)]")
			XCTAssertEqual(rig.heading, jammedHeading, accuracy: 1e-9,
				"a jammed rig must not rotate [\(preset.name)]")

			for _ in 0 ..< Int(3 / Constants.timestep)
			{
				rig.step(drive: 1, steerTarget: 0, seconds: Constants.timestep)
			}
			XCTAssertLessThan(abs(rig.articulation), 1.2,
				"pulling forward must unjam the fold [\(preset.name)]")
		}
	}

	/// A wheel on the ground cannot move sideways. What makes the residue harmless is
	/// that it is discretisation, so it must SHRINK with the timestep. The jackknife bug
	/// this guards against sat at 77px/s at every timestep.
	func testTrailerAxleDoesNotSlipSideways()
	{
		for preset in Preset.all
		{
			let coarse = worstAxleSlip(preset: preset, seconds: Constants.coarseTimestep)
			let fine = worstAxleSlip(preset: preset, seconds: Constants.fineTimestep)
			XCTAssertLessThan(fine, coarse * 0.35,
				"axle slip must be discretisation and shrink with dt: \(coarse) vs \(fine) [\(preset.name)]")
		}
	}

	private func worstAxleSlip(preset: Preset, seconds: Double) -> Double
	{
		let world = World(preset: preset)
		var rig = Rig(at: Placement(position: Point(x: 400, y: 300), heading: 0), world: world)

		let axle = { (state: Rig) -> Point in
			return Point(x: state.position.x - cos(state.trailerHeading) * state.kingpinToAxle,
						 y: state.position.y - sin(state.trailerHeading) * state.kingpinToAxle)
		}

		var previous = axle(rig)
		var worst = 0.0
		for _ in 0 ..< Int(8 / seconds)
		{
			rig.step(drive: -1, steerTarget: rig.steerLimit, seconds: seconds)
			let current = axle(rig)
			let sideways = abs(-sin(rig.trailerHeading) * (current.x - previous.x)
				+ cos(rig.trailerHeading) * (current.y - previous.y)) / seconds
			worst = max(worst, sideways)
			previous = current
		}
		return worst
	}

	// MARK: - The level

	func testLotIsWellFormed()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset)
			let parkedBoxCount = world.lot.parked.count * 2

			for first in 0 ..< parkedBoxCount
			{
				// Walls legitimately overlap each other at the corners, so only parked
				// boxes are checked against everything.
				for second in (first + 1) ..< world.obstacles.count
				{
					XCTAssertFalse(Collision.intersects(world.obstacles[first], world.obstacles[second]),
						"lot obstacles \(first) and \(second) overlap [\(preset.name)]")
				}
			}

			let start = Rig(at: world.level.start, world: world)
			for box in start.collisionBoxes
			{
				for obstacle in world.obstacles
				{
					XCTAssertFalse(Collision.intersects(box, obstacle),
						"the player must not start inside an obstacle [\(preset.name)]")
				}
			}

			let parkedInBay = Collision.boxCorners(centre: world.lot.bayTrailerCentre,
												   length: world.dimensions.trailerLength,
												   width: world.dimensions.trailerWidth,
												   heading: world.lot.bayHeading)
			for obstacle in world.obstacles
			{
				XCTAssertFalse(Collision.intersects(parkedInBay, obstacle),
					"a trailer parked correctly in the bay must not overlap anything [\(preset.name)]")
			}

			for index in 0 ..< parkedBoxCount
			{
				for corner in world.obstacles[index]
				{
					XCTAssertTrue(corner.x > -1 && corner.x < Canvas.width + 1
						&& corner.y > -1 && corner.y < Canvas.height + 1,
						"parked box \(index) falls outside the canvas [\(preset.name)]")
				}
			}
		}
	}

	func testLevelBoundsHoldEveryParkedBoxAndTheStartRig()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset)
			let bounds = world.level.bounds
			let inside = { (point: Point) -> Bool in
				return point.x >= bounds.x - 1e-9 && point.x <= bounds.x + bounds.width + 1e-9
					&& point.y >= bounds.y - 1e-9 && point.y <= bounds.y + bounds.height + 1e-9
			}
			for index in 0 ..< world.lot.parked.count * 2
			{
				for corner in world.obstacles[index]
				{
					XCTAssertTrue(inside(corner), "a parked box must lie inside the level bounds [\(preset.name)]")
				}
			}
			for box in Rig(at: world.level.start, world: world).collisionBoxes
			{
				for corner in box
				{
					XCTAssertTrue(inside(corner), "the start rig must lie inside the level bounds [\(preset.name)]")
				}
			}
		}
	}

	func testLotEdgeDecidesWhetherTheWallsCollide()
	{
		let open = World(preset: .standard, lotEdge: .open)
		XCTAssertEqual(open.obstacles.count, open.lot.parked.count * 2,
			"an open lot collides only with the parked trucks")
		let kerb = World(preset: .standard, lotEdge: .kerb)
		XCTAssertEqual(kerb.obstacles.count, kerb.lot.parked.count * 2 + kerb.lot.walls.count,
			"a kerb adds the four edges")
	}

	/// An obstacle wider than its own picture is invisible by construction: no screenshot
	/// and no playtest can see it. So the sizes are measured rather than trusted.
	func testParkedBoxesAreTheSizeTheyAreDrawn()
	{
		for preset in Preset.all
		{
			let world = World(preset: preset)
			for placement in world.lot.parked
			{
				let boxes = World.parkedBoxes(placement, dimensions: world.dimensions)
				let expected = [(world.dimensions.trailerLength, world.dimensions.trailerWidth),
								(world.dimensions.cabLength, world.dimensions.cabWidth)]
				for (index, box) in boxes.enumerated()
				{
					let length = hypot(box[0].x - box[1].x, box[0].y - box[1].y)
					let width = hypot(box[1].x - box[2].x, box[1].y - box[2].y)
					XCTAssertEqual(length, expected[index].0, accuracy: 1e-9,
						"parked box \(index) length must match its drawing [\(preset.name)]")
					XCTAssertEqual(width, expected[index].1, accuracy: 1e-9,
						"parked box \(index) width must match its drawing [\(preset.name)]")
				}
			}
		}
	}
}
