//	==================================================
//	'Procedural.swift'
//	--------------------------------------------------
//	Textures drawn at launch with Core Graphics, and a seeded random source, so the
//	lot needs no image assets and looks the same on every launch.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit
import SpriteKit

/// xorshift64*. Seeded, so cracks and scuffs land in the same place every launch and
/// a screenshot can be compared with the last one.
struct SeededRandom: RandomNumberGenerator
{
	private var state: UInt64

	init(seed: UInt64)
	{
		state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
	}

	mutating func next() -> UInt64
	{
		state ^= state >> 12
		state ^= state << 25
		state ^= state >> 27
		return state &* 0x2545_F491_4F6C_DD1D
	}
}

struct ProceduralTexture
{
	// MARK: - Private Properties

	private static var cache: [String: SKTexture] = [:]

	private enum Constants
	{
		static let glowInnerAlpha: CGFloat = 1
		static let glowMidAlpha: CGFloat = 0.35
		static let glowMidStop: CGFloat = 0.3
	}

	// MARK: - Public API

	/// White disc fading to transparent at the rim: the particle and light source shape.
	static func softCircle(diameter: Int) -> SKTexture
	{
		let key = "softCircle\(diameter)"
		if let texture = cache[key]
		{
			return texture
		}

		let size = CGSize(width: diameter, height: diameter)
		let image = UIGraphicsImageRenderer(size: size).image
		{ context in
			let colors = [UIColor.white.withAlphaComponent(Constants.glowInnerAlpha).cgColor,
						  UIColor.white.withAlphaComponent(Constants.glowMidAlpha).cgColor,
						  UIColor.white.withAlphaComponent(0).cgColor] as CFArray
			let stops: [CGFloat] = [0, Constants.glowMidStop, 1]
			guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
											colors: colors, locations: stops)
			else { return }
			let centre = CGPoint(x: size.width / 2, y: size.height / 2)
			context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
												 endCenter: centre, endRadius: size.width / 2,
												 options: [])
		}
		let texture = SKTexture(image: image)
		cache[key] = texture
		return texture
	}

	/// A plain white square, for debris and sparks that should have hard edges.
	static func square(side: Int) -> SKTexture
	{
		let key = "square\(side)"
		if let texture = cache[key]
		{
			return texture
		}

		let size = CGSize(width: side, height: side)
		let image = UIGraphicsImageRenderer(size: size).image
		{ context in
			UIColor.white.setFill()
			context.fill(CGRect(origin: .zero, size: size))
		}
		let texture = SKTexture(image: image)
		cache[key] = texture
		return texture
	}
}
