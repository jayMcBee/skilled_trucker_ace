//	==================================================
//	'SeededRandom.swift'
//	--------------------------------------------------
//	A seeded random source, so the lot looks the same on every launch and a screenshot
//	can be compared with the last one.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import Foundation

/// xorshift64*. Seeded, so cracks and scuffs land in the same place every launch and
/// a screenshot can be compared with the last one. A plain value with no shared
/// state, so it stays off the main actor and conforms like any other generator.
nonisolated struct SeededRandom: RandomNumberGenerator
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
