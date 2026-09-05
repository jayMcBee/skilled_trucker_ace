//	==================================================
//	'GameOptions.swift'
//	--------------------------------------------------
//	Everything the options sheet can change, stored in UserDefaults so it survives a
//	relaunch. Every default matches the web build.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import Foundation

enum SoundChoice: Int
{
	case off = 0
	case synthesised = 1
	case sampled = 2
}

struct GameOptions
{
	// MARK: - Public Properties

	static var presetIndex: Int
	{
		get { return clampedIndex(store.integer(forKey: Constants.presetIndexKey)) }
		set { store.set(clampedIndex(newValue), forKey: Constants.presetIndexKey) }
	}

	static var forwardFactor: Double
	{
		get { return double(forKey: Constants.forwardFactorKey, fallback: 1) }
		set { store.set(newValue, forKey: Constants.forwardFactorKey) }
	}

	static var reverseFactor: Double
	{
		get { return double(forKey: Constants.reverseFactorKey, fallback: 1) }
		set { store.set(newValue, forKey: Constants.reverseFactorKey) }
	}

	static var jackknifeEndsRun: Bool
	{
		get { return bool(forKey: Constants.jackknifeEndsRunKey, fallback: false) }
		set { store.set(newValue, forKey: Constants.jackknifeEndsRunKey) }
	}

	/// Drive pad on the right and steering on the left, for players who want it that way.
	static var swapPads: Bool
	{
		get { return bool(forKey: Constants.swapPadsKey, fallback: false) }
		set { store.set(newValue, forKey: Constants.swapPadsKey) }
	}

	static var particlesEnabled: Bool
	{
		get { return bool(forKey: Constants.particlesEnabledKey, fallback: true) }
		set { store.set(newValue, forKey: Constants.particlesEnabledKey) }
	}

	/// How big the player's steered wheels are drawn, as a multiple of the baked tyre.
	/// A dial while the look is being found.
	static var steeredWheelScale: Double
	{
		get
		{
			let stored = double(forKey: Constants.steeredWheelScaleKey, fallback: Constants.defaultSteeredWheelScale)
			return clamped(stored, lowestSteeredWheelScale, highestSteeredWheelScale)
		}
		set { store.set(newValue, forKey: Constants.steeredWheelScaleKey) }
	}

	static let lowestSteeredWheelScale = 1.5
	static let highestSteeredWheelScale = 2.2

	/// The lane runs left to right across the landscape screen, which fits it far
	/// better than the tall strip the web canvas was.
	static var lotAcrossScreen: Bool
	{
		get { return bool(forKey: Constants.lotAcrossScreenKey, fallback: true) }
		set { store.set(newValue, forKey: Constants.lotAcrossScreenKey) }
	}

	static var lotEdge: LotEdge
	{
		get { return LotEdge(rawValue: store.integer(forKey: Constants.lotEdgeKey)) ?? .open }
		set { store.set(newValue.rawValue, forKey: Constants.lotEdgeKey) }
	}

	static var soundChoice: SoundChoice
	{
		get
		{
			if store.object(forKey: Constants.soundChoiceKey) == nil
			{
				return .synthesised
			}
			return SoundChoice(rawValue: store.integer(forKey: Constants.soundChoiceKey)) ?? .synthesised
		}
		set { store.set(newValue.rawValue, forKey: Constants.soundChoiceKey) }
	}

	static var preset: Preset
	{
		return Preset.all[presetIndex]
	}

	static var tuning: Tuning
	{
		return Tuning(forwardFactor: forwardFactor, reverseFactor: reverseFactor,
					  jackknifeEndsRun: jackknifeEndsRun)
	}

	// MARK: - Private Properties

	private static let store = UserDefaults.standard

	private enum Constants
	{
		static let presetIndexKey = "presetIndex"
		static let forwardFactorKey = "forwardFactor"
		static let reverseFactorKey = "reverseFactor"
		static let jackknifeEndsRunKey = "jackknifeEndsRun"
		static let swapPadsKey = "swapPads"
		static let particlesEnabledKey = "particlesEnabled"
		static let soundChoiceKey = "soundChoice"
		static let lotEdgeKey = "lotEdge"
		static let lotAcrossScreenKey = "lotAcrossScreen"
		static let steeredWheelScaleKey = "steeredWheelScale"
		/// The baked tyre read as tiny on the player's cab. Found by play.
		static let defaultSteeredWheelScale = 1.8
	}

	// MARK: - Private

	private static func clampedIndex(_ index: Int) -> Int
	{
		return min(Preset.all.count - 1, max(0, index))
	}

	/// UserDefaults reads a missing number as zero, which is a valid dial value, so
	/// absence has to be checked before the value is trusted.
	private static func double(forKey key: String, fallback: Double) -> Double
	{
		return store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
	}

	private static func bool(forKey key: String, fallback: Bool) -> Bool
	{
		return store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
	}
}
