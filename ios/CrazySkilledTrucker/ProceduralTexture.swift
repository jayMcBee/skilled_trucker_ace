//	==================================================
//	'ProceduralTexture.swift'
//	--------------------------------------------------
//	Textures drawn at launch with Core Graphics, and textures loaded from the bundle.
//	One cache for both, so nothing is drawn or decoded twice.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit
import SpriteKit

struct ProceduralTexture
{
	// MARK: - Private Properties

	private static var cache: [String: SKTexture] = [:]

	private enum Constants
	{
		static let glowInnerAlpha: CGFloat = 1
		static let glowMidAlpha: CGFloat = 0.35
		static let glowMidStop: CGFloat = 0.3
		static let floorSubdirectory = "Floor"
		/// Clear in the middle, night at the corners. Stops are (position, alpha).
		static let vignetteStops: [(CGFloat, CGFloat)] = [(0, 0), (0.55, 0), (0.75, 0.25), (0.9, 0.55), (1, 0.85)]
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

	/// A texture from a file in the bundle, at the root or in the Floor folder, so both
	/// ways Xcode can copy a folder work. Nil when the file is not in the bundle.
	static func bundled(_ name: String, extension fileExtension: String) -> SKTexture?
	{
		let key = "file:\(name).\(fileExtension)"
		if let texture = cache[key]
		{
			return texture
		}
		let located = Bundle.main.url(forResource: name, withExtension: fileExtension)
			?? Bundle.main.url(forResource: name, withExtension: fileExtension,
							   subdirectory: Constants.floorSubdirectory)
		guard let url = located,
			  let image = UIImage(contentsOfFile: url.path)
		else { return nil }
		let texture = SKTexture(image: image)
		cache[key] = texture
		return texture
	}

	/// Black that thickens toward the edge, so the lot darkens into night at the screen
	/// edge. Stretched over the screen as an ellipse by whoever draws it.
	static func vignette(diameter: Int) -> SKTexture
	{
		let key = "vignette\(diameter)"
		if let texture = cache[key]
		{
			return texture
		}

		let size = CGSize(width: diameter, height: diameter)
		let image = UIGraphicsImageRenderer(size: size).image
		{ context in
			let colors = Constants.vignetteStops.map { UIColor.black.withAlphaComponent($0.1).cgColor } as CFArray
			let stops = Constants.vignetteStops.map { $0.0 }
			guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
											colors: colors, locations: stops)
			else { return }
			let centre = CGPoint(x: size.width / 2, y: size.height / 2)
			context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
												 endCenter: centre, endRadius: size.width / 2,
												 options: [.drawsAfterEndLocation])
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
