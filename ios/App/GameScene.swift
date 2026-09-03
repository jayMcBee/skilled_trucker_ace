//	==================================================
//	'GameScene.swift'
//	--------------------------------------------------
//	The playable scene: a procedurally drawn truck stop, the rig, the effects, two
//	thumb pads and the HUD. It steps the physics and tells the sound layer what the
//	truck is doing.
//
//	THE ONE THING TO KNOW: 'Rig.swift' works in canvas coordinates, where +y points
//	DOWN. SpriteKit's +y points UP. Every conversion happens in scenePosition(_:) and
//	sceneRotation(_:) below, and nowhere else. Bypassing them mirrors the whole game,
//	which looks plausible and plays backwards.
//
//	The world lives in `worldLayer`, a Canvas.width x Canvas.height box scaled to fit
//	the screen. The HUD and the pads live in scene space, so they sit the same on any
//	iPad while the lot letterboxes.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit
import SpriteKit

/// Everything one particle burst needs, so a burst is a named recipe and not a row
/// of literals at the call site.
private struct BurstRecipe
{
	let textureDiameter: Int
	let isSquare: Bool
	let count: Int
	let colour: SKColor
	let speed: CGFloat
	let speedRange: CGFloat
	let lifetime: CGFloat
	let scale: CGFloat
	let scaleSpeed: CGFloat
	let alpha: CGFloat
	let alphaSpeed: CGFloat
	let isAdditive: Bool
	let spin: CGFloat
}

final class GameScene: SKScene
{
	// MARK: - Callbacks

	var onOptionsRequested: (() -> Void)?

	// MARK: - Private Properties

	private var world: World
	private var rig: Rig
	private var isRunOver = false
	private var isJammed = false
	private var directionChanges = 0
	private var lastTravelDirection = 0
	private var lastUpdateTime: TimeInterval = 0
	private var throttle = 0.0
	private var steerTarget = 0.0
	private var driveTouch: UITouch?
	private var steerTouch: UITouch?
	private var sound: SoundEngine?
	private var activeSoundChoice = SoundChoice.off
	private var worldBasePosition = CGPoint.zero

	/// Below this the rig counts as stopped, for the win check, the shift count and the lamps.
	private var stoppedThreshold: Double
	{
		return world.dimensions.trailerLength * Constants.winSpeedFractionOfTrailerLength
	}

	private let worldLayer = SKNode()
	private let lotLayer = SKEffectNode()
	private let bayMarking = SKNode()
	private let rigLayer = SKNode()
	private let effectsLayer = SKNode()
	private let hudLayer = SKNode()
	private var trailerNode: TrailerNode
	private var cabNode: CabNode
	private let exhaust = SKEmitterNode()
	private let wedgeFill = SKShapeNode()
	private let wedgeHeadingLine = SKShapeNode()
	private let wedgeWheelCasing = SKShapeNode()
	private let wedgeWheelLine = SKShapeNode()
	private let jammedLabel = SKLabelNode(fontNamed: Constants.heavyFont)
	private let shiftsLabel = SKLabelNode(fontNamed: Constants.boldFont)
	private let speedLabel = SKLabelNode(fontNamed: Constants.boldFont)
	private let bayDistanceLabel = SKLabelNode(fontNamed: Constants.boldFont)
	private let bayAngleLabel = SKLabelNode(fontNamed: Constants.boldFont)
	private let setupLabel = SKLabelNode(fontNamed: Constants.boldFont)
	private let resultOverlay = SKNode()
	private let resultDim = SKSpriteNode(color: .black, size: .zero)
	private let resultTitle = SKLabelNode(fontNamed: Constants.heavyFont)
	private let resultSubtitle = SKLabelNode(fontNamed: Constants.boldFont)
	private let resultHint = SKLabelNode(fontNamed: Constants.boldFont)
	private let flash = SKSpriteNode(color: .red, size: .zero)
	private let drivePad = ThumbPad(axis: .vertical, length: Constants.drivePadLength,
									thickness: Constants.padThickness, endLabels: ("FWD", "REV"))
	private let steerPad = ThumbPad(axis: .horizontal, length: Constants.steerPadLength,
									thickness: Constants.padThickness, endLabels: ("L", "R"))
	private let optionsButton = SKNode()
	private let restartButton = SKNode()

	private enum Constants
	{
		static let boldFont = "AvenirNext-Bold"
		static let heavyFont = "AvenirNext-Heavy"
		static let monoFont = "Menlo-Bold"

		/// The world box, as CGFloat, for everything that lays out in points.
		static let canvasWidth = CGFloat(Canvas.width)
		static let canvasHeight = CGFloat(Canvas.height)
		static let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

		/// Any scrape ends the run, so the win box is generous on angle and tight on
		/// distance. All three mirror the web build exactly.
		static let winDistanceFractionOfTrailerWidth = 0.35
		static let winHeadingTolerance = 0.12
		static let winSpeedFractionOfTrailerLength = 0.01

		/// Backgrounding the app produces one enormous step that would tunnel the rig
		/// straight through a parked truck.
		static let longestTimestep = 1.0 / 30.0
		static let metresPerSecondToKilometresPerHour = 3.6

		static let padInset: CGFloat = 22
		static let padThickness: CGFloat = 84
		static let drivePadLength: CGFloat = 250
		static let steerPadLength: CGFloat = 300
		static let padTouchMargin: CGFloat = 40
		/// Below this deflection the pad reads as centred, so a resting thumb does not creep.
		static let driveDeadZone = 0.12

		static let hudInset: CGFloat = 20
		static let hudFontSize: CGFloat = 17
		static let hudSmallFontSize: CGFloat = 12
		static let hudGap: CGFloat = 6
		static let buttonWidth: CGFloat = 104
		static let buttonHeight: CGFloat = 34
		static let buttonGap: CGFloat = 10
		static let optionsTitle = "OPTIONS"
		static let restartTitle = "RESTART"
		static let resultTitleSize: CGFloat = 44
		static let resultSubtitleSize: CGFloat = 18
		static let resultHintSize: CGFloat = 14
		static let resultDimAlpha: CGFloat = 0.72
		static let jammedText = "JAMMED — DRIVE FORWARD"
		static let jammedFontSize: CGFloat = 12
		static let jammedLabelSideMargin = 90.0
		static let jammedLabelBottomMargin = 26.0
		static let jammedLabelTopMargin = 14.0
		static let jammedLabelLiftInRigWidths = 0.95

		static let shadowOffset = CGVector(dx: 3, dy: -3)
		static let wedgeReachInCabLengths = 2.2
		static let wedgeFillColour = SKColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.26)
		static let wedgeHeadingColour = SKColor(white: 1, alpha: 0.24)
		static let wedgeCasingColour = SKColor(red: 0.01, green: 0.02, blue: 0.09, alpha: 0.7)
		static let wedgeWheelColour = SKColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)

		static let exhaustIdleBirthRate: CGFloat = 4
		static let exhaustBirthRateWithThrottle: CGFloat = 40
		static let shakeSteps = 7
		static let shakeAmplitude: CGFloat = 9
		static let shakeStepDuration = 0.03
		static let shakeActionKey = "shake"
		static let flashPeakAlpha: CGFloat = 0.35
		static let flashAttack = 0.05
		static let flashRelease = 0.35
		static let bayPulseDuration = 0.9
		static let bayPulseLowAlpha: CGFloat = 0.55

		static let lotSeed: UInt64 = 42
		/// Layer order, bottom to top. Ties inside a layer resolve by tree order.
		static let lotLayerZ: CGFloat = 0
		static let bayMarkingZ: CGFloat = 1
		static let rigLayerZ: CGFloat = 5
		static let effectsLayerZ: CGFloat = 8
		static let hudLayerZ: CGFloat = 20
		/// The ground and its markings sit below every truck shadow, which is at -1 in
		/// its own truck.
		static let groundZ: CGFloat = -2
		static let wallZ: CGFloat = 2
		static let lampGlowZ: CGFloat = 3
		static let cabAboveTrailerZ: CGFloat = 1
		static let wedgeZ: CGFloat = 3
		static let jammedLabelZ: CGFloat = 4
		static let buttonZ: CGFloat = 2
		static let flashZ: CGFloat = 4
		static let resultOverlayZ: CGFloat = 5
		static let fullCircle: CGFloat = .pi * 2
		static let asphaltNoiseSmoothness: CGFloat = 0.55
		static let asphaltPatchSmoothness: CGFloat = 0.92
		static let asphaltBlend: CGFloat = 0.9
		static let asphaltPatchAlpha: CGFloat = 0.45
		static let stainCount = 7
		static let stainWidthRange: ClosedRange<CGFloat> = 60 ... 220
		static let stainHeightRange: ClosedRange<CGFloat> = 30 ... 90
		static let scuffCount = 18
		static let scuffEndScatter = 80.0
		static let scuffControlScatter = 60.0
		static let scuffAlphaRange: ClosedRange<CGFloat> = 0.05 ... 0.13
		static let scuffWidthRange: ClosedRange<CGFloat> = 3 ... 7
		static let crackCount = 16
		static let crackSegmentRange = 4 ... 9
		static let crackTurnRange: ClosedRange<CGFloat> = -0.9 ... 0.9
		static let crackStepRange: ClosedRange<CGFloat> = 12 ... 38
		static let crackWidth: CGFloat = 1.2
		static let crackHighlightWidth: CGFloat = 2.5
		static let crackHighlightOffset = CGPoint(x: 1, y: -1)
		static let stallDashPattern: [CGFloat] = [14, 3, 6, 5]
		static let stallDashPhaseStep: CGFloat = 5
		static let stallLineWidth: CGFloat = 1.5
		static let bayOutlineLengthFraction = 1.05
		static let bayOutlineWidthFraction = 1.07
		static let bayLineWidthInRigWidths = 0.05
		static let bayMinimumLineWidth = 2.0
		static let bayGlowWidth: CGFloat = 1
		static let bayFontSizeInRigWidths = 0.19
		static let bayMinimumFontSize = 8.0
		static let lampGlowTextureDiameter = 128

		static let exhaustTextureDiameter = 32
		static let exhaustLifetime: CGFloat = 1.4
		static let exhaustLifetimeRange: CGFloat = 0.6
		static let exhaustSpeed: CGFloat = 6
		static let exhaustSpeedRange: CGFloat = 4
		static let exhaustAlpha: CGFloat = 0.28
		static let exhaustAlphaSpeed: CGFloat = -0.2
		static let exhaustScale: CGFloat = 0.25
		static let exhaustScaleRange: CGFloat = 0.1
		static let exhaustScaleSpeed: CGFloat = 0.5

		static let wedgeHeadingLineWidth: CGFloat = 1.5
		static let wedgeCasingLineWidth: CGFloat = 5
		static let wedgeWheelLineWidth: CGFloat = 2.5
		static let wedgeWheelGlowWidth: CGFloat = 1
		static let hintPulseLowAlpha: CGFloat = 0.3
		static let hintPulseDuration = 0.7
		/// Result text offsets from the screen centre, in units of their own font size.
		static let resultTitleLift: CGFloat = 0.4
		static let resultSubtitleDrop: CGFloat = 1.4
		static let resultHintDrop: CGFloat = 3.4

		/// Everything out within a twentieth of a second: a burst, not a fountain.
		static let burstBirthRatePerParticle: CGFloat = 20
		static let burstLifetimeSpread: CGFloat = 0.5
		static let burstScaleSpread: CGFloat = 0.5
		static let burstRemovalLifetimes = 2.0
		static let jamDustCount = 8
		static let sparks = BurstRecipe(textureDiameter: 16, isSquare: false, count: 60, colour: sparkColour,
										speed: 140, speedRange: 100, lifetime: 0.45, scale: 0.5, scaleSpeed: -0.8,
										alpha: 1, alphaSpeed: -1.8, isAdditive: true, spin: 0)
		static let debris = BurstRecipe(textureDiameter: 6, isSquare: true, count: 18, colour: debrisColour,
										speed: 70, speedRange: 50, lifetime: 0.9, scale: 0.8, scaleSpeed: -0.3,
										alpha: 1, alphaSpeed: -1.0, isAdditive: false, spin: 6)
		static let dust = BurstRecipe(textureDiameter: 32, isSquare: false, count: 14, colour: dustColour,
									  speed: 25, speedRange: 15, lifetime: 1.2, scale: 0.6, scaleSpeed: 1.2,
									  alpha: 0.5, alphaSpeed: -0.4, isAdditive: false, spin: 0)
		static let goldConfetti = BurstRecipe(textureDiameter: 16, isSquare: false, count: 90, colour: confettiGold,
											  speed: 120, speedRange: 80, lifetime: 1.1, scale: 0.5, scaleSpeed: -0.4,
											  alpha: 1, alphaSpeed: -0.9, isAdditive: true, spin: 0)
		static let greenConfetti = BurstRecipe(textureDiameter: 16, isSquare: false, count: 60, colour: goodColour,
											   speed: 90, speedRange: 60, lifetime: 1.3, scale: 0.4, scaleSpeed: -0.3,
											   alpha: 1, alphaSpeed: -0.8, isAdditive: true, spin: 0)

		static let voidColour = SKColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)
		static let asphaltColour = SKColor(red: 0.24, green: 0.26, blue: 0.33, alpha: 1)
		static let wallColour = SKColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1)
		static let kerbColour = SKColor(white: 1, alpha: 0.22)
		static let stallLineColour = SKColor(white: 1, alpha: 0.30)
		static let bayColour = SKColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1)
		static let bayTextColour = SKColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 0.35)
		static let lampGlowColour = SKColor(red: 1, green: 0.76, blue: 0.24, alpha: 1)
		static let lampGlowAlpha: CGFloat = 0.13
		static let crackColour = SKColor(white: 0, alpha: 0.55)
		static let crackHighlightColour = SKColor(white: 1, alpha: 0.05)
		static let scuffColour = SKColor(white: 0, alpha: 1)
		static let stainColour = SKColor(white: 0, alpha: 0.16)
		static let jammedColour = SKColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)
		static let goodColour = SKColor(red: 0.64, green: 0.90, blue: 0.21, alpha: 1)
		static let neutralColour = SKColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
		static let dimTextColour = SKColor(white: 1, alpha: 0.45)
		static let badColour = SKColor(red: 0.96, green: 0.25, blue: 0.37, alpha: 1)
		static let buttonFill = SKColor(white: 1, alpha: 0.08)
		static let buttonStroke = SKColor(white: 1, alpha: 0.18)
		static let playerTrailerColour = SKColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
		static let playerCabColour = SKColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
		static let sparkColour = SKColor(red: 1, green: 0.72, blue: 0.25, alpha: 1)
		static let debrisColour = SKColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1)
		static let dustColour = SKColor(red: 0.60, green: 0.58, blue: 0.50, alpha: 1)
		static let smokeColour = SKColor(white: 0.55, alpha: 1)
		static let confettiGold = SKColor(red: 1, green: 0.85, blue: 0.30, alpha: 1)

		static let parkedTrailerColours: [SKColor] = [
			SKColor(white: 0.97, alpha: 1), SKColor(white: 0.89, alpha: 1),
			SKColor(white: 0.80, alpha: 1), SKColor(white: 0.94, alpha: 1)
		]
		static let parkedCabColours: [SKColor] = [
			SKColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1),
			SKColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1),
			SKColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1),
			SKColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1),
			SKColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1),
			SKColor(white: 0.89, alpha: 1)
		]
		/// Sodium lamps, in canvas units, where the web build painted its glows.
		static let lampGlows: [(x: Double, y: Double, radius: Double)] = [
			(150, 100, 180), (650, 100, 180), (400, 550, 220)
		]
	}

	// MARK: - Init

	override init(size: CGSize)
	{
		let world = World(preset: Options.preset, tuning: Options.tuning)
		self.world = world
		self.rig = Rig(at: world.level.start, world: world)
		self.trailerNode = TrailerNode(dimensions: world.dimensions,
									   bodyColour: Constants.playerTrailerColour, isPlayer: true)
		self.cabNode = CabNode(dimensions: world.dimensions, bodyColour: Constants.playerCabColour, isPlayer: true)
		super.init(size: size)
		scaleMode = .resizeFill
		backgroundColor = Constants.voidColour
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	deinit
	{
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - Lifecycle

	override func didMove(to view: SKView)
	{
		lotLayer.zPosition = Constants.lotLayerZ
		lotLayer.shouldRasterize = true
		bayMarking.zPosition = Constants.bayMarkingZ
		rigLayer.zPosition = Constants.rigLayerZ
		effectsLayer.zPosition = Constants.effectsLayerZ
		hudLayer.zPosition = Constants.hudLayerZ
		worldLayer.addChild(lotLayer)
		worldLayer.addChild(bayMarking)
		worldLayer.addChild(rigLayer)
		worldLayer.addChild(effectsLayer)
		addChild(worldLayer)
		addChild(hudLayer)

		buildLot()
		configureExhaust()
		attachRig()
		buildWedge()
		buildHud()
		refreshSetupLabel()
		layoutScreen()
		restart()
		setSound(Options.soundChoice)

		NotificationCenter.default.addObserver(self, selector: #selector(applicationBecameActive),
											   name: UIApplication.didBecomeActiveNotification, object: nil)
	}

	override func didChangeSize(_ oldSize: CGSize)
	{
		super.didChangeSize(oldSize)
		guard worldLayer.parent != nil
		else { return }
		layoutScreen()
	}

	override func update(_ currentTime: TimeInterval)
	{
		// The first frame has no previous timestamp, and a repeated timestamp gives a
		// zero step, which Rig.step refuses by precondition. Both are skipped.
		let elapsed = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
		lastUpdateTime = currentTime
		guard elapsed > 0
		else { return }

		let seconds = min(elapsed, Constants.longestTimestep)
		if !isRunOver
		{
			advance(by: seconds)
		}
		layoutRig()
		updateSound()
	}

	// MARK: - Public API

	func restart()
	{
		rig = Rig(at: world.level.start, world: world)
		isRunOver = false
		isJammed = false
		directionChanges = 0
		lastTravelDirection = 0
		throttle = 0
		steerTarget = 0
		driveTouch = nil
		steerTouch = nil
		jammedLabel.isHidden = true
		resultOverlay.isHidden = true
		effectsLayer.removeAllChildren()
		worldLayer.removeAction(forKey: Constants.shakeActionKey)
		worldLayer.position = worldBasePosition
		shiftsLabel.text = "SHIFTS 0"
		layoutRig()
		updateBayReadout()
	}

	/// Called when the options sheet closes. Anything that changes the world restarts
	/// the run, because a rig half-way through a manoeuvre in a different lot is
	/// neither the old run nor a new one.
	func applyOptions()
	{
		let wantedPreset = Options.preset
		let wantedTuning = Options.tuning
		if wantedPreset != world.preset || wantedTuning != world.tuning
		{
			world = World(preset: wantedPreset, tuning: wantedTuning)
			buildLot()
			buildRig()
			refreshSetupLabel()
			restart()
		}
		layoutScreen()
		if Options.soundChoice != activeSoundChoice
		{
			setSound(Options.soundChoice)
		}
	}

	/// The sheet pauses the view, so the sound layer would hold its last state under it.
	func quietSound()
	{
		sound?.update(SoundState())
	}

	// MARK: - Private: coordinates

	/// Canvas coordinates (+y down) to worldLayer coordinates (+y up).
	private func scenePosition(_ point: Point) -> CGPoint
	{
		return CGPoint(x: CGFloat(point.x), y: CGFloat(Canvas.height - point.y))
	}

	private func sceneRotation(_ heading: Double) -> CGFloat
	{
		return CGFloat(-heading)
	}

	private func centre(of quad: ConvexQuad) -> Point
	{
		let sumX = quad.reduce(0.0) { $0 + $1.x }
		let sumY = quad.reduce(0.0) { $0 + $1.y }
		return Point(x: sumX / Double(quad.count), y: sumY / Double(quad.count))
	}

	/// A path straight from collision corners, so a drawn shape cannot differ from the
	/// shape it collides as.
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

	// MARK: - Private: the lot

	private func buildLot()
	{
		lotLayer.removeAllChildren()
		bayMarking.removeAllChildren()
		bayMarking.removeAllActions()

		var random = SeededRandom(seed: Constants.lotSeed)
		let canvasSize = Constants.canvasSize
		let canvasCentre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

		// Grain, then larger patches multiplied over it, so the surface reads as worn
		// asphalt rather than a flat colour. Both are noise textures SpriteKit makes itself.
		let grain = SKSpriteNode(texture: SKTexture(noiseWithSmoothness: Constants.asphaltNoiseSmoothness,
													size: canvasSize, grayscale: true), size: canvasSize)
		grain.position = canvasCentre
		grain.color = Constants.asphaltColour
		grain.colorBlendFactor = Constants.asphaltBlend
		grain.zPosition = Constants.groundZ
		lotLayer.addChild(grain)

		let patches = SKSpriteNode(texture: SKTexture(noiseWithSmoothness: Constants.asphaltPatchSmoothness,
													  size: canvasSize, grayscale: true), size: canvasSize)
		patches.position = canvasCentre
		patches.blendMode = .multiply
		patches.alpha = Constants.asphaltPatchAlpha
		patches.zPosition = Constants.groundZ
		lotLayer.addChild(patches)

		addStains(using: &random)
		addScuffs(using: &random)
		addCracks(using: &random)
		addStallLines()
		addBayMarking()
		addParkedRigs()
		addWalls()
		addLampGlows()
	}

	private func addStains(using random: inout SeededRandom)
	{
		for _ in 0 ..< Constants.stainCount
		{
			let stain = SKShapeNode(ellipseOf: CGSize(
				width: CGFloat.random(in: Constants.stainWidthRange, using: &random),
				height: CGFloat.random(in: Constants.stainHeightRange, using: &random)))
			stain.position = CGPoint(x: CGFloat.random(in: 0 ... Constants.canvasWidth, using: &random),
									 y: CGFloat.random(in: 0 ... Constants.canvasHeight, using: &random))
			stain.zRotation = CGFloat.random(in: 0 ... CGFloat.pi, using: &random)
			stain.fillColor = Constants.stainColour
			stain.strokeColor = .clear
			stain.zPosition = Constants.groundZ
			lotLayer.addChild(stain)
		}
	}

	/// Tyre scuffs sweep from the lane into the slots, which is where trucks actually turn.
	private func addScuffs(using random: inout SeededRandom)
	{
		let level = world.level
		let laneLeft = level.leftRowX + world.dimensions.parkedRigLength / 2
		let laneRight = level.rightRowX - world.dimensions.parkedRigLength / 2
		let scatter = Constants.scuffEndScatter
		let bend = Constants.scuffControlScatter
		for _ in 0 ..< Constants.scuffCount
		{
			let startX = Double.random(in: laneLeft ... laneRight, using: &random)
			let startY = Double.random(in: level.firstSlotY ... level.start.position.y, using: &random)
			let towardLeft = Bool.random(using: &random)
			let endX = towardLeft ? level.leftRowX : level.rightRowX
			let endY = startY + Double.random(in: -scatter ... scatter, using: &random)
			let control = Point(x: (startX + endX) / 2, y: startY + Double.random(in: -bend ... bend, using: &random))

			let path = CGMutablePath()
			path.move(to: scenePosition(Point(x: startX, y: startY)))
			path.addQuadCurve(to: scenePosition(Point(x: endX, y: endY)), control: scenePosition(control))
			let scuff = SKShapeNode(path: path)
			scuff.strokeColor = Constants.scuffColour
			scuff.alpha = CGFloat.random(in: Constants.scuffAlphaRange, using: &random)
			scuff.lineWidth = CGFloat.random(in: Constants.scuffWidthRange, using: &random)
			scuff.lineCap = .round
			scuff.zPosition = Constants.groundZ
			lotLayer.addChild(scuff)
		}
	}

	private func addCracks(using random: inout SeededRandom)
	{
		for _ in 0 ..< Constants.crackCount
		{
			var point = CGPoint(x: CGFloat.random(in: 0 ... Constants.canvasWidth, using: &random),
								y: CGFloat.random(in: 0 ... Constants.canvasHeight, using: &random))
			var direction = CGFloat.random(in: 0 ... Constants.fullCircle, using: &random)
			let path = CGMutablePath()
			path.move(to: point)
			for _ in 0 ..< Int.random(in: Constants.crackSegmentRange, using: &random)
			{
				direction += CGFloat.random(in: Constants.crackTurnRange, using: &random)
				let step = CGFloat.random(in: Constants.crackStepRange, using: &random)
				point = CGPoint(x: point.x + cos(direction) * step, y: point.y + sin(direction) * step)
				path.addLine(to: point)
			}
			let highlight = SKShapeNode(path: path)
			highlight.strokeColor = Constants.crackHighlightColour
			highlight.lineWidth = Constants.crackHighlightWidth
			highlight.position = Constants.crackHighlightOffset
			highlight.zPosition = Constants.groundZ
			lotLayer.addChild(highlight)

			let crack = SKShapeNode(path: path)
			crack.strokeColor = Constants.crackColour
			crack.lineWidth = Constants.crackWidth
			crack.zPosition = Constants.groundZ
			lotLayer.addChild(crack)
		}
	}

	/// Worn stall lines between the slots, dashed so they read as paint that has been
	/// driven over for years.
	private func addStallLines()
	{
		let level = world.level
		let halfLength = world.dimensions.parkedRigLength / 2
		for rowX in [level.leftRowX, level.rightRowX]
		{
			for index in 0 ... LotSpec.slotCount
			{
				let y = level.firstSlotY + level.rowPitch * (Double(index) - 0.5)
				let path = CGMutablePath()
				path.move(to: scenePosition(Point(x: rowX - halfLength, y: y)))
				path.addLine(to: scenePosition(Point(x: rowX + halfLength, y: y)))
				let dashed = path.copy(dashingWithPhase: CGFloat(index) * Constants.stallDashPhaseStep,
									   lengths: Constants.stallDashPattern)
				let line = SKShapeNode(path: dashed)
				line.strokeColor = Constants.stallLineColour
				line.lineWidth = Constants.stallLineWidth
				line.zPosition = Constants.groundZ
				lotLayer.addChild(line)
			}
		}
	}

	/// Three sides, open toward the lane, the way a painted bay actually reads. It
	/// pulses, so the eye finds the target without a HUD arrow.
	private func addBayMarking()
	{
		let halfLength = world.dimensions.parkedRigLength / 2 * Constants.bayOutlineLengthFraction
		let halfWidth = world.dimensions.parkedRigWidth / 2 * Constants.bayOutlineWidthFraction
		let bayCentre = world.lot.bayCentre
		let heading = world.lot.bayHeading

		let corner =
		{ (alongLength: Double, acrossWidth: Double) -> Point in
			return Point(x: bayCentre.x + cos(heading) * alongLength - sin(heading) * acrossWidth,
						 y: bayCentre.y + sin(heading) * alongLength + cos(heading) * acrossWidth)
		}
		let path = CGMutablePath()
		path.move(to: scenePosition(corner(halfLength, -halfWidth)))
		path.addLine(to: scenePosition(corner(-halfLength, -halfWidth)))
		path.addLine(to: scenePosition(corner(-halfLength, halfWidth)))
		path.addLine(to: scenePosition(corner(halfLength, halfWidth)))

		let outline = SKShapeNode(path: path)
		outline.strokeColor = Constants.bayColour
		outline.lineWidth = max(Constants.bayMinimumLineWidth,
								world.dimensions.parkedRigWidth * Constants.bayLineWidthInRigWidths)
		outline.lineCap = .square
		outline.glowWidth = Constants.bayGlowWidth
		bayMarking.addChild(outline)

		let label = SKLabelNode(fontNamed: Constants.monoFont)
		label.text = "RESERVED"
		label.fontSize = max(Constants.bayMinimumFontSize,
							 world.dimensions.parkedRigWidth * Constants.bayFontSizeInRigWidths)
		label.fontColor = Constants.bayTextColour
		label.verticalAlignmentMode = .center
		label.position = scenePosition(bayCentre)
		label.zRotation = sceneRotation(heading)
		bayMarking.addChild(label)

		bayMarking.run(.repeatForever(.sequence([
			.fadeAlpha(to: Constants.bayPulseLowAlpha, duration: Constants.bayPulseDuration),
			.fadeAlpha(to: 1, duration: Constants.bayPulseDuration)
		])))
	}

	/// Placed from the same boxes they collide as: the centre of each box is the
	/// centre of its picture.
	private func addParkedRigs()
	{
		for (index, placement) in world.lot.parked.enumerated()
		{
			let boxes = World.parkedBoxes(placement, dimensions: world.dimensions)
			let trailer = TrailerNode(
				dimensions: world.dimensions,
				bodyColour: Constants.parkedTrailerColours[index % Constants.parkedTrailerColours.count],
				isPlayer: false)
			trailer.position = scenePosition(centre(of: boxes[0]))
			trailer.zRotation = sceneRotation(placement.heading)
			trailer.castShadow(worldOffset: Constants.shadowOffset)
			lotLayer.addChild(trailer)

			let cab = CabNode(dimensions: world.dimensions,
							  bodyColour: Constants.parkedCabColours[index % Constants.parkedCabColours.count],
							  isPlayer: false)
			cab.position = scenePosition(centre(of: boxes[1]))
			cab.zRotation = sceneRotation(placement.heading)
			cab.castShadow(worldOffset: Constants.shadowOffset)
			lotLayer.addChild(cab)
		}
	}

	private func addWalls()
	{
		for wall in world.lot.walls
		{
			let node = SKShapeNode(path: path(from: Collision.rectangleCorners(wall)))
			node.fillColor = Constants.wallColour
			node.strokeColor = Constants.kerbColour
			node.lineWidth = 1
			node.zPosition = Constants.wallZ
			lotLayer.addChild(node)
		}
	}

	private func addLampGlows()
	{
		for lamp in Constants.lampGlows
		{
			let glow = SKSpriteNode(texture: ProceduralTexture.softCircle(diameter: Constants.lampGlowTextureDiameter),
									size: CGSize(width: lamp.radius * 2, height: lamp.radius * 2))
			glow.position = scenePosition(Point(x: lamp.x, y: lamp.y))
			glow.color = Constants.lampGlowColour
			glow.colorBlendFactor = 1
			glow.blendMode = .add
			glow.alpha = Constants.lampGlowAlpha
			glow.zPosition = Constants.lampGlowZ
			lotLayer.addChild(glow)
		}
	}

	// MARK: - Private: the rig

	/// Called when the world changes. Only the two truck nodes are replaced: the wedge
	/// and the JAMMED label live in the same layer and must survive.
	private func buildRig()
	{
		trailerNode.removeFromParent()
		cabNode.removeFromParent()
		trailerNode = TrailerNode(dimensions: world.dimensions,
								  bodyColour: Constants.playerTrailerColour, isPlayer: true)
		cabNode = CabNode(dimensions: world.dimensions, bodyColour: Constants.playerCabColour, isPlayer: true)
		attachRig()
	}

	private func attachRig()
	{
		rigLayer.addChild(trailerNode)
		cabNode.zPosition = Constants.cabAboveTrailerZ
		rigLayer.addChild(cabNode)
		exhaust.removeFromParent()
		exhaust.position = cabNode.exhaustAnchor
		cabNode.addChild(exhaust)
	}

	/// Smoke is left behind in the effects layer rather than carried with the cab.
	private func configureExhaust()
	{
		exhaust.particleTexture = ProceduralTexture.softCircle(diameter: Constants.exhaustTextureDiameter)
		exhaust.particleBirthRate = 0
		exhaust.particleLifetime = Constants.exhaustLifetime
		exhaust.particleLifetimeRange = Constants.exhaustLifetimeRange
		exhaust.particleSpeed = Constants.exhaustSpeed
		exhaust.particleSpeedRange = Constants.exhaustSpeedRange
		exhaust.emissionAngleRange = Constants.fullCircle
		exhaust.particleAlpha = Constants.exhaustAlpha
		exhaust.particleAlphaSpeed = Constants.exhaustAlphaSpeed
		exhaust.particleScale = Constants.exhaustScale
		exhaust.particleScaleRange = Constants.exhaustScaleRange
		exhaust.particleScaleSpeed = Constants.exhaustScaleSpeed
		exhaust.particleColor = Constants.smokeColour
		exhaust.particleColorBlendFactor = 1
		exhaust.targetNode = effectsLayer
	}

	/// The steering readout: a dim line along the heading and a bright one at the
	/// wheel angle, filled between. The eye judges the angle between two adjacent
	/// lines far better than one line's absolute direction. Straight edges mean wheel
	/// angle, and nothing else is drawn with straight edges near the nose.
	private func buildWedge()
	{
		wedgeFill.fillColor = Constants.wedgeFillColour
		wedgeFill.strokeColor = .clear
		wedgeHeadingLine.strokeColor = Constants.wedgeHeadingColour
		wedgeHeadingLine.lineWidth = Constants.wedgeHeadingLineWidth
		wedgeWheelCasing.strokeColor = Constants.wedgeCasingColour
		wedgeWheelCasing.lineWidth = Constants.wedgeCasingLineWidth
		wedgeWheelLine.strokeColor = Constants.wedgeWheelColour
		wedgeWheelLine.lineWidth = Constants.wedgeWheelLineWidth
		wedgeWheelLine.glowWidth = Constants.wedgeWheelGlowWidth
		for node in [wedgeFill, wedgeHeadingLine, wedgeWheelCasing, wedgeWheelLine]
		{
			node.zPosition = Constants.wedgeZ
			rigLayer.addChild(node)
		}

		jammedLabel.text = Constants.jammedText
		jammedLabel.fontSize = Constants.jammedFontSize
		jammedLabel.fontColor = Constants.jammedColour
		jammedLabel.zPosition = Constants.jammedLabelZ
		jammedLabel.isHidden = true
		rigLayer.addChild(jammedLabel)
	}

	// MARK: - Private: the HUD

	private func buildHud()
	{
		for label in [shiftsLabel, speedLabel, bayDistanceLabel, bayAngleLabel, setupLabel]
		{
			label.fontSize = Constants.hudFontSize
			label.fontColor = Constants.neutralColour
			label.verticalAlignmentMode = .top
			hudLayer.addChild(label)
		}
		shiftsLabel.horizontalAlignmentMode = .left
		speedLabel.horizontalAlignmentMode = .left
		speedLabel.fontColor = Constants.dimTextColour
		bayDistanceLabel.horizontalAlignmentMode = .right
		bayAngleLabel.horizontalAlignmentMode = .left
		setupLabel.horizontalAlignmentMode = .center
		setupLabel.fontSize = Constants.hudSmallFontSize
		setupLabel.fontColor = Constants.dimTextColour

		makeButton(optionsButton, title: Constants.optionsTitle)
		makeButton(restartButton, title: Constants.restartTitle)

		hudLayer.addChild(drivePad)
		hudLayer.addChild(steerPad)

		resultDim.alpha = Constants.resultDimAlpha
		resultTitle.fontSize = Constants.resultTitleSize
		resultSubtitle.fontSize = Constants.resultSubtitleSize
		resultSubtitle.fontColor = Constants.dimTextColour
		resultHint.fontSize = Constants.resultHintSize
		resultHint.fontColor = Constants.dimTextColour
		resultHint.text = "TAP TO GO AGAIN"
		resultHint.run(.repeatForever(.sequence([
			.fadeAlpha(to: Constants.hintPulseLowAlpha, duration: Constants.hintPulseDuration),
			.fadeAlpha(to: 1, duration: Constants.hintPulseDuration)
		])))
		for node in [resultDim, resultTitle, resultSubtitle, resultHint] as [SKNode]
		{
			resultOverlay.addChild(node)
		}
		resultOverlay.zPosition = Constants.resultOverlayZ
		resultOverlay.isHidden = true
		hudLayer.addChild(resultOverlay)

		flash.alpha = 0
		flash.zPosition = Constants.flashZ
		hudLayer.addChild(flash)
	}

	/// The preset and both dials, with the fold clock: what the options sheet set, in
	/// one line, so a screenshot says what it was taken with.
	private func refreshSetupLabel()
	{
		let foldClock = world.secondsOfFullLockReverseBeforeJam()
		let foldText = foldClock.map { String(format: "FOLD %.1f S", $0) } ?? "NEVER FOLDS"
		setupLabel.text = String(format: "%@ · FWD %.0f KM/H · REV %.0f KM/H · %@",
								 world.preset.name.uppercased(), world.forwardKilometresPerHour,
								 world.reverseKilometresPerHour, foldText)
	}

	private func makeButton(_ button: SKNode, title: String)
	{
		let rect = CGRect(x: -Constants.buttonWidth / 2, y: -Constants.buttonHeight / 2,
						  width: Constants.buttonWidth, height: Constants.buttonHeight)
		let pill = SKShapeNode(rect: rect, cornerRadius: Constants.buttonHeight / 2)
		pill.fillColor = Constants.buttonFill
		pill.strokeColor = Constants.buttonStroke
		pill.lineWidth = 1
		let label = SKLabelNode(fontNamed: Constants.boldFont)
		label.text = title
		label.fontSize = Constants.hudSmallFontSize
		label.fontColor = Constants.dimTextColour
		label.verticalAlignmentMode = .center
		for node in [button, pill, label] as [SKNode]
		{
			node.name = title
		}
		button.addChild(pill)
		button.addChild(label)
		button.zPosition = Constants.buttonZ
		hudLayer.addChild(button)
	}

	/// Everything in scene space is placed from the real size, so the pads sit in the
	/// corners of any iPad while the lot letterboxes in the middle.
	private func layoutScreen()
	{
		let fit = min(size.width / Constants.canvasWidth, size.height / Constants.canvasHeight)
		worldLayer.setScale(fit)
		worldBasePosition = CGPoint(x: (size.width - Constants.canvasWidth * fit) / 2,
									y: (size.height - Constants.canvasHeight * fit) / 2)
		worldLayer.position = worldBasePosition

		let inset = Constants.padInset
		let driveOnLeft = !Options.swapPads
		let driveX = driveOnLeft ? inset + Constants.padThickness / 2 : size.width - inset - Constants.padThickness / 2
		let steerX = driveOnLeft ? size.width - inset - Constants.steerPadLength / 2 : inset + Constants.steerPadLength / 2
		drivePad.position = CGPoint(x: driveX, y: inset + Constants.drivePadLength / 2)
		steerPad.position = CGPoint(x: steerX, y: inset + Constants.padThickness / 2)

		let top = size.height - Constants.hudInset
		shiftsLabel.position = CGPoint(x: Constants.hudInset, y: top)
		speedLabel.position = CGPoint(x: Constants.hudInset, y: top - Constants.hudFontSize - Constants.hudGap)
		bayDistanceLabel.position = CGPoint(x: size.width / 2 - Constants.hudGap, y: top)
		bayAngleLabel.position = CGPoint(x: size.width / 2 + Constants.hudGap, y: top)
		setupLabel.position = CGPoint(x: size.width / 2, y: top - Constants.hudFontSize - Constants.hudGap)

		let buttonY = size.height - Constants.hudInset - Constants.buttonHeight / 2
		optionsButton.position = CGPoint(x: size.width - Constants.hudInset - Constants.buttonWidth / 2, y: buttonY)
		restartButton.position = CGPoint(x: optionsButton.position.x - Constants.buttonWidth - Constants.buttonGap,
										 y: buttonY)

		let centre = CGPoint(x: size.width / 2, y: size.height / 2)
		resultDim.size = size
		resultDim.position = centre
		resultTitle.position = CGPoint(x: centre.x, y: centre.y + Constants.resultTitleSize * Constants.resultTitleLift)
		resultSubtitle.position = CGPoint(x: centre.x,
										  y: centre.y - Constants.resultSubtitleSize * Constants.resultSubtitleDrop)
		resultHint.position = CGPoint(x: centre.x, y: centre.y - Constants.resultSubtitleSize * Constants.resultHintDrop)
		flash.size = size
		flash.position = centre
	}

	// MARK: - Private: simulation

	private func advance(by seconds: Double)
	{
		let articulation = rig.step(drive: throttle, steerTarget: steerTarget, seconds: seconds)

		// Refusing the step means pushing into the fold limit does nothing at all, which
		// on screen is indistinguishable from a dead control. Only true on the frames the
		// player is actually pushing into it, which is when it is worth saying.
		let jammedNow = abs(articulation) > TruckSpec.maxArticulation
		if jammedNow && !isJammed
		{
			sound?.playJam()
			if Options.particlesEnabled
			{
				effectsLayer.addChild(burst(Constants.dust, count: Constants.jamDustCount, at: scenePosition(rig.position)))
			}
		}
		isJammed = jammedNow
		jammedLabel.isHidden = !isJammed

		countDirectionChange()

		if jammedNow && world.tuning.jackknifeEndsRun
		{
			crash(at: rig.position, title: "JACKKNIFED", subtitle: "The cab folded into the trailer nose.")
			return
		}

		for box in rig.collisionBoxes
		{
			for obstacle in world.obstacles where Collision.intersects(box, obstacle)
			{
				crash(at: Collision.contactPoint(box, obstacle), title: "SCRAPED",
					  subtitle: "In a yard this tight, small moves are everything.")
				return
			}
		}

		updateBayReadout()
	}

	/// Counts a shift when the rig actually reverses direction, not when a pad is pressed.
	private func countDirectionChange()
	{
		let direction = rig.speed > stoppedThreshold ? 1 : (rig.speed < -stoppedThreshold ? -1 : 0)
		if direction != 0 && lastTravelDirection != 0 && direction != lastTravelDirection
		{
			directionChanges += 1
			shiftsLabel.text = "SHIFTS \(directionChanges)"
		}
		if direction != 0
		{
			lastTravelDirection = direction
		}
	}

	/// Metres away and degrees off square, separately, each green when it alone is good
	/// enough to win. One blended percentage told the player nothing.
	private func updateBayReadout()
	{
		let trailer = rig.trailerCentre
		let distance = hypot(trailer.x - world.lot.bayTrailerCentre.x, trailer.y - world.lot.bayTrailerCentre.y)
		let headingError = abs(normalizedAngle(rig.trailerHeading - world.lot.bayHeading))
		let distanceTolerance = world.dimensions.trailerWidth * Constants.winDistanceFractionOfTrailerWidth

		bayDistanceLabel.text = String(format: "BAY %.1f m", distance / world.scale)
		bayDistanceLabel.fontColor = distance < distanceTolerance ? Constants.goodColour : Constants.neutralColour
		bayAngleLabel.text = String(format: "%.0f° OFF", headingError * 180 / Double.pi)
		bayAngleLabel.fontColor = headingError < Constants.winHeadingTolerance ? Constants.goodColour : Constants.neutralColour

		let stopped = abs(rig.speed) < stoppedThreshold
		if distance < distanceTolerance && headingError < Constants.winHeadingTolerance && stopped
		{
			park()
		}
	}

	private func park()
	{
		endRun(title: "PARKED", subtitle: "Fitted the rig in with \(directionChanges) direction shifts.",
			   colour: Constants.goodColour)
		sound?.playParked()
		guard Options.particlesEnabled
		else { return }
		let origin = scenePosition(world.lot.bayCentre)
		effectsLayer.addChild(burst(Constants.goldConfetti, at: origin))
		effectsLayer.addChild(burst(Constants.greenConfetti, at: origin))
	}

	private func crash(at point: Point, title: String, subtitle: String)
	{
		endRun(title: title, subtitle: subtitle, colour: Constants.badColour)
		sound?.playCrash()
		shake()
		flash.run(.sequence([.fadeAlpha(to: Constants.flashPeakAlpha, duration: Constants.flashAttack),
							 .fadeAlpha(to: 0, duration: Constants.flashRelease)]))

		guard Options.particlesEnabled
		else { return }
		let origin = scenePosition(point)
		effectsLayer.addChild(burst(Constants.sparks, at: origin))
		effectsLayer.addChild(burst(Constants.debris, at: origin))
		effectsLayer.addChild(burst(Constants.dust, at: origin))
	}

	private func endRun(title: String, subtitle: String, colour: SKColor)
	{
		isRunOver = true
		isJammed = false
		jammedLabel.isHidden = true
		driveTouch = nil
		steerTouch = nil
		throttle = 0
		resultTitle.text = title
		resultTitle.fontColor = colour
		resultSubtitle.text = subtitle
		resultOverlay.isHidden = false
	}

	// MARK: - Private: effects

	private func burst(_ recipe: BurstRecipe, count: Int? = nil, at position: CGPoint) -> SKEmitterNode
	{
		let particles = count ?? recipe.count
		let emitter = SKEmitterNode()
		emitter.particleTexture = recipe.isSquare
			? ProceduralTexture.square(side: recipe.textureDiameter)
			: ProceduralTexture.softCircle(diameter: recipe.textureDiameter)
		emitter.particleBirthRate = CGFloat(particles) * Constants.burstBirthRatePerParticle
		emitter.numParticlesToEmit = particles
		emitter.particleLifetime = recipe.lifetime
		emitter.particleLifetimeRange = recipe.lifetime * Constants.burstLifetimeSpread
		emitter.emissionAngleRange = Constants.fullCircle
		emitter.particleSpeed = recipe.speed
		emitter.particleSpeedRange = recipe.speedRange
		emitter.particleScale = recipe.scale
		emitter.particleScaleRange = recipe.scale * Constants.burstScaleSpread
		emitter.particleScaleSpeed = recipe.scaleSpeed
		emitter.particleAlpha = recipe.alpha
		emitter.particleAlphaSpeed = recipe.alphaSpeed
		emitter.particleColor = recipe.colour
		emitter.particleColorBlendFactor = 1
		emitter.particleBlendMode = recipe.isAdditive ? .add : .alpha
		emitter.particleRotationRange = Constants.fullCircle
		emitter.particleRotationSpeed = recipe.spin
		emitter.position = position
		emitter.run(.sequence([
			.wait(forDuration: TimeInterval(recipe.lifetime) * Constants.burstRemovalLifetimes),
			.removeFromParent()
		]))
		return emitter
	}

	private func shake()
	{
		var moves: [SKAction] = []
		for step in 0 ..< Constants.shakeSteps
		{
			let falloff = 1 - CGFloat(step) / CGFloat(Constants.shakeSteps)
			let offset = CGPoint(x: CGFloat.random(in: -1 ... 1) * Constants.shakeAmplitude * falloff,
								 y: CGFloat.random(in: -1 ... 1) * Constants.shakeAmplitude * falloff)
			moves.append(.move(to: CGPoint(x: worldBasePosition.x + offset.x, y: worldBasePosition.y + offset.y),
							   duration: Constants.shakeStepDuration))
		}
		moves.append(.move(to: worldBasePosition, duration: Constants.shakeStepDuration))
		worldLayer.run(.sequence(moves), withKey: Constants.shakeActionKey)
	}

	// MARK: - Private: drawing the frame

	private func layoutRig()
	{
		let boxes = rig.collisionBoxes
		let cabBox = boxes[0]
		let trailerBox = boxes[1]

		cabNode.position = scenePosition(centre(of: cabBox))
		cabNode.zRotation = sceneRotation(rig.heading)
		cabNode.castShadow(worldOffset: Constants.shadowOffset)
		cabNode.showSteer(sceneAngle: sceneRotation(rig.steerAngle))

		trailerNode.position = scenePosition(centre(of: trailerBox))
		trailerNode.zRotation = sceneRotation(rig.trailerHeading)
		trailerNode.castShadow(worldOffset: Constants.shadowOffset)
		let moving = abs(rig.speed) > stoppedThreshold
		trailerNode.showLamps(braking: moving && throttle == 0, reversing: rig.speed < -stoppedThreshold)

		layoutWedge(cabBox: cabBox)

		let nose = scenePosition(rig.position)
		jammedLabel.position = CGPoint(
			x: clamped(Double(nose.x), Constants.jammedLabelSideMargin,
					   Canvas.width - Constants.jammedLabelSideMargin),
			y: clamped(Double(nose.y) + world.dimensions.parkedRigWidth * Constants.jammedLabelLiftInRigWidths,
					   Constants.jammedLabelBottomMargin, Canvas.height - Constants.jammedLabelTopMargin))

		drivePad.showKnob(fraction: CGFloat(throttle), isActive: driveTouch != nil)
		steerPad.showKnob(fraction: CGFloat(rig.steerAngle / rig.steerLimit), isActive: steerTouch != nil)

		let kilometresPerHour = abs(rig.speed) / world.scale * Constants.metresPerSecondToKilometresPerHour
		speedLabel.text = String(format: "%.0f km/h", kilometresPerHour)

		let wantsSmoke = Options.particlesEnabled && !isRunOver
		exhaust.particleBirthRate = wantsSmoke
			? Constants.exhaustIdleBirthRate + Constants.exhaustBirthRateWithThrottle * CGFloat(abs(throttle)) : 0
	}

	/// The wedge hangs off the front edge of the cab box, so it moves with the shape
	/// that is drawn rather than with a point that is not.
	private func layoutWedge(cabBox: ConvexQuad)
	{
		let frontMid = Point(x: (cabBox[1].x + cabBox[2].x) / 2, y: (cabBox[1].y + cabBox[2].y) / 2)
		let origin = scenePosition(frontMid)
		let reach = CGFloat(world.dimensions.cabLength * Constants.wedgeReachInCabLengths)
		let headingAngle = sceneRotation(rig.heading)
		let wheelAngle = sceneRotation(rig.heading + rig.steerAngle)
		let headingEnd = CGPoint(x: origin.x + cos(headingAngle) * reach, y: origin.y + sin(headingAngle) * reach)
		let wheelEnd = CGPoint(x: origin.x + cos(wheelAngle) * reach, y: origin.y + sin(wheelAngle) * reach)

		let fill = CGMutablePath()
		fill.move(to: origin)
		fill.addLine(to: headingEnd)
		fill.addLine(to: wheelEnd)
		fill.closeSubpath()
		wedgeFill.path = fill
		wedgeFill.isHidden = rig.steerAngle == 0

		let headingPath = CGMutablePath()
		headingPath.move(to: origin)
		headingPath.addLine(to: headingEnd)
		wedgeHeadingLine.path = headingPath

		let wheelPath = CGMutablePath()
		wheelPath.move(to: origin)
		wheelPath.addLine(to: wheelEnd)
		wedgeWheelCasing.path = wheelPath
		wedgeWheelLine.path = wheelPath
	}

	// MARK: - Private: sound

	private func setSound(_ choice: SoundChoice)
	{
		sound?.stop()
		sound = nil
		switch choice
		{
			case .off:
				break
			case .synthesised:
				sound = SynthesisedSoundEngine()
			case .sampled:
				sound = SampledSoundEngine()
		}
		sound?.start()
		activeSoundChoice = choice
	}

	private func updateSound()
	{
		guard let sound = sound
		else { return }
		var state = SoundState()
		if !isRunOver
		{
			let topSpeed = rig.speed >= 0 ? world.maxForwardSpeed : world.maxReverseSpeed
			state.speedFraction = min(1, abs(rig.speed) / topSpeed)
			state.throttle = throttle
			state.isReversing = rig.speed < -stoppedThreshold
		}
		sound.update(state)
	}

	/// Backgrounding stops the audio session. A stop and a start rebuilds whatever
	/// the system tore down.
	@objc private func applicationBecameActive()
	{
		sound?.stop()
		sound?.start()
	}

	// MARK: - Private: touch

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		for touch in touches
		{
			let location = touch.location(in: self)
			let hits = nodes(at: location)
			if hits.contains(where: { $0.name == Constants.optionsTitle })
			{
				onOptionsRequested?()
				return
			}
			if hits.contains(where: { $0.name == Constants.restartTitle })
			{
				restart()
				return
			}
			if isRunOver
			{
				restart()
				return
			}
			claim(touch, at: location)
		}
		applyTouches()
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		applyTouches()
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		release(touches)
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
	{
		release(touches)
	}

	/// A thumb that lands on or near a pad takes it. One that lands anywhere in the
	/// lower half takes the pad on its side of the screen, so a hurried thumb still works.
	private func claim(_ touch: UITouch, at location: CGPoint)
	{
		if driveTouch == nil && drivePad.accepts(location, margin: Constants.padTouchMargin)
		{
			driveTouch = touch
			return
		}
		if steerTouch == nil && steerPad.accepts(location, margin: Constants.padTouchMargin)
		{
			steerTouch = touch
			return
		}
		guard location.y < size.height / 2
		else { return }
		let driveSide = drivePad.position.x < size.width / 2 ? location.x < size.width / 2 : location.x >= size.width / 2
		if driveSide && driveTouch == nil
		{
			driveTouch = touch
		}
		else if !driveSide && steerTouch == nil
		{
			steerTouch = touch
		}
	}

	private func release(_ touches: Set<UITouch>)
	{
		for touch in touches
		{
			if touch === driveTouch
			{
				driveTouch = nil
			}
			// Lifting the steering thumb HOLDS the angle. Nothing on this truck springs
			// back: the wheel is a position, not a nudge.
			if touch === steerTouch
			{
				steerTouch = nil
			}
		}
		applyTouches()
	}

	private func applyTouches()
	{
		if let touch = driveTouch
		{
			let fraction = Double(drivePad.fraction(for: touch.location(in: self)))
			let magnitude = abs(fraction)
			throttle = magnitude < Constants.driveDeadZone ? 0
				: (fraction < 0 ? -1 : 1) * (magnitude - Constants.driveDeadZone) / (1 - Constants.driveDeadZone)
		}
		else
		{
			throttle = 0
		}

		if let touch = steerTouch
		{
			// Absolute, not incremental: the thumb's position across the pad IS the wheel
			// angle. The rig's own steer rate still limits how fast the wheel gets there.
			steerTarget = Double(steerPad.fraction(for: touch.location(in: self))) * rig.steerLimit
		}
		else
		{
			steerTarget = rig.steerAngle
		}
	}
}
