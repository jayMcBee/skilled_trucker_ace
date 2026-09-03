//	==================================================
//	'GameScene.swift'
//	--------------------------------------------------
//	The playable scene: draws the lot and the rig, steps the physics, and turns two
//	thumb pads into a drive command and a steering angle.
//
//	THE ONE THING TO KNOW: 'Rig.swift' works in canvas coordinates, where +y points
//	DOWN. SpriteKit's +y points UP. Every conversion happens in scenePosition(_:) and
//	sceneRotation(_:) below, and nowhere else. Bypassing them mirrors the whole game,
//	which looks plausible and plays backwards.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit
import SpriteKit

final class GameScene: SKScene
{
	// MARK: - Private Properties

	private var world: World
	private var rig: Rig
	private var isRunOver = false
	private var isJammed = false
	private var directionChanges = 0
	private var lastTravelDirection = 0
	private var lastUpdateTime: TimeInterval = 0

	private var driveCommand = 0.0
	private var steerTarget = 0.0
	private var driveTouch: UITouch?
	private var steerTouch: UITouch?

	private let rigLayer = SKNode()
	private let cabNode = SKShapeNode()
	private let trailerNode = SKShapeNode()
	private let jammedLabel = SKLabelNode(fontNamed: Constants.boldFontName)
	private let resultLabel = SKLabelNode(fontNamed: Constants.boldFontName)
	private let bayReadoutLabel = SKLabelNode(fontNamed: Constants.boldFontName)
	private let steerKnob = SKShapeNode(circleOfRadius: Constants.knobRadius)
	private let drivePadNode = SKShapeNode()
	private let steerPadNode = SKShapeNode()

	private enum Constants
	{
		static let boldFontName = "HelveticaNeue-Bold"

		/// Any scrape ends the run, so the win box is generous on angle and tight on
		/// distance. Both mirror the web build exactly.
		static let winDistanceFractionOfTrailerWidth = 0.35
		static let winHeadingTolerance = 0.12
		static let winSpeedFractionOfTrailerLength = 0.01

		static let padHeight = 150.0
		static let padInset = 24.0
		static let padWidth = 300.0
		static let padCornerRadius = 18.0
		static let knobRadius = 26.0
		static let driveDeadZoneFraction = 0.18

		static let trailerColour = SKColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
		static let cabColour = SKColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
		static let asphaltColour = SKColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)
		static let wallColour = SKColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1)
		static let bayColour = SKColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1)
		static let jammedColour = SKColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)
		static let goodColour = SKColor(red: 0.64, green: 0.90, blue: 0.21, alpha: 1)
		static let neutralColour = SKColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)

		static let parkedTrailerColours: [SKColor] = [
			SKColor(white: 0.97, alpha: 1), SKColor(white: 0.89, alpha: 1),
			SKColor(white: 0.80, alpha: 1), SKColor(white: 0.94, alpha: 1)
		]
		static let parkedCabColours: [SKColor] = [
			SKColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1),
			SKColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1),
			SKColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1),
			SKColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1),
			SKColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1)
		]
	}

	// MARK: - Init

	override init(size: CGSize)
	{
		let initialWorld = World(preset: .standard)
		self.world = initialWorld
		self.rig = Rig(at: initialWorld.level.start, world: initialWorld)
		super.init(size: size)
		self.scaleMode = .aspectFit
		self.backgroundColor = Constants.asphaltColour
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	// MARK: - Lifecycle

	override func didMove(to view: SKView)
	{
		buildStaticLot()
		buildRigNodes()
		buildOverlay()
		restart()
	}

	override func update(_ currentTime: TimeInterval)
	{
		// The first frame has no previous timestamp, and a repeated timestamp gives a
		// zero step, which Rig.step refuses by precondition. Both are skipped rather
		// than guessed at.
		let elapsed = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
		lastUpdateTime = currentTime
		guard elapsed > 0
		else { return }

		// Backgrounding the app produces one enormous step that would tunnel the rig
		// straight through a parked truck.
		let seconds = min(elapsed, 1.0 / 30.0)
		advance(by: seconds)
		layoutRig()
	}

	// MARK: - Public API

	func restart()
	{
		rig = Rig(at: world.level.start, world: world)
		isRunOver = false
		isJammed = false
		directionChanges = 0
		lastTravelDirection = 0
		driveCommand = 0
		steerTarget = 0
		jammedLabel.isHidden = true
		resultLabel.isHidden = true
		layoutRig()
	}

	// MARK: - Private: coordinates

	/// Canvas coordinates (+y down) to scene coordinates (+y up). The scene is exactly
	/// Canvas.width x Canvas.height and scales with .aspectFit, so any iPad letterboxes
	/// the same lot rather than seeing more or less of it.
	private func scenePosition(_ point: Point) -> CGPoint
	{
		return CGPoint(x: CGFloat(point.x), y: CGFloat(Canvas.height - point.y))
	}

	private func sceneRotation(_ heading: Double) -> CGFloat
	{
		return CGFloat(-heading)
	}

	/// Builds a path straight from collision corners, so a drawn shape cannot differ
	/// from the shape it collides as. That mismatch cost the web build an invisible
	/// 0.83m kill zone around every parked truck.
	private func path(from quad: ConvexQuad) -> CGPath
	{
		let path = CGMutablePath()
		path.move(to: scenePosition(quad[0]))
		for corner in quad.dropFirst()
		{
			path.addLine(to: scenePosition(corner))
		}
		path.closeSubpath()
		return path
	}

	// MARK: - Private: building the scene

	private func buildStaticLot()
	{
		for (index, placement) in world.lot.parked.enumerated()
		{
			let boxes = World.parkedBoxes(placement, dimensions: world.dimensions)
			let colours = [Constants.parkedTrailerColours[index % Constants.parkedTrailerColours.count],
						   Constants.parkedCabColours[index % Constants.parkedCabColours.count]]
			for (part, box) in boxes.enumerated()
			{
				let node = SKShapeNode(path: path(from: box))
				node.fillColor = colours[part]
				node.strokeColor = .clear
				node.zPosition = 1
				addChild(node)
			}
		}

		for wall in world.lot.walls
		{
			let node = SKShapeNode(path: path(from: Collision.rectangleCorners(wall)))
			node.fillColor = Constants.wallColour
			node.strokeColor = .clear
			node.zPosition = 1
			addChild(node)
		}

		addChild(buildBayMarking())
	}

	/// Three sides, open toward the lane, the way a painted bay actually reads.
	private func buildBayMarking() -> SKShapeNode
	{
		let halfLength = world.dimensions.parkedRigLength / 2.0
		let halfWidth = world.dimensions.parkedRigWidth / 2.0
		let centre = world.lot.bayCentre
		let heading = world.lot.bayHeading

		let corner = { (alongLength: Double, acrossWidth: Double) -> Point in
			return Point(x: centre.x + cos(heading) * alongLength - sin(heading) * acrossWidth,
						 y: centre.y + sin(heading) * alongLength + cos(heading) * acrossWidth)
		}

		let path = CGMutablePath()
		path.move(to: scenePosition(corner(halfLength, -halfWidth)))
		path.addLine(to: scenePosition(corner(-halfLength, -halfWidth)))
		path.addLine(to: scenePosition(corner(-halfLength, halfWidth)))
		path.addLine(to: scenePosition(corner(halfLength, halfWidth)))

		let node = SKShapeNode(path: path)
		node.strokeColor = Constants.bayColour
		node.lineWidth = 3
		node.zPosition = 0
		return node
	}

	private func buildRigNodes()
	{
		trailerNode.strokeColor = .clear
		trailerNode.fillColor = Constants.trailerColour
		cabNode.strokeColor = .clear
		cabNode.fillColor = Constants.cabColour
		rigLayer.zPosition = 5
		rigLayer.addChild(trailerNode)
		rigLayer.addChild(cabNode)
		addChild(rigLayer)
	}

	private func buildOverlay()
	{
		jammedLabel.text = "JAMMED — DRIVE FORWARD"
		jammedLabel.fontSize = 22
		jammedLabel.fontColor = Constants.jammedColour
		jammedLabel.zPosition = 20
		jammedLabel.isHidden = true
		addChild(jammedLabel)

		bayReadoutLabel.fontSize = 18
		bayReadoutLabel.fontColor = Constants.neutralColour
		bayReadoutLabel.horizontalAlignmentMode = .right
		bayReadoutLabel.position = CGPoint(x: size.width - CGFloat(Constants.padInset),
										   y: size.height - CGFloat(Constants.padInset) - 18)
		bayReadoutLabel.zPosition = 20
		addChild(bayReadoutLabel)

		resultLabel.fontSize = 34
		resultLabel.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
		resultLabel.zPosition = 25
		resultLabel.isHidden = true
		addChild(resultLabel)

		configurePad(drivePadNode, centredAt: drivePadCentre)
		configurePad(steerPadNode, centredAt: steerPadCentre)

		steerKnob.fillColor = Constants.neutralColour
		steerKnob.strokeColor = .clear
		steerKnob.zPosition = 16
		steerKnob.position = steerPadCentre
		addChild(steerKnob)
	}

	private func configurePad(_ pad: SKShapeNode, centredAt centre: CGPoint)
	{
		let rect = CGRect(x: CGFloat(-Constants.padWidth / 2.0), y: CGFloat(-Constants.padHeight / 2.0),
						  width: CGFloat(Constants.padWidth), height: CGFloat(Constants.padHeight))
		pad.path = CGPath(roundedRect: rect, cornerWidth: CGFloat(Constants.padCornerRadius),
						  cornerHeight: CGFloat(Constants.padCornerRadius), transform: nil)
		pad.position = centre
		pad.fillColor = SKColor(white: 1, alpha: 0.06)
		pad.strokeColor = SKColor(white: 1, alpha: 0.12)
		pad.zPosition = 15
		addChild(pad)
	}

	private var drivePadCentre: CGPoint
	{
		return CGPoint(x: CGFloat(Constants.padInset + Constants.padWidth / 2.0),
					   y: CGFloat(Constants.padInset + Constants.padHeight / 2.0))
	}

	private var steerPadCentre: CGPoint
	{
		return CGPoint(x: size.width - CGFloat(Constants.padInset + Constants.padWidth / 2.0),
					   y: CGFloat(Constants.padInset + Constants.padHeight / 2.0))
	}

	// MARK: - Private: simulation

	private func advance(by seconds: Double)
	{
		guard !isRunOver
		else { return }

		let articulation = rig.step(drive: driveCommand, steerTarget: steerTarget, seconds: seconds)

		// Refusing the step means pushing into the fold limit does nothing at all, which
		// on screen is indistinguishable from a dead control. Only true on the frames the
		// player is actually pushing into it, which is when it is worth saying.
		isJammed = abs(articulation) > TruckSpec.maxArticulation
		jammedLabel.isHidden = !isJammed

		countDirectionChange()

		for box in rig.collisionBoxes
		{
			for obstacle in world.obstacles
			{
				if Collision.intersects(box, obstacle)
				{
					endRun(saying: "SCRAPED — TAP TO RETRY", colour: Constants.cabColour)
					return
				}
			}
		}

		updateBayReadout()
	}

	/// Counts a shift when the rig actually reverses direction, not when a pad is pressed.
	private func countDirectionChange()
	{
		let threshold = world.dimensions.trailerLength * Constants.winSpeedFractionOfTrailerLength
		let direction = rig.speed > threshold ? 1 : (rig.speed < -threshold ? -1 : 0)
		if direction != 0 && lastTravelDirection != 0 && direction != lastTravelDirection
			directionChanges += 1
		if direction != 0
			lastTravelDirection = direction
	}

	/// Metres away and degrees off square, separately. One blended percentage told the
	/// player nothing: the same number meant close-and-crooked or straight-and-far.
	private func updateBayReadout()
	{
		let trailer = rig.trailerCentre
		let distance = hypot(trailer.x - world.lot.bayTrailerCentre.x,
							 trailer.y - world.lot.bayTrailerCentre.y)
		let headingError = abs(normalizedAngle(rig.trailerHeading - world.lot.bayHeading))
		let distanceTolerance = world.dimensions.trailerWidth * Constants.winDistanceFractionOfTrailerWidth

		let metres = distance / world.scale
		let degrees = headingError * 180.0 / Double.pi
		bayReadoutLabel.text = String(format: "Bay: %.1f m away, %.0f° off", metres, degrees)
		bayReadoutLabel.fontColor = distance < distanceTolerance && headingError < Constants.winHeadingTolerance
			? Constants.goodColour : Constants.neutralColour

		let stopped = abs(rig.speed) < world.dimensions.trailerLength * Constants.winSpeedFractionOfTrailerLength
		if distance < distanceTolerance && headingError < Constants.winHeadingTolerance && stopped
			endRun(saying: "PARKED IN \(directionChanges) SHIFTS — TAP TO GO AGAIN",
				   colour: Constants.goodColour)
	}

	private func endRun(saying text: String, colour: SKColor)
	{
		isRunOver = true
		isJammed = false
		jammedLabel.isHidden = true
		resultLabel.text = text
		resultLabel.fontColor = colour
		resultLabel.isHidden = false
	}

	private func layoutRig()
	{
		let boxes = rig.collisionBoxes
		cabNode.path = path(from: boxes[0])
		trailerNode.path = path(from: boxes[1])

		let nose = scenePosition(rig.position)
		let labelX = clamped(Double(nose.x), Constants.padWidth / 2.0,
							 Double(size.width) - Constants.padWidth / 2.0)
		let labelY = clamped(Double(nose.y) + world.dimensions.parkedRigWidth,
							 40, Double(size.height) - 30)
		jammedLabel.position = CGPoint(x: CGFloat(labelX), y: CGFloat(labelY))

		let knobReach = Constants.padWidth / 2.0 - Constants.knobRadius
		steerKnob.position = CGPoint(
			x: steerPadCentre.x + CGFloat(rig.steerAngle / rig.steerLimit * knobReach),
			y: steerPadCentre.y)
	}

	// MARK: - Private: touch

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		if isRunOver
		{
			restart()
			return
		}

		for touch in touches
		{
			let location = touch.location(in: self)
			if location.x < size.width / 2.0
			{
				driveTouch = touch
			}
			else
			{
				steerTouch = touch
			}
		}
		applyTouches()
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		applyTouches()
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		releaseTouches(touches)
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		releaseTouches(touches)
	}

	private func releaseTouches(_ touches: Set<UITouch>)
	{
		for touch in touches
		{
			if touch === driveTouch
			{
				driveTouch = nil
				driveCommand = 0
			}
			// Lifting the steering thumb must HOLD the angle, not centre it. Nothing on
			// this truck springs back, and the wheel is a position, not a nudge.
			if touch === steerTouch
				steerTouch = nil
		}
		applyTouches()
	}

	private func applyTouches()
	{
		if let touch = driveTouch
		{
			let offset = Double(touch.location(in: self).y - drivePadCentre.y)
			let deadZone = Constants.padHeight * Constants.driveDeadZoneFraction
			driveCommand = abs(offset) < deadZone ? 0 : (offset > 0 ? 1 : -1)
		}
		else
		{
			driveCommand = 0
		}

		if let touch = steerTouch
		{
			// Absolute, not incremental: the thumb's position across the pad IS the wheel
			// angle. That is the one thing a touch screen does better than a key, and the
			// rig's own steer rate still limits how fast the wheel gets there.
			let reach = Constants.padWidth / 2.0 - Constants.knobRadius
			let offset = Double(touch.location(in: self).x - steerPadCentre.x)
			steerTarget = clamped(offset / reach, -1, 1) * rig.steerLimit
		}
		else
		{
			steerTarget = rig.steerAngle
		}
	}
}
