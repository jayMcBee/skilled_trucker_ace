//	==================================================
//	'TruckArt.swift'
//	--------------------------------------------------
//	The trailer and the cab as nodes: one baked sprite each, from 'tools/make_trucks.py',
//	drawn in local units where +x is forward. The sprite is exactly the collision box,
//	so the picture and the shape it collides as cannot drift apart: an obstacle wider
//	than its picture is invisible by construction, and one narrower than it feels
//	cheated. The player's cab is baked without front wheels; they are drawn here in the
//	same style and place as the baked tyres, and they turn with the wheel.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import SpriteKit

/// Colours and sizes both node classes share.
private enum TruckPalette
{
	static let shadowColour = SKColor(white: 0, alpha: 0.55)
	/// The baked tyres' dark, with a mid-grey tread: enough to read on the red cab
	/// without turning the pair into two white bars.
	static let tyreColour = SKColor(red: 0.094, green: 0.094, blue: 0.11, alpha: 1)
	static let tyreTreadColour = SKColor(red: 0.52, green: 0.54, blue: 0.58, alpha: 1)
	static let tyreCornerRadius: CGFloat = 0.75
	static let lampRedColour = SKColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
	static let lampWhiteColour = SKColor(white: 1, alpha: 1)
	static let glowTextureDiameter = 64
	/// Under the body, which sits at 0 in its own node.
	static let shadowZ: CGFloat = -1
	/// Left and right of the centreline, in local units.
	static let sides: [CGFloat] = [-1, 1]
}

/// Shared drawing helpers for the two node classes.
private struct TruckPaint
{
	static func rectangle(centre: CGPoint, size: CGSize, fill: SKColor, corner: CGFloat = 0) -> SKShapeNode
	{
		let rect = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
						  width: size.width, height: size.height)
		let node = SKShapeNode(rect: rect, cornerRadius: corner)
		node.fillColor = fill
		node.strokeColor = .clear
		node.isAntialiased = true
		return node
	}

	static func shadow(size: CGSize) -> SKShapeNode
	{
		let node = rectangle(centre: .zero, size: size, fill: TruckPalette.shadowColour)
		node.zPosition = TruckPalette.shadowZ
		return node
	}

	/// The baked sprite, or a flat block of `fallback` when the PNG is not in the bundle,
	/// so the game still plays without its art.
	static func body(texture: SKTexture?, size: CGSize, fallback: SKColor) -> SKSpriteNode
	{
		if let texture = texture
		{
			return SKSpriteNode(texture: texture, size: size)
		}
		return SKSpriteNode(color: fallback, size: size)
	}

	static func glow(colour: SKColor, diameter: CGFloat) -> SKSpriteNode
	{
		let sprite = SKSpriteNode(texture: ProceduralTexture.softCircle(diameter: TruckPalette.glowTextureDiameter),
								  size: CGSize(width: diameter, height: diameter))
		sprite.color = colour
		sprite.colorBlendFactor = 1
		sprite.blendMode = .add
		return sprite
	}

	/// Rotates a world-space offset into this node's local space, so every shadow in
	/// the lot falls the same way no matter which way the truck points.
	static func localOffset(_ worldOffset: CGVector, rotation: CGFloat) -> CGPoint
	{
		let cosine = cos(-rotation)
		let sine = sin(-rotation)
		return CGPoint(x: worldOffset.dx * cosine - worldOffset.dy * sine,
					   y: worldOffset.dx * sine + worldOffset.dy * cosine)
	}
}

// MARK: - Trailer

final class TrailerNode: SKNode
{
	// MARK: - Private Properties

	private let shadow: SKShapeNode
	private let leftLamp: SKSpriteNode
	private let rightLamp: SKSpriteNode

	private enum Constants
	{
		/// Where the baked tail lamps sit: at the rear edge, this far in from each side.
		static let lampInsetFraction = 0.13
		static let lampGlowDiameterFraction = 0.45
		static let playerLampGlowDiameterFraction = 0.9
		static let lampIdleAlpha: CGFloat = 0.3
		static let lampBrakeAlpha: CGFloat = 0.9
		static let lampReverseAlpha: CGFloat = 0.7
	}

	// MARK: - Init

	init(dimensions: TruckDimensions, texture: SKTexture?, fallbackColour: SKColor, isPlayer: Bool)
	{
		let length = CGFloat(dimensions.trailerLength)
		let width = CGFloat(dimensions.trailerWidth)
		let size = CGSize(width: length, height: width)
		shadow = TruckPaint.shadow(size: size)
		let lampDiameter = width * (isPlayer ? Constants.playerLampGlowDiameterFraction
										   : Constants.lampGlowDiameterFraction)
		leftLamp = TruckPaint.glow(colour: TruckPalette.lampRedColour, diameter: lampDiameter)
		rightLamp = TruckPaint.glow(colour: TruckPalette.lampRedColour, diameter: lampDiameter)
		super.init()

		addChild(shadow)
		addChild(TruckPaint.body(texture: texture, size: size, fallback: fallbackColour))

		let lampY = width / 2 - width * Constants.lampInsetFraction
		for (side, glow) in zip(TruckPalette.sides, [leftLamp, rightLamp])
		{
			glow.position = CGPoint(x: -length / 2, y: side * lampY)
			glow.alpha = Constants.lampIdleAlpha
			addChild(glow)
		}
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	// MARK: - Public API

	func castShadow(worldOffset: CGVector)
	{
		shadow.position = TruckPaint.localOffset(worldOffset, rotation: zRotation)
	}

	/// Brake lights when slowing, white lights when backing up, a dim red otherwise.
	func showLamps(braking: Bool, reversing: Bool)
	{
		let colour = reversing ? TruckPalette.lampWhiteColour : TruckPalette.lampRedColour
		let alpha = reversing ? Constants.lampReverseAlpha
			: (braking ? Constants.lampBrakeAlpha : Constants.lampIdleAlpha)
		for lamp in [leftLamp, rightLamp]
		{
			lamp.color = colour
			lamp.alpha = alpha
		}
	}
}

// MARK: - Cab

final class CabNode: SKNode
{
	// MARK: - Public Properties

	/// Where the exhaust stack is baked, in local units, for the smoke emitter.
	let exhaustAnchor: CGPoint

	// MARK: - Private Properties

	private let shadow: SKShapeNode
	private let steeredWheels: [SKNode]

	private enum Constants
	{
		/// The baked front tyres: 20 x 10 px in a 112 x 96 px cab, centred 20 px from the
		/// front and 7 px from each side, with a lighter tread block inside.
		static let wheelLengthFraction = 0.176
		static let wheelWidthFraction = 0.102
		static let treadLengthFraction = 0.7
		static let treadWidthFraction = 0.4
		static let frontAxleFraction = 0.317
		static let wheelTrackFraction = 0.418
		/// The stack in the baked cab: rear left of the roof.
		static let exhaustXFraction = -0.36
		static let exhaustYFraction = 0.35
		/// Above the body, so the turning pair is never covered.
		static let steeredWheelZ: CGFloat = 2
		/// Full lock is only 24 degrees, which on a 5-unit wheel moves the tip about 2px.
		/// A little more than real still reads as "turning" without looking bent.
		static let steerExaggeration: CGFloat = 1.3
	}

	// MARK: - Init

	/// The player's cab is baked without front wheels and gets the steered pair here, in
	/// the baked tyres' place, at `wheelScale` times their size, kept inside the box. A
	/// parked cab has its wheels baked in.
	init(dimensions: TruckDimensions, texture: SKTexture?, fallbackColour: SKColor, isPlayer: Bool,
		 wheelScale: CGFloat = 1)
	{
		let length = CGFloat(dimensions.cabLength)
		let width = CGFloat(dimensions.cabWidth)
		let size = CGSize(width: length, height: width)
		shadow = TruckPaint.shadow(size: size)
		exhaustAnchor = CGPoint(x: length * Constants.exhaustXFraction, y: width * Constants.exhaustYFraction)

		var wheels: [SKNode] = []
		if isPlayer
		{
			let wheelLength = length * Constants.wheelLengthFraction * wheelScale
			let wheelWidth = width * Constants.wheelWidthFraction * wheelScale
			// A bigger tyre moves inward rather than past the box edge.
			let track = min(width * Constants.wheelTrackFraction, width / 2 - wheelWidth / 2)
			for side in TruckPalette.sides
			{
				let wheel = SKNode()
				wheel.position = CGPoint(x: length * Constants.frontAxleFraction, y: side * track)
				let tyre = TruckPaint.rectangle(centre: .zero, size: CGSize(width: wheelLength, height: wheelWidth),
												fill: TruckPalette.tyreColour, corner: TruckPalette.tyreCornerRadius)
				let tread = TruckPaint.rectangle(
					centre: .zero,
					size: CGSize(width: wheelLength * Constants.treadLengthFraction,
								 height: wheelWidth * Constants.treadWidthFraction),
					fill: TruckPalette.tyreTreadColour)
				wheel.addChild(tyre)
				wheel.addChild(tread)
				wheels.append(wheel)
			}
		}
		steeredWheels = wheels
		super.init()

		addChild(shadow)
		addChild(TruckPaint.body(texture: texture, size: size, fallback: fallbackColour))
		for wheel in steeredWheels
		{
			wheel.zPosition = Constants.steeredWheelZ
			addChild(wheel)
		}
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	// MARK: - Public API

	func castShadow(worldOffset: CGVector)
	{
		shadow.position = TruckPaint.localOffset(worldOffset, rotation: zRotation)
	}

	/// `sceneAngle` is the steer angle already converted to scene rotation, so the
	/// wheels turn the same way the rig does.
	func showSteer(sceneAngle: CGFloat)
	{
		for wheel in steeredWheels
		{
			wheel.zRotation = sceneAngle * Constants.steerExaggeration
		}
	}
}
