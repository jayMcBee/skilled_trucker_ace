//	==================================================
//	'TruckArt.swift'
//	--------------------------------------------------
//	The trailer and the cab as node trees, drawn in local units where +x is forward.
//	Both are built from the same TruckDimensions the collision boxes use, so the
//	picture and the shape it collides as cannot drift apart. Nothing here is drawn
//	outside the collision box: an obstacle wider than its own picture is invisible
//	by construction, and one narrower than it feels cheated.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import SpriteKit

/// Colours and sizes both node classes share.
private enum TruckPalette
{
	static let shadowColour = SKColor(white: 0, alpha: 0.55)
	static let outlineColour = SKColor(white: 0, alpha: 0.35)
	static let outlineWidth: CGFloat = 0.8
	static let tyreColour = SKColor(red: 0.01, green: 0.02, blue: 0.09, alpha: 1)
	static let tyreCoreColour = SKColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1)
	static let tyreCornerRadius: CGFloat = 1
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
		static let ribSpacingFraction = 0.077
		static let ribInsetFraction = 0.06
		static let ribWidthFraction = 0.04
		static let ribHeightFraction = 0.86
		static let ribColour = SKColor(white: 0, alpha: 0.10)
		static let roofEdgeFraction = 0.07
		static let roofEdgeColour = SKColor(white: 1, alpha: 0.35)
		static let lampWidthFraction = 0.05
		static let lampHeightFraction = 0.19
		static let lampInsetFraction = 0.05
		static let lampGlowDiameterFraction = 0.55
		static let playerLampGlowDiameterFraction = 0.9
		static let lampIdleAlpha: CGFloat = 0.35
		static let lampBrakeAlpha: CGFloat = 0.9
		static let lampReverseAlpha: CGFloat = 0.7
		static let axleFractions = [0.10, 0.19]
		static let tyreLengthFraction = 0.06
		static let tyreWidthFraction = 0.14
		static let tyreInsetFraction = 0.08
	}

	// MARK: - Init

	init(dimensions: TruckDimensions, bodyColour: SKColor, isPlayer: Bool)
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

		let body = TruckPaint.rectangle(centre: .zero, size: size, fill: bodyColour)
		body.strokeColor = TruckPalette.outlineColour
		body.lineWidth = TruckPalette.outlineWidth
		addChild(body)

		let ribWidth = max(1, width * Constants.ribWidthFraction)
		var ribX = -length / 2 + length * Constants.ribInsetFraction
		while ribX < length / 2 - length * Constants.ribInsetFraction
		{
			let rib = TruckPaint.rectangle(centre: CGPoint(x: ribX, y: 0),
										   size: CGSize(width: ribWidth, height: width * Constants.ribHeightFraction),
										   fill: Constants.ribColour)
			addChild(rib)
			ribX += length * Constants.ribSpacingFraction
		}

		let edgeHeight = width * Constants.roofEdgeFraction
		for side in TruckPalette.sides
		{
			let edge = TruckPaint.rectangle(centre: CGPoint(x: 0, y: side * (width / 2 - edgeHeight / 2)),
											size: CGSize(width: length, height: edgeHeight),
											fill: Constants.roofEdgeColour)
			addChild(edge)
		}

		for axle in Constants.axleFractions
		{
			for side in TruckPalette.sides
			{
				let tyre = TruckPaint.rectangle(
					centre: CGPoint(x: -length / 2 + length * axle,
									y: side * (width / 2 - width * Constants.tyreInsetFraction)),
					size: CGSize(width: length * Constants.tyreLengthFraction,
								 height: width * Constants.tyreWidthFraction),
					fill: TruckPalette.tyreColour, corner: TruckPalette.tyreCornerRadius)
				addChild(tyre)
			}
		}

		let lampSize = CGSize(width: max(1, width * Constants.lampWidthFraction),
							  height: width * Constants.lampHeightFraction)
		let lampY = width / 2 - width * Constants.lampInsetFraction - lampSize.height / 2
		for (side, glow) in zip(TruckPalette.sides, [leftLamp, rightLamp])
		{
			let lampCentre = CGPoint(x: -length / 2 + lampSize.width / 2, y: side * lampY)
			addChild(TruckPaint.rectangle(centre: lampCentre, size: lampSize, fill: TruckPalette.lampRedColour))
			glow.position = lampCentre
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

	/// Where the exhaust stack is, in local units, for the smoke emitter.
	let exhaustAnchor: CGPoint

	// MARK: - Private Properties

	private let shadow: SKShapeNode
	private let steeredWheels: [SKNode]

	private enum Constants
	{
		static let windscreenColour = SKColor(red: 0.01, green: 0.02, blue: 0.09, alpha: 1)
		static let windscreenStartFraction = 0.18
		static let windscreenLengthFraction = 0.18
		static let windscreenWidthFraction = 0.84
		static let bonnetHighlightColour = SKColor(white: 1, alpha: 0.16)
		static let roofShadeColour = SKColor(white: 0, alpha: 0.10)
		static let mirrorColour = SKColor(white: 0.85, alpha: 1)
		static let mirrorLengthFraction = 0.08
		static let mirrorWidthFraction = 0.06
		static let wheelLengthFraction = 0.40
		static let wheelWidthFraction = 0.17
		static let wheelMinimumLength: CGFloat = 6
		static let wheelMinimumWidth: CGFloat = 2.5
		static let rearAxleFraction = -0.34
		static let frontAxleFraction = 0.34
		static let wheelTrackFraction = 0.40
		static let rearWheelLengthFraction = 0.7
		static let casingPadding: CGFloat = 1
		static let exhaustXFraction = -0.30
		static let exhaustYFraction = -0.44
		static let roofCentreFraction = -0.2
		/// Above every body detail, so the readout is never covered.
		static let steeredWheelZ: CGFloat = 2
		static let roofLengthFraction = 0.5
		static let bodyDetailWidthFraction = 0.9
		static let bodyCornerRadius: CGFloat = 1.5
		/// Full lock is only 24 degrees, which on a 13px wheel moves the tip under 3px.
		/// Drawn 1.6x, it reads. The player needs direction and size, not a protractor.
		static let steerExaggeration: CGFloat = 1.6
	}

	// MARK: - Init

	/// The player's steered wheels are the steering readout, so they are drawn oversized
	/// and proud of the body, 2px past the collision box: a picture bigger than its box
	/// is forgiving. A parked cab gets fixed wheels inside its box instead, because a
	/// parked picture bigger than its box is a lie the player pays for.
	init(dimensions: TruckDimensions, bodyColour: SKColor, isPlayer: Bool)
	{
		let length = CGFloat(dimensions.cabLength)
		let width = CGFloat(dimensions.cabWidth)
		let size = CGSize(width: length, height: width)
		shadow = TruckPaint.shadow(size: size)
		exhaustAnchor = CGPoint(x: length * Constants.exhaustXFraction, y: width * Constants.exhaustYFraction)

		let wheelLength = max(Constants.wheelMinimumLength, length * Constants.wheelLengthFraction)
		let wheelWidth = max(Constants.wheelMinimumWidth, width * Constants.wheelWidthFraction)
		var wheels: [SKNode] = []
		if isPlayer
		{
			for side in TruckPalette.sides
			{
				let wheel = SKNode()
				wheel.position = CGPoint(x: length * Constants.frontAxleFraction,
										 y: side * width * Constants.wheelTrackFraction)
				let casing = TruckPaint.rectangle(
					centre: .zero,
					size: CGSize(width: wheelLength + Constants.casingPadding * 2,
								 height: wheelWidth + Constants.casingPadding * 2),
					fill: TruckPalette.tyreColour, corner: TruckPalette.tyreCornerRadius)
				let core = TruckPaint.rectangle(centre: .zero, size: CGSize(width: wheelLength, height: wheelWidth),
												fill: TruckPalette.tyreCoreColour)
				wheel.addChild(casing)
				wheel.addChild(core)
				wheels.append(wheel)
			}
		}
		steeredWheels = wheels
		super.init()

		addChild(shadow)

		let body = TruckPaint.rectangle(centre: .zero, size: size, fill: bodyColour, corner: Constants.bodyCornerRadius)
		body.strokeColor = TruckPalette.outlineColour
		body.lineWidth = TruckPalette.outlineWidth
		addChild(body)

		let detailWidth = width * Constants.bodyDetailWidthFraction
		let roof = TruckPaint.rectangle(centre: CGPoint(x: length * Constants.roofCentreFraction, y: 0),
										size: CGSize(width: length * Constants.roofLengthFraction, height: detailWidth),
										fill: Constants.roofShadeColour)
		addChild(roof)

		let bonnetLength = length / 2 - length * (Constants.windscreenStartFraction + Constants.windscreenLengthFraction)
		let bonnet = TruckPaint.rectangle(centre: CGPoint(x: length / 2 - bonnetLength / 2, y: 0),
										  size: CGSize(width: bonnetLength, height: detailWidth),
										  fill: Constants.bonnetHighlightColour)
		addChild(bonnet)

		let windscreenX = length * (Constants.windscreenStartFraction + Constants.windscreenLengthFraction / 2)
		let windscreen = TruckPaint.rectangle(centre: CGPoint(x: windscreenX, y: 0),
											  size: CGSize(width: length * Constants.windscreenLengthFraction,
														   height: width * Constants.windscreenWidthFraction),
											  fill: Constants.windscreenColour)
		addChild(windscreen)

		for side in TruckPalette.sides
		{
			let mirror = TruckPaint.rectangle(
				centre: CGPoint(x: windscreenX, y: side * (width / 2 - width * Constants.mirrorWidthFraction / 2)),
				size: CGSize(width: length * Constants.mirrorLengthFraction, height: width * Constants.mirrorWidthFraction),
				fill: Constants.mirrorColour)
			addChild(mirror)

			let fixedAxles = isPlayer ? [Constants.rearAxleFraction] : [Constants.rearAxleFraction, Constants.frontAxleFraction]
			for axle in fixedAxles
			{
				let wheel = TruckPaint.rectangle(
					centre: CGPoint(x: length * axle, y: side * width * Constants.wheelTrackFraction),
					size: CGSize(width: wheelLength * Constants.rearWheelLengthFraction, height: wheelWidth),
					fill: TruckPalette.tyreColour, corner: TruckPalette.tyreCornerRadius)
				addChild(wheel)
			}
		}

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
