//	==================================================
//	'ThumbPad.swift'
//	--------------------------------------------------
//	One on-screen slider: a track, a centre tick and a knob. Vertical for drive,
//	horizontal for steering. It draws and it maps a touch to -1 ... 1; the scene
//	decides what that number means.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import SpriteKit

enum PadAxis
{
	case vertical
	case horizontal
}

final class ThumbPad: SKNode
{
	// MARK: - Public Properties

	let axis: PadAxis
	let length: CGFloat
	let thickness: CGFloat

	/// How far the knob centre can travel from the pad centre, along the axis.
	var reach: CGFloat
	{
		return length / 2 - Constants.knobRadius - Constants.knobInset
	}

	// MARK: - Private Properties

	private let knob = SKShapeNode(circleOfRadius: Constants.knobRadius)
	private let track: SKShapeNode

	private enum Constants
	{
		static let knobRadius: CGFloat = 26
		static let knobInset: CGFloat = 6
		static let cornerRadius: CGFloat = 22
		static let trackFill = SKColor(white: 1, alpha: 0.07)
		static let trackStroke = SKColor(white: 1, alpha: 0.16)
		static let tickColour = SKColor(white: 1, alpha: 0.30)
		static let tickLength: CGFloat = 14
		static let knobIdleFill = SKColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.85)
		static let knobActiveFill = SKColor(red: 0.64, green: 0.90, blue: 0.21, alpha: 0.95)
		static let knobStroke = SKColor(white: 1, alpha: 0.5)
		static let knobGlowWidth: CGFloat = 3
		static let knobZ: CGFloat = 1
		static let labelFont = "AvenirNext-Bold"
		static let labelSize: CGFloat = 12
		static let labelColour = SKColor(white: 1, alpha: 0.35)
		static let labelInset: CGFloat = 12
	}

	// MARK: - Init

	init(axis: PadAxis, length: CGFloat, thickness: CGFloat, endLabels: (String, String))
	{
		self.axis = axis
		self.length = length
		self.thickness = thickness

		let size = axis == .vertical ? CGSize(width: thickness, height: length)
			: CGSize(width: length, height: thickness)
		let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
		track = SKShapeNode(rect: rect, cornerRadius: Constants.cornerRadius)
		super.init()

		track.fillColor = Constants.trackFill
		track.strokeColor = Constants.trackStroke
		track.lineWidth = 1
		addChild(track)

		let tickPath = CGMutablePath()
		if axis == .vertical
		{
			tickPath.move(to: CGPoint(x: -Constants.tickLength / 2, y: 0))
			tickPath.addLine(to: CGPoint(x: Constants.tickLength / 2, y: 0))
		}
		else
		{
			tickPath.move(to: CGPoint(x: 0, y: -Constants.tickLength / 2))
			tickPath.addLine(to: CGPoint(x: 0, y: Constants.tickLength / 2))
		}
		let tick = SKShapeNode(path: tickPath)
		tick.strokeColor = Constants.tickColour
		tick.lineWidth = 1
		addChild(tick)

		let labelOffset = length / 2 - Constants.labelInset
		let positions = axis == .vertical
			? [CGPoint(x: 0, y: labelOffset - Constants.labelSize / 2), CGPoint(x: 0, y: -labelOffset - Constants.labelSize / 2)]
			: [CGPoint(x: -labelOffset, y: -Constants.labelSize / 2), CGPoint(x: labelOffset, y: -Constants.labelSize / 2)]
		for (text, position) in zip([endLabels.0, endLabels.1], positions)
		{
			let label = SKLabelNode(fontNamed: Constants.labelFont)
			label.text = text
			label.fontSize = Constants.labelSize
			label.fontColor = Constants.labelColour
			label.position = position
			addChild(label)
		}

		knob.fillColor = Constants.knobIdleFill
		knob.strokeColor = Constants.knobStroke
		knob.lineWidth = 1
		knob.glowWidth = Constants.knobGlowWidth
		knob.zPosition = Constants.knobZ
		addChild(knob)
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	// MARK: - Public API

	/// -1 ... 1 along the axis, for a point in the pad's parent space.
	func fraction(for point: CGPoint) -> CGFloat
	{
		let offset = axis == .vertical ? point.y - position.y : point.x - position.x
		return min(1, max(-1, offset / reach))
	}

	func showKnob(fraction: CGFloat, isActive: Bool)
	{
		let travel = min(1, max(-1, fraction)) * reach
		knob.position = axis == .vertical ? CGPoint(x: 0, y: travel) : CGPoint(x: travel, y: 0)
		knob.fillColor = isActive ? Constants.knobActiveFill : Constants.knobIdleFill
	}

	/// True when `point` is on the pad or in the generous margin around it, so a thumb
	/// that lands a little off the track still takes hold.
	func accepts(_ point: CGPoint, margin: CGFloat) -> Bool
	{
		let size = axis == .vertical ? CGSize(width: thickness, height: length)
			: CGSize(width: length, height: thickness)
		let hit = CGRect(x: position.x - size.width / 2 - margin, y: position.y - size.height / 2 - margin,
						 width: size.width + margin * 2, height: size.height + margin * 2)
		return hit.contains(point)
	}
}
