//	==================================================
//	'SoundEngine.swift'
//	--------------------------------------------------
//	Two interchangeable sound layers behind one small protocol, switched from the
//	options sheet. Both run the same idea: a diesel is a train of firing pulses through
//	the body's resonances and an exhaust, with a rattle that follows the pulses.
//
//	`SampledSoundEngine` plays loops that 'tools/make_sounds.py' rendered from that
//	model at three loads, crossfaded by load, each bent a little in pitch, through an
//	exhaust low-pass and a little room. `SynthesisedSoundEngine` runs the model itself in
//	a render block and needs no files.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import AVFoundation
import Synchronization

/// What the game tells the sound layer, once per frame.
struct SoundState
{
	/// |speed| over the top speed for the current direction, 0 ... 1.
	var speedFraction = 0.0
	/// The drive pad, -1 ... 1.
	var throttle = 0.0
	var isReversing = false
	/// The frame's length, for smoothing.
	var seconds = 1.0 / 60.0
	/// Multiplies every engine frequency: 1 is the model as rendered, less is a bigger engine.
	var pitch = 1.0
}

protocol SoundEngine: AnyObject
{
	func start()
	func stop()
	func update(_ state: SoundState)
	func playCrash()
	func playJam()
	func playBrakeHiss()
	func playParked()
}

/// Ambient: silenced by the mute switch and mixes with whatever music is playing,
/// which is what a casual game should do.
struct AudioSessionSetup
{
	static func activate()
	{
		let session = AVAudioSession.sharedInstance()
		try? session.setCategory(.ambient)
		try? session.setActive(true)
	}
}

/// How the game's speed and throttle become an engine's load, shared by both engines
/// so switching them compares the sound and not the mapping. Pure, and off the main
/// actor, because the render block asks it for the firing rate.
nonisolated struct EngineLoad
{
	static let idleRpm: Float = 650
	static let topRpm: Float = 1500
	static let cylinders: Float = 6

	/// 0 at idle, 1 flat out. Revs follow the throttle more than the speed: a truck
	/// pulling away is loud before it is fast.
	static func fraction(_ state: SoundState) -> Float
	{
		let speed = Float(state.speedFraction)
		let throttle = Float(abs(state.throttle))
		return min(1, max(0, Constants.speedWeight * speed + Constants.throttleWeight * throttle))
	}

	/// Rolling with the throttle off: road and wind, no firing.
	static func coasting(_ state: SoundState) -> Float
	{
		return Float(state.speedFraction) * (1 - Float(abs(state.throttle)))
	}

	static func rpm(atLoad load: Float) -> Float
	{
		return idleRpm + (topRpm - idleRpm) * load
	}

	/// Firings per second: four-stroke, so each cylinder fires once per two turns.
	static func firingRate(rpm: Float) -> Float
	{
		return rpm / 60 * cylinders / 2
	}

	private enum Constants
	{
		static let speedWeight: Float = 0.35
		static let throttleWeight: Float = 0.65
	}
}

/// Approaches a target over `seconds`, so a per-frame value never steps.
private func approached(_ value: Float, toward target: Float, over seconds: Float, frame: Float) -> Float
{
	return value + (target - value) * min(1, frame / seconds)
}

// MARK: - Sampled

/// One rendered loop with its own pitch bend and gain, sitting on one input of the
/// engine mixer.
private struct EngineLoop
{
	let player = AVAudioPlayerNode()
	let gain = AVAudioMixerNode()
	let varispeed = AVAudioUnitVarispeed()
	let buffer: AVAudioPCMBuffer
	/// The load the loop was rendered at, 0 ... 1, and the RPM that means.
	let centreLoad: Float
	let rpm: Float
}

final class SampledSoundEngine: SoundEngine
{
	// MARK: - Private Properties

	private let engine = AVAudioEngine()
	private var loops: [EngineLoop] = []
	private var coastLoop: EngineLoop?
	private let engineMixer = AVAudioMixerNode()
	private let exhaustFilter = AVAudioUnitEQ(numberOfBands: 1)
	private let roomMixer = AVAudioMixerNode()
	private let room = AVAudioUnitReverb()
	private let ambientPlayer = AVAudioPlayerNode()
	private let beeperPlayer = AVAudioPlayerNode()
	private let oneShotPlayer = AVAudioPlayerNode()
	private var ambientLoop: AVAudioPCMBuffer?
	private var beeperLoop: AVAudioPCMBuffer?
	private var oneShots: [String: AVAudioPCMBuffer] = [:]
	private var isGraphBuilt = false
	private var isRunning = false
	private var isBeeping = false
	private var exhaustCutoff = Constants.exhaustClosedHz

	private enum Constants
	{
		static let loopFiles: [(name: String, load: Float, rpm: Float)] = [
			("engine_idle", 0.15, 650), ("engine_low", 0.5, 1000), ("engine_high", 1.0, 1500)
		]
		static let coastFile = "engine_coast"
		static let ambientLoopFile = "ambient_loop"
		static let beeperLoopFile = "beeper_loop"
		static let crashFile = "crash"
		static let jamFile = "jam"
		static let brakeHissFiles = ["brake_hiss1", "brake_hiss2", "brake_hiss3"]
		static let brakeHissLevelRange: ClosedRange<Float> = 0.45 ... 0.8
		static let hornFile = "horn"
		static let fileExtension = "wav"
		static let soundsSubdirectory = "Sounds"

		/// Each loop is bent at most this far from the pitch it was rendered at; the
		/// crossfade does the rest.
		static let lowestRate: Float = 0.8
		static let highestRate: Float = 1.25
		/// Loud at idle already: a diesel is. Louder flat out.
		static let idleGain: Float = 0.55
		static let gainRiseWithLoad: Float = 0.45
		static let coastGain: Float = 0.6
		static let gainSmoothingSeconds: Float = 0.08
		static let rateSmoothingSeconds: Float = 0.15
		/// The exhaust opens with the throttle: muffled off-load, bright on it.
		static let exhaustClosedHz: Float = 700
		static let exhaustOpenHz: Float = 3500
		static let exhaustSmoothingSeconds: Float = 0.12
		static let exhaustBandwidth: Float = 0.5
		static let roomWetDryMix: Float = 12
		static let ambientVolume: Float = 0.45
		static let beeperVolume: Float = 0.5
		static let oneShotVolume: Float = 1.0
		static let engineVolume: Float = 0.9
	}

	// MARK: - Public API

	func start()
	{
		guard !isRunning
		else { return }

		AudioSessionSetup.activate()
		if !isGraphBuilt
		{
			buildGraph()
		}

		// Stopping a player clears what it had scheduled, so loops go back on every start.
		for loop in loops + (coastLoop.map { [$0] } ?? [])
		{
			loop.player.scheduleBuffer(loop.buffer, at: nil, options: .loops)
		}
		if let loop = ambientLoop
		{
			ambientPlayer.scheduleBuffer(loop, at: nil, options: .loops)
		}
		if let loop = beeperLoop
		{
			beeperPlayer.scheduleBuffer(loop, at: nil, options: .loops)
		}

		do
		{
			try engine.start()
		}
		catch
		{
			return
		}
		isRunning = true
		isBeeping = false
		for loop in loops + (coastLoop.map { [$0] } ?? [])
		{
			loop.player.play()
		}
		if ambientLoop != nil
		{
			ambientPlayer.play()
		}
		if !oneShots.isEmpty
		{
			oneShotPlayer.play()
		}
	}

	func stop()
	{
		guard isRunning
		else { return }
		for loop in loops + (coastLoop.map { [$0] } ?? [])
		{
			loop.player.stop()
		}
		for player in [ambientPlayer, beeperPlayer, oneShotPlayer]
		{
			player.stop()
		}
		engine.stop()
		isRunning = false
		isBeeping = false
	}

	/// Equal-power crossfade between the loops either side of the load, each bent
	/// toward the load's RPM within its range, all approached rather than stepped.
	func update(_ state: SoundState)
	{
		guard isRunning
		else { return }

		let frame = Float(state.seconds)
		let load = EngineLoad.fraction(state)
		let rpm = EngineLoad.rpm(atLoad: load)
		let overall = (Constants.idleGain + Constants.gainRiseWithLoad * load) * Constants.engineVolume

		for (index, loop) in loops.enumerated()
		{
			let below = index > 0 ? loops[index - 1].centreLoad : -Float.infinity
			let above = index < loops.count - 1 ? loops[index + 1].centreLoad : Float.infinity
			let tent: Float
			if load < loop.centreLoad
			{
				tent = below.isFinite ? max(0, 1 - (loop.centreLoad - load) / (loop.centreLoad - below)) : 1
			}
			else
			{
				tent = above.isFinite ? max(0, 1 - (load - loop.centreLoad) / (above - loop.centreLoad)) : 1
			}
			let target = sin(tent * Float.pi / 2) * overall
			loop.gain.outputVolume = approached(loop.gain.outputVolume, toward: target,
												over: Constants.gainSmoothingSeconds, frame: frame)
			let rate = min(Constants.highestRate, max(Constants.lowestRate, rpm / loop.rpm)) * Float(state.pitch)
			loop.varispeed.rate = approached(loop.varispeed.rate, toward: rate,
											 over: Constants.rateSmoothingSeconds, frame: frame)
		}

		if let coast = coastLoop
		{
			let target = EngineLoad.coasting(state) * Constants.coastGain
			coast.gain.outputVolume = approached(coast.gain.outputVolume, toward: target,
												 over: Constants.gainSmoothingSeconds, frame: frame)
		}

		let cutoff = Constants.exhaustClosedHz
			+ (Constants.exhaustOpenHz - Constants.exhaustClosedHz) * Float(abs(state.throttle))
		exhaustCutoff = approached(exhaustCutoff, toward: cutoff, over: Constants.exhaustSmoothingSeconds, frame: frame)
		exhaustFilter.bands[0].frequency = exhaustCutoff

		if beeperLoop != nil && state.isReversing != isBeeping
		{
			isBeeping = state.isReversing
			if isBeeping
			{
				beeperPlayer.play()
			}
			else
			{
				beeperPlayer.pause()
			}
		}
	}

	func playCrash()
	{
		playOneShot(Constants.crashFile)
	}

	func playJam()
	{
		playOneShot(Constants.jamFile)
	}

	/// A different puff each time, at a different level, so no two stops match.
	func playBrakeHiss()
	{
		guard let name = Constants.brakeHissFiles.randomElement()
		else { return }
		playOneShot(name, volume: Float.random(in: Constants.brakeHissLevelRange))
	}

	func playParked()
	{
		playOneShot(Constants.hornFile)
	}

	// MARK: - Private

	/// Attached and connected once. A missing file leaves that player unconnected and
	/// silent: the WAVs come from a script and can be absent.
	///
	///     loop player -> gain -> varispeed -\\
	///     loop player -> gain -> varispeed --> engine mixer -> exhaust low-pass -> room mixer -> reverb -> main
	///     one-shots ------------------------------------------------------------^
	///     ambient, beeper -> main
	private func buildGraph()
	{
		isGraphBuilt = true
		// The shared chain first: a loop cannot be connected to a mixer that is not
		// attached yet, and AVAudioEngine raises rather than waits.
		engine.attach(engineMixer)
		engine.attach(exhaustFilter)
		engine.attach(roomMixer)
		engine.attach(room)

		for entry in Constants.loopFiles
		{
			if let buffer = buffer(named: entry.name)
			{
				loops.append(attachLoop(buffer: buffer, load: entry.load, rpm: entry.rpm))
			}
		}
		if let buffer = buffer(named: Constants.coastFile)
		{
			coastLoop = attachLoop(buffer: buffer, load: 0, rpm: EngineLoad.idleRpm)
		}

		let format = loops.first?.buffer.format ?? coastLoop?.buffer.format
		exhaustFilter.bands[0].filterType = .lowPass
		exhaustFilter.bands[0].frequency = exhaustCutoff
		exhaustFilter.bands[0].bandwidth = Constants.exhaustBandwidth
		exhaustFilter.bands[0].bypass = false
		room.loadFactoryPreset(.largeRoom2)
		room.wetDryMix = Constants.roomWetDryMix
		engine.connect(engineMixer, to: exhaustFilter, format: format)
		engine.connect(exhaustFilter, to: roomMixer, format: format)
		engine.connect(roomMixer, to: room, format: format)
		engine.connect(room, to: engine.mainMixerNode, format: format)

		for player in [ambientPlayer, beeperPlayer, oneShotPlayer]
		{
			engine.attach(player)
		}
		ambientLoop = buffer(named: Constants.ambientLoopFile)
		if let loop = ambientLoop
		{
			engine.connect(ambientPlayer, to: engine.mainMixerNode, format: loop.format)
			ambientPlayer.volume = Constants.ambientVolume
		}
		beeperLoop = buffer(named: Constants.beeperLoopFile)
		if let loop = beeperLoop
		{
			engine.connect(beeperPlayer, to: engine.mainMixerNode, format: loop.format)
			beeperPlayer.volume = Constants.beeperVolume
		}
		for name in [Constants.crashFile, Constants.jamFile, Constants.hornFile] + Constants.brakeHissFiles
		{
			guard let sound = buffer(named: name)
			else { continue }
			if oneShots.isEmpty
			{
				engine.connect(oneShotPlayer, to: roomMixer, format: sound.format)
			}
			oneShots[name] = sound
		}
		oneShotPlayer.volume = Constants.oneShotVolume
	}

	private func attachLoop(buffer: AVAudioPCMBuffer, load: Float, rpm: Float) -> EngineLoop
	{
		let loop = EngineLoop(buffer: buffer, centreLoad: load, rpm: rpm)
		engine.attach(loop.player)
		engine.attach(loop.gain)
		engine.attach(loop.varispeed)
		engine.connect(loop.player, to: loop.gain, format: buffer.format)
		engine.connect(loop.gain, to: loop.varispeed, format: buffer.format)
		engine.connect(loop.varispeed, to: engineMixer, format: buffer.format)
		loop.gain.outputVolume = 0
		return loop
	}

	private func playOneShot(_ name: String, volume: Float = Constants.oneShotVolume)
	{
		guard isRunning,
			  let sound = oneShots[name]
		else { return }
		oneShotPlayer.volume = volume
		oneShotPlayer.scheduleBuffer(sound, at: nil, options: .interrupts)
	}

	/// Looks at the bundle root first, then in a `Sounds` folder, so both ways of adding
	/// the files in Xcode work.
	private func buffer(named name: String) -> AVAudioPCMBuffer?
	{
		let located = Bundle.main.url(forResource: name, withExtension: Constants.fileExtension)
			?? Bundle.main.url(forResource: name, withExtension: Constants.fileExtension,
							   subdirectory: Constants.soundsSubdirectory)
		guard let url = located,
			  let file = try? AVAudioFile(forReading: url),
			  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
											frameCapacity: AVAudioFrameCount(file.length))
		else { return nil }
		do
		{
			try file.read(into: buffer)
		}
		catch
		{
			return nil
		}
		return buffer
	}
}

// MARK: - Synthesised

/// A second-order filter section, direct form I. Coefficients from the RBJ cookbook.
nonisolated private struct Biquad
{
	var b0: Float = 1
	var b1: Float = 0
	var b2: Float = 0
	var a1: Float = 0
	var a2: Float = 0
	private var x1: Float = 0
	private var x2: Float = 0
	private var y1: Float = 0
	private var y2: Float = 0

	mutating func process(_ x0: Float) -> Float
	{
		let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
		return y0
	}

	mutating func setLowPass(frequency: Float, q: Float, sampleRate: Float)
	{
		let w = 2 * Float.pi * frequency / sampleRate
		let alpha = sin(w) / (2 * q)
		let c = cos(w)
		let a0 = 1 + alpha
		b0 = (1 - c) / 2 / a0
		b1 = (1 - c) / a0
		b2 = (1 - c) / 2 / a0
		a1 = -2 * c / a0
		a2 = (1 - alpha) / a0
	}

	mutating func setBandPass(frequency: Float, q: Float, sampleRate: Float)
	{
		let w = 2 * Float.pi * frequency / sampleRate
		let alpha = sin(w) / (2 * q)
		let c = cos(w)
		let a0 = 1 + alpha
		b0 = q * alpha / a0
		b1 = 0
		b2 = -q * alpha / a0
		a1 = -2 * c / a0
		a2 = (1 - alpha) / a0
	}
}

/// One firing: a decaying burst of body tone and noise. Two of these alternate, so a
/// pulse's tail survives the next firing.
nonisolated private struct FiringPulse
{
	var envelope: Float = 0
	var phase: Float = 0
}

/// Everything the render block reads and writes. The main thread stores the control
/// values once per frame and the audio thread loads them each buffer, through
/// atomics, so neither side ever waits. The one-shots are counters: the render block
/// starts an envelope each time a counter moves.
///
/// Off the main actor on purpose: `render` runs on the real-time audio thread.
nonisolated private final class SynthVoice: @unchecked Sendable
{
	// MARK: - Control values, stored by the main thread, loaded on the audio thread

	let load = Atomic<Float>(0)
	let pitch = Atomic<Float>(1)
	let coasting = Atomic<Float>(0)
	let throttle = Atomic<Float>(0)
	let isReversing = Atomic<Bool>(false)
	let crashTrigger = Atomic<Int>(0)
	let jamTrigger = Atomic<Int>(0)
	let hissTrigger = Atomic<Int>(0)
	let hornTrigger = Atomic<Int>(0)

	// MARK: - Render state, owned by the audio thread

	private let sampleRate: Float
	private var noiseState: UInt32 = 0x1234_5678
	private var cylinderGains: [Float] = []
	private var cylinderLags: [Float] = []

	private var smoothedLoad: Float = 0
	private var smoothedPitch: Float = 1
	private var smoothedCoast: Float = 0
	private var smoothedExhaust: Float = Constants.exhaustClosedHz
	private var firingPhase: Float = 0
	private var firingTarget: Float = 1
	private var cylinder = 0
	private var pulses = [FiringPulse(), FiringPulse()]
	private var nextPulse = 0
	private var bodyLow = Biquad()
	private var bodyMid = Biquad()
	private var bodyHigh = Biquad()
	private var exhaust = Biquad()
	private var coastFilter = Biquad()
	private var rattleEnvelope: Float = 0
	private var rattleLowPass: Float = 0
	private var whinePhase: Float = 0
	private var vibratoPhase: Float = 0
	private var humPhase: Float = 0

	private var beeperPhase: Float = 0
	private var beeperClock: Float = 0
	private var beeperGain: Float = 0
	private var crashEnvelope: Float = 0
	private var crashRing = [Float](repeating: 0, count: 3)
	private var crashRingPhases = [Float](repeating: 0, count: 3)
	private var jamEnvelope: Float = 0
	private var jamClick: Float = 0
	private var jamRingPhases = [Float](repeating: 0, count: 2)
	private var hissEnvelope: Float = 0
	private var hissSecondsLeft: Float = 0
	private var hissDecay: Float = 1
	private var hissGain: Float = 0
	private var hissFilter = Biquad()
	private var hornSecondsLeft: Float = 0
	private var hornGain: Float = 0
	private var hornPhases = [Float](repeating: 0, count: 3)
	private var seenCrashTrigger = 0
	private var seenJamTrigger = 0
	private var seenHissTrigger = 0
	private var seenHornTrigger = 0

	private enum Constants
	{
		static let cylinderCount = 6
		static let cylinderGainSpread: Float = 0.14
		static let cylinderLagSpread: Float = 0.025
		static let firingJitter: Float = 0.008
		static let pulseAmplitudeSpread: Float = 0.4
		static let pulseToneLevel: Float = 0.8
		static let pulseNoiseLevel: Float = 0.6
		static let pulseTauIdle: Float = 0.0045
		static let pulseTauDropWithLoad: Float = 0.002
		static let bodyToneIdleHz: Float = 130
		static let bodyToneRiseHz: Float = 80
		static let bodyLowHz: Float = 85
		static let bodyLowRiseHz: Float = 45
		static let bodyLowQ: Float = 2.5
		static let bodyMidHz: Float = 190
		static let bodyMidRiseHz: Float = 40
		static let bodyMidQ: Float = 4
		static let bodyMidLevel: Float = 0.8
		static let bodyHighHz: Float = 420
		static let bodyHighRiseHz: Float = 380
		static let bodyHighQ: Float = 5
		static let bodyHighIdleLevel: Float = 0.25
		static let bodyHighRise: Float = 0.6
		static let directLevel: Float = 0.35
		static let exhaustClosedHz: Float = 550
		static let exhaustOpenHz: Float = 3150
		static let exhaustQ: Float = 0.7
		static let rattleIdleLevel: Float = 0.10
		static let rattleRise: Float = 0.14
		static let rattleHighPassHz: Float = 2200
		static let rattleEnvelopeFollow: Float = 0.03
		static let rattleEnvelopeScale: Float = 2.5
		static let whineIdleHz: Float = 1500
		static let whineRiseHz: Float = 2300
		static let whineLevel: Float = 0.06
		static let vibratoHz: Float = 3.1
		static let vibratoDepth: Float = 0.6
		static let humLevel: Float = 0.25
		static let coastCutoffHz: Float = 900
		static let coastLevel: Float = 0.5
		static let loadSmoothing: Float = 0.00008
		static let pitchSmoothing: Float = 0.1
		static let masterGain: Float = 0.45
		static let idleGain: Float = 0.55
		static let gainRiseWithLoad: Float = 0.45
		static let outputDrive: Float = 1.15

		static let beeperFrequency: Float = 1220
		static let beeperPeriod: Float = 0.7
		static let beeperOnFraction: Float = 0.45
		static let beeperLevel: Float = 0.12
		static let beeperSmoothing: Float = 0.003
		static let crashDecaySeconds: Float = 0.10
		static let crashNoiseLevel: Float = 1.2
		static let crashRingHz: [Float] = [183, 311, 468]
		static let crashRingDecaySeconds: Float = 0.45
		static let crashRingLevel: Float = 0.6
		static let jamDecaySeconds: Float = 0.05
		static let jamRingHz: [Float] = [122, 197]
		static let jamRingDecaySeconds: Float = 0.14
		static let jamLevel: Float = 0.7
		static let hissSeconds: Float = 0.7
		static let hissAttackSeconds: Float = 0.015
		static let hissDecaySeconds: Float = 0.16
		static let hissDecaySpread: Float = 0.12
		static let hissHz: Float = 2600
		static let hissQ: Float = 0.9
		static let hissLevel: Float = 0.22
		static let hissLevelSpread: Float = 0.12
		static let hornSeconds: Float = 1.2
		static let hornReleaseSeconds: Float = 0.3
		static let hornHz: [Float] = [233, 311, 349]
		static let hornLevel: Float = 0.22
		static let hornSmoothing: Float = 0.001
		/// Below this an envelope is silent and its voice is skipped.
		static let envelopeFloor: Float = 0.001
		static let gainFloor: Float = 1e-6
		static let twoPi = Float.pi * 2
	}

	// MARK: - Init

	init(sampleRate: Float)
	{
		self.sampleRate = sampleRate
		for _ in 0 ..< Constants.cylinderCount
		{
			cylinderGains.append(1 + Constants.cylinderGainSpread * nextNoise())
			cylinderLags.append(Constants.cylinderLagSpread * nextNoise())
		}
		coastFilter.setLowPass(frequency: Constants.coastCutoffHz, q: 0.7, sampleRate: sampleRate)
		hissFilter.setBandPass(frequency: Constants.hissHz, q: Constants.hissQ, sampleRate: sampleRate)
		setBodyFilters(load: 0, pitch: 1)
	}

	// MARK: - Public API

	func render(into bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int)
	{
		let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
		guard let first = buffers.first,
			  let output = first.mData?.assumingMemoryBound(to: Float.self)
		else
		{
			return
		}

		let targetLoad = load.load(ordering: .relaxed)
		let targetPitch = pitch.load(ordering: .relaxed)
		let targetCoast = coasting.load(ordering: .relaxed)
		let throttleLevel = abs(throttle.load(ordering: .relaxed))
		let reversing = isReversing.load(ordering: .relaxed)
		latchTriggers()

		// Filters follow the load once per buffer: cheap, and a buffer is short.
		smoothedPitch += (targetPitch - smoothedPitch) * Constants.pitchSmoothing
		setBodyFilters(load: smoothedLoad, pitch: smoothedPitch)
		let targetExhaust = Constants.exhaustClosedHz + (Constants.exhaustOpenHz - Constants.exhaustClosedHz) * throttleLevel
		smoothedExhaust += (targetExhaust - smoothedExhaust) * 0.2
		exhaust.setLowPass(frequency: smoothedExhaust, q: Constants.exhaustQ, sampleRate: sampleRate)

		let secondsPerSample = 1 / sampleRate
		let crashDecay = exp(-1 / (Constants.crashDecaySeconds * sampleRate))
		let crashRingDecay = exp(-1 / (Constants.crashRingDecaySeconds * sampleRate))
		let jamDecay = exp(-1 / (Constants.jamDecaySeconds * sampleRate))
		let jamRingDecay = exp(-1 / (Constants.jamRingDecaySeconds * sampleRate))

		for frame in 0 ..< frameCount
		{
			smoothedLoad += (targetLoad - smoothedLoad) * Constants.loadSmoothing
			smoothedCoast += (targetCoast - smoothedCoast) * Constants.loadSmoothing
			var sample = engineSample(load: smoothedLoad, pitch: smoothedPitch, secondsPerSample: secondsPerSample)
			sample += coastFilter.process(nextNoise()) * smoothedCoast * Constants.coastLevel

			// The beeper is a gated tone. The gate is smoothed so it never clicks.
			beeperClock += secondsPerSample
			if beeperClock > Constants.beeperPeriod
			{
				beeperClock -= Constants.beeperPeriod
			}
			let beeperWanted: Float = reversing && beeperClock < Constants.beeperPeriod * Constants.beeperOnFraction
				? Constants.beeperLevel : 0
			beeperGain += (beeperWanted - beeperGain) * Constants.beeperSmoothing
			if beeperWanted == 0 && beeperGain < Constants.gainFloor
			{
				beeperGain = 0
			}
			beeperPhase = wrapped(beeperPhase + Constants.twoPi * Constants.beeperFrequency * secondsPerSample)
			sample += sin(beeperPhase) * beeperGain

			if crashEnvelope > Constants.envelopeFloor
			{
				sample += nextNoise() * crashEnvelope * Constants.crashNoiseLevel
				crashEnvelope *= crashDecay
			}
			for index in crashRing.indices where crashRing[index] > Constants.envelopeFloor
			{
				crashRingPhases[index] = wrapped(crashRingPhases[index]
					+ Constants.twoPi * Constants.crashRingHz[index] * secondsPerSample)
				sample += sin(crashRingPhases[index]) * crashRing[index] * Constants.crashRingLevel / Float(index + 1)
				crashRing[index] *= crashRingDecay
			}

			if jamEnvelope > Constants.envelopeFloor
			{
				// A short click of noise on top of two ringing partials that outlast it.
				var thud = nextNoise() * jamClick
				for index in jamRingPhases.indices
				{
					jamRingPhases[index] = wrapped(jamRingPhases[index]
						+ Constants.twoPi * Constants.jamRingHz[index] * secondsPerSample)
					thud += sin(jamRingPhases[index]) * jamEnvelope / Float(index + 1)
				}
				sample += thud * Constants.jamLevel
				jamEnvelope *= jamRingDecay
				jamClick *= jamDecay
			}

			if hissSecondsLeft > 0
			{
				hissSecondsLeft -= secondsPerSample
				let elapsed = Constants.hissSeconds - hissSecondsLeft
				hissEnvelope = elapsed < Constants.hissAttackSeconds
					? elapsed / Constants.hissAttackSeconds : hissEnvelope * hissDecay
				sample += hissFilter.process(nextNoise()) * hissEnvelope * hissGain
			}

			let hornWanted: Float = hornSecondsLeft > Constants.hornReleaseSeconds ? Constants.hornLevel : 0
			hornGain += (hornWanted - hornGain) * Constants.hornSmoothing
			if hornWanted == 0 && hornGain < Constants.gainFloor
			{
				hornGain = 0
			}
			if hornSecondsLeft > 0
			{
				hornSecondsLeft -= secondsPerSample
				var chord: Float = 0
				for index in hornPhases.indices
				{
					hornPhases[index] = wrapped(hornPhases[index] + Constants.twoPi * Constants.hornHz[index] * secondsPerSample)
					chord += sin(hornPhases[index]) + 0.5 * sin(2 * hornPhases[index]) + 0.3 * sin(3 * hornPhases[index])
				}
				sample += chord * hornGain
			}

			output[frame] = tanh(sample * Constants.outputDrive)
		}

		for extra in buffers.dropFirst()
		{
			if let channel = extra.mData?.assumingMemoryBound(to: Float.self)
			{
				channel.update(from: output, count: frameCount)
			}
		}
	}

	// MARK: - Private

	/// One sample of the diesel: fire the next cylinder when its moment comes, sum the
	/// live pulses, pass them through the body and the exhaust, add rattle, whine and hum.
	private func engineSample(load: Float, pitch: Float, secondsPerSample: Float) -> Float
	{
		let firingRate = EngineLoad.firingRate(rpm: EngineLoad.rpm(atLoad: load)) * pitch
		firingPhase += firingRate * secondsPerSample
		if firingPhase >= firingTarget
		{
			firingPhase -= firingTarget
			let amplitude = cylinderGains[cylinder] * (1 - Constants.pulseAmplitudeSpread / 2 + Constants.pulseAmplitudeSpread * unitNoise())
			pulses[nextPulse] = FiringPulse(envelope: amplitude, phase: 0)
			nextPulse = (nextPulse + 1) % pulses.count
			cylinder = (cylinder + 1) % Constants.cylinderCount
			firingTarget = 1 + cylinderLags[cylinder] + Constants.firingJitter * nextNoise()
		}

		let tau = Constants.pulseTauIdle - Constants.pulseTauDropWithLoad * load
		let pulseDecay = exp(-secondsPerSample / tau)
		let bodyTone = (Constants.bodyToneIdleHz + Constants.bodyToneRiseHz * load) * pitch
		var excitation: Float = 0
		for index in pulses.indices where pulses[index].envelope > Constants.envelopeFloor
		{
			pulses[index].phase = wrapped(pulses[index].phase + Constants.twoPi * bodyTone * secondsPerSample)
			excitation += pulses[index].envelope
				* (Constants.pulseToneLevel * sin(pulses[index].phase) + Constants.pulseNoiseLevel * nextNoise())
			pulses[index].envelope *= pulseDecay
		}

		var tone = bodyLow.process(excitation)
			+ bodyMid.process(excitation) * Constants.bodyMidLevel
			+ bodyHigh.process(excitation) * (Constants.bodyHighIdleLevel + Constants.bodyHighRise * load)
			+ excitation * Constants.directLevel
		tone = exhaust.process(tone)

		rattleEnvelope += (abs(excitation) - rattleEnvelope) * Constants.rattleEnvelopeFollow
		let white = nextNoise()
		rattleLowPass += (white - rattleLowPass) * (Constants.twoPi * Constants.rattleHighPassHz * secondsPerSample)
		let rattle = (white - rattleLowPass) * rattleEnvelope * Constants.rattleEnvelopeScale
			* (Constants.rattleIdleLevel + Constants.rattleRise * load)

		vibratoPhase = wrapped(vibratoPhase + Constants.twoPi * Constants.vibratoHz * secondsPerSample)
		let whineHz = Constants.whineIdleHz + Constants.whineRiseHz * load
		whinePhase = wrapped(whinePhase + Constants.twoPi * whineHz * secondsPerSample)
		let whine = sin(whinePhase + Constants.vibratoDepth * sin(vibratoPhase)) * Constants.whineLevel * load * load

		humPhase = wrapped(humPhase + Constants.twoPi * firingRate * secondsPerSample)
		let hum = sin(humPhase) * Constants.humLevel * (1 - load)

		let gain = (Constants.idleGain + Constants.gainRiseWithLoad * load) * Constants.masterGain
		return (tone + rattle + whine + hum) * gain
	}

	private func setBodyFilters(load: Float, pitch: Float)
	{
		bodyLow.setBandPass(frequency: (Constants.bodyLowHz + Constants.bodyLowRiseHz * load) * pitch,
							q: Constants.bodyLowQ, sampleRate: sampleRate)
		bodyMid.setBandPass(frequency: (Constants.bodyMidHz + Constants.bodyMidRiseHz * load) * pitch,
							q: Constants.bodyMidQ, sampleRate: sampleRate)
		bodyHigh.setBandPass(frequency: (Constants.bodyHighHz + Constants.bodyHighRiseHz * load) * pitch,
							 q: Constants.bodyHighQ, sampleRate: sampleRate)
	}

	private func latchTriggers()
	{
		let crashCount = crashTrigger.load(ordering: .relaxed)
		if crashCount != seenCrashTrigger
		{
			seenCrashTrigger = crashCount
			crashEnvelope = 1
			for index in crashRing.indices
			{
				crashRing[index] = 1
				crashRingPhases[index] = 0
			}
		}
		let jamCount = jamTrigger.load(ordering: .relaxed)
		if jamCount != seenJamTrigger
		{
			seenJamTrigger = jamCount
			jamEnvelope = 1
			jamClick = 1
			for index in jamRingPhases.indices
			{
				jamRingPhases[index] = 0
			}
		}
		let hissCount = hissTrigger.load(ordering: .relaxed)
		if hissCount != seenHissTrigger
		{
			seenHissTrigger = hissCount
			hissSecondsLeft = Constants.hissSeconds
			hissEnvelope = 0
			// A different puff each time: length and level drawn fresh on every stop.
			let decaySeconds = Constants.hissDecaySeconds + Constants.hissDecaySpread * unitNoise()
			hissDecay = exp(-1 / (decaySeconds * sampleRate))
			hissGain = Constants.hissLevel + Constants.hissLevelSpread * unitNoise()
		}
		let hornCount = hornTrigger.load(ordering: .relaxed)
		if hornCount != seenHornTrigger
		{
			seenHornTrigger = hornCount
			hornSecondsLeft = Constants.hornSeconds
			for index in hornPhases.indices
			{
				hornPhases[index] = 0
			}
		}
	}

	private func wrapped(_ phase: Float) -> Float
	{
		return phase > Constants.twoPi ? phase - Constants.twoPi : phase
	}

	/// xorshift32, mapped to -1 ... 1. No allocation, no locks: safe on the audio thread.
	private func nextNoise() -> Float
	{
		noiseState ^= noiseState << 13
		noiseState ^= noiseState >> 17
		noiseState ^= noiseState << 5
		return Float(noiseState) / Float(UInt32.max) * 2 - 1
	}

	private func unitNoise() -> Float
	{
		return (nextNoise() + 1) / 2
	}
}

final class SynthesisedSoundEngine: SoundEngine
{
	// MARK: - Private Properties

	private let engine = AVAudioEngine()
	private let voice = SynthVoice(sampleRate: Float(Constants.sampleRate))
	private var sourceNode: AVAudioSourceNode?

	private enum Constants
	{
		static let sampleRate = 44100.0
		static let outputVolume: Float = 0.8
	}

	// MARK: - Public API

	func start()
	{
		guard sourceNode == nil,
			  let format = AVAudioFormat(standardFormatWithSampleRate: Constants.sampleRate, channels: 1)
		else { return }

		AudioSessionSetup.activate()

		// Sendable and off the main actor: this block runs on the audio thread.
		let voice = self.voice
		let node = AVAudioSourceNode(format: format)
		{ @Sendable (_, _, frameCount, audioBufferList) -> OSStatus in
			voice.render(into: audioBufferList, frameCount: Int(frameCount))
			return noErr
		}
		engine.attach(node)
		engine.connect(node, to: engine.mainMixerNode, format: format)
		engine.mainMixerNode.outputVolume = Constants.outputVolume
		sourceNode = node
		try? engine.start()
	}

	func stop()
	{
		engine.stop()
		if let node = sourceNode
		{
			engine.detach(node)
		}
		sourceNode = nil
	}

	func update(_ state: SoundState)
	{
		voice.load.store(EngineLoad.fraction(state), ordering: .relaxed)
		voice.pitch.store(Float(state.pitch), ordering: .relaxed)
		voice.coasting.store(EngineLoad.coasting(state), ordering: .relaxed)
		voice.throttle.store(Float(state.throttle), ordering: .relaxed)
		voice.isReversing.store(state.isReversing, ordering: .relaxed)
	}

	func playCrash()
	{
		voice.crashTrigger.wrappingAdd(1, ordering: .relaxed)
	}

	func playJam()
	{
		voice.jamTrigger.wrappingAdd(1, ordering: .relaxed)
	}

	func playBrakeHiss()
	{
		voice.hissTrigger.wrappingAdd(1, ordering: .relaxed)
	}

	func playParked()
	{
		voice.hornTrigger.wrappingAdd(1, ordering: .relaxed)
	}
}
