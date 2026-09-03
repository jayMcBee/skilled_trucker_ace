//	==================================================
//	'SoundEngine.swift'
//	--------------------------------------------------
//	Two interchangeable sound layers behind one small protocol, switched from the
//	options sheet. `SynthesisedSoundEngine` makes every sound in a render block and
//	needs no files. `SampledSoundEngine` plays the WAV loops that 'tools/make_sounds.py'
//	generates, bent in pitch with a varispeed unit. Both run on AVAudioEngine.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import AVFoundation

/// What the game tells the sound layer, once per frame.
struct SoundState
{
	/// |speed| over the top speed for the current direction, 0 ... 1.
	var speedFraction = 0.0
	/// The drive pad, -1 ... 1.
	var throttle = 0.0
	var isReversing = false
}

protocol SoundEngine: AnyObject
{
	func start()
	func stop()
	func update(_ state: SoundState)
	func playCrash()
	func playJam()
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

// MARK: - Synthesised

/// Everything the render block reads and writes. The main thread writes the control
/// values once per frame and the audio thread reads them each buffer.
/// ponytail: plain stores, no atomics. Aligned Float and Int stores are single
/// instructions on arm64, so the worst case is one buffer rendered with a value that
/// is a frame stale. Move to Synchronization.Atomic if the target ever goes to iOS 18+.
private final class SynthVoice
{
	// MARK: - Control values, written by the main thread

	var speedFraction: Float = 0
	var throttle: Float = 0
	var isReversing = false
	var crashTrigger = 0
	var jamTrigger = 0
	var hornTrigger = 0

	// MARK: - Render state, owned by the audio thread

	var sampleRate: Float = 44100
	private var enginePhase: Float = 0
	private var engineFrequency: Float = Constants.idleFrequency
	private var engineGain: Float = 0
	private var rattleState: Float = 0
	private var beeperPhase: Float = 0
	private var beeperClock: Float = 0
	private var beeperGain: Float = 0
	private var noiseState: UInt32 = 0x1234_5678
	private var crashEnvelope: Float = 0
	private var crashThumpPhase: Float = 0
	private var jamEnvelope: Float = 0
	private var jamPhase: Float = 0
	private var hornSecondsLeft: Float = 0
	private var hornPhaseLow: Float = 0
	private var hornPhaseHigh: Float = 0
	private var hornGain: Float = 0
	private var seenCrashTrigger = 0
	private var seenJamTrigger = 0
	private var seenHornTrigger = 0

	private enum Constants
	{
		static let idleFrequency: Float = 30
		static let fundamentalWeight: Float = 1.4
		static let secondHarmonicWeight: Float = 0.6
		static let thirdHarmonicWeight: Float = 0.35
		static let thirdHarmonicPhaseOffset: Float = 0.5
		static let fourthHarmonicWeight: Float = 0.2
		static let hornSecondHarmonicWeight: Float = 0.4
		static let hornThirdHarmonicWeight: Float = 0.2
		/// Below this an envelope is silent and its voice is skipped.
		static let envelopeFloor: Float = 0.001
		/// Below this a smoothed gain snaps to zero instead of decaying into subnormals.
		static let gainFloor: Float = 1e-6
		static let frequencyRiseWithSpeed: Float = 58
		static let frequencyRiseWithThrottle: Float = 9
		static let frequencySmoothing: Float = 0.0004
		static let idleGain: Float = 0.30
		static let gainRiseWithSpeed: Float = 0.30
		static let gainRiseWithThrottle: Float = 0.18
		static let gainSmoothing: Float = 0.0008
		static let rattleLevel: Float = 0.10
		static let rattleSmoothing: Float = 0.25
		static let beeperFrequency: Float = 1000
		static let beeperPeriod: Float = 0.7
		static let beeperOnFraction: Float = 0.45
		static let beeperLevel: Float = 0.10
		static let beeperSmoothing: Float = 0.003
		static let crashDecaySeconds: Float = 0.22
		static let crashNoiseLevel: Float = 0.9
		static let crashThumpFrequency: Float = 55
		static let crashThumpLevel: Float = 0.8
		static let jamFrequency: Float = 85
		static let jamDecaySeconds: Float = 0.09
		static let jamLevel: Float = 0.7
		static let hornSeconds: Float = 0.9
		static let hornReleaseSeconds: Float = 0.25
		static let hornLowFrequency: Float = 233
		static let hornHighFrequency: Float = 311
		static let hornLevel: Float = 0.30
		static let hornSmoothing: Float = 0.001
		static let twoPi = Float.pi * 2
	}

	// MARK: - Public API

	func render(into bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int)
	{
		let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
		guard let first = buffers.first,
			  let output = first.mData?.assumingMemoryBound(to: Float.self)
		else { return }

		if crashTrigger != seenCrashTrigger
		{
			seenCrashTrigger = crashTrigger
			crashEnvelope = 1
			crashThumpPhase = 0
		}
		if jamTrigger != seenJamTrigger
		{
			seenJamTrigger = jamTrigger
			jamEnvelope = 1
			jamPhase = 0
		}
		if hornTrigger != seenHornTrigger
		{
			seenHornTrigger = hornTrigger
			hornSecondsLeft = Constants.hornSeconds
			hornPhaseLow = 0
			hornPhaseHigh = 0
		}

		let targetFrequency = Constants.idleFrequency
			+ Constants.frequencyRiseWithSpeed * speedFraction
			+ Constants.frequencyRiseWithThrottle * abs(throttle)
		let targetGain = Constants.idleGain
			+ Constants.gainRiseWithSpeed * speedFraction
			+ Constants.gainRiseWithThrottle * abs(throttle)
		let crashDecay = exp(-1 / (Constants.crashDecaySeconds * sampleRate))
		let jamDecay = exp(-1 / (Constants.jamDecaySeconds * sampleRate))
		let secondsPerSample = 1 / sampleRate

		for frame in 0 ..< frameCount
		{
			engineFrequency += (targetFrequency - engineFrequency) * Constants.frequencySmoothing
			engineGain += (targetGain - engineGain) * Constants.gainSmoothing
			enginePhase += Constants.twoPi * engineFrequency * secondsPerSample
			if enginePhase > Constants.twoPi
			{
				enginePhase -= Constants.twoPi
			}

			// A diesel is a stack of harmonics with a rattle on top. tanh rounds the peaks
			// so the sum reads as one thick note rather than three thin ones.
			let noise = nextNoise()
			rattleState += (noise - rattleState) * Constants.rattleSmoothing
			let harmonics = Constants.fundamentalWeight * sin(enginePhase)
				+ Constants.secondHarmonicWeight * sin(2 * enginePhase)
				+ Constants.thirdHarmonicWeight * sin(3 * enginePhase + Constants.thirdHarmonicPhaseOffset)
				+ Constants.fourthHarmonicWeight * sin(4 * enginePhase)
			let rattle = rattleState * Constants.rattleLevel * (1 + sin(2 * enginePhase))
			var sample = tanh(harmonics + rattle) * engineGain

			// The beeper is a gated tone. The gate is smoothed so it never clicks.
			beeperClock += secondsPerSample
			if beeperClock > Constants.beeperPeriod
			{
				beeperClock -= Constants.beeperPeriod
			}
			let beeperWanted: Float = isReversing && beeperClock < Constants.beeperPeriod * Constants.beeperOnFraction
				? Constants.beeperLevel : 0
			beeperGain += (beeperWanted - beeperGain) * Constants.beeperSmoothing
			if beeperWanted == 0 && beeperGain < Constants.gainFloor
			{
				beeperGain = 0
			}
			beeperPhase += Constants.twoPi * Constants.beeperFrequency * secondsPerSample
			if beeperPhase > Constants.twoPi
			{
				beeperPhase -= Constants.twoPi
			}
			sample += sin(beeperPhase) * beeperGain

			if crashEnvelope > Constants.envelopeFloor
			{
				crashThumpPhase += Constants.twoPi * Constants.crashThumpFrequency * secondsPerSample
				sample += nextNoise() * crashEnvelope * Constants.crashNoiseLevel
					+ sin(crashThumpPhase) * crashEnvelope * crashEnvelope * Constants.crashThumpLevel
				crashEnvelope *= crashDecay
			}

			if jamEnvelope > Constants.envelopeFloor
			{
				jamPhase += Constants.twoPi * Constants.jamFrequency * secondsPerSample
				sample += sin(jamPhase) * jamEnvelope * Constants.jamLevel
				jamEnvelope *= jamDecay
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
				hornPhaseLow += Constants.twoPi * Constants.hornLowFrequency * secondsPerSample
				hornPhaseHigh += Constants.twoPi * Constants.hornHighFrequency * secondsPerSample
				sample += (hornVoice(phase: hornPhaseLow) + hornVoice(phase: hornPhaseHigh)) * hornGain
			}

			output[frame] = tanh(sample)
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

	private func hornVoice(phase: Float) -> Float
	{
		return sin(phase) + Constants.hornSecondHarmonicWeight * sin(2 * phase)
			+ Constants.hornThirdHarmonicWeight * sin(3 * phase)
	}

	/// xorshift32, mapped to -1 ... 1. No allocation, no locks: safe on the audio thread.
	private func nextNoise() -> Float
	{
		noiseState ^= noiseState << 13
		noiseState ^= noiseState >> 17
		noiseState ^= noiseState << 5
		return Float(noiseState) / Float(UInt32.max) * 2 - 1
	}
}

final class SynthesisedSoundEngine: SoundEngine
{
	// MARK: - Private Properties

	private let engine = AVAudioEngine()
	private let voice = SynthVoice()
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
		voice.sampleRate = Float(Constants.sampleRate)

		let voice = self.voice
		let node = AVAudioSourceNode(format: format)
		{ _, _, frameCount, audioBufferList -> OSStatus in
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
		voice.speedFraction = Float(state.speedFraction)
		voice.throttle = Float(state.throttle)
		voice.isReversing = state.isReversing
	}

	func playCrash()
	{
		voice.crashTrigger += 1
	}

	func playJam()
	{
		voice.jamTrigger += 1
	}

	func playParked()
	{
		voice.hornTrigger += 1
	}
}

// MARK: - Sampled

/// Plays the generated WAV files. The engine loop goes through a varispeed unit, so
/// pitch and tempo rise together with speed, which is what a real engine does.
final class SampledSoundEngine: SoundEngine
{
	// MARK: - Private Properties

	private let engine = AVAudioEngine()
	private let enginePlayer = AVAudioPlayerNode()
	private let varispeed = AVAudioUnitVarispeed()
	/// A player's `volume` is applied by the mixer it feeds. The engine player feeds
	/// the varispeed unit, so it needs a mixer of its own for the volume to do anything.
	private let engineMixer = AVAudioMixerNode()
	private let ambientPlayer = AVAudioPlayerNode()
	private let beeperPlayer = AVAudioPlayerNode()
	private let oneShotPlayer = AVAudioPlayerNode()
	private var engineLoop: AVAudioPCMBuffer?
	private var ambientLoop: AVAudioPCMBuffer?
	private var beeperLoop: AVAudioPCMBuffer?
	private var oneShots: [String: AVAudioPCMBuffer] = [:]
	private var isGraphBuilt = false
	private var isRunning = false
	private var isBeeping = false

	private enum Constants
	{
		static let engineLoopFile = "engine_loop"
		static let ambientLoopFile = "ambient_loop"
		static let beeperLoopFile = "beeper_loop"
		static let crashFile = "crash"
		static let jamFile = "jam"
		static let hornFile = "horn"
		static let fileExtension = "wav"
		static let soundsSubdirectory = "Sounds"

		static let idleRate: Float = 0.75
		static let rateRiseWithSpeed: Float = 1.05
		static let rateRiseWithThrottle: Float = 0.10
		static let idleVolume: Float = 0.35
		static let volumeRiseWithSpeed: Float = 0.35
		static let volumeRiseWithThrottle: Float = 0.2
		static let ambientVolume: Float = 0.5
		static let beeperVolume: Float = 0.5
		static let oneShotVolume: Float = 1.0
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
		if let loop = engineLoop
		{
			enginePlayer.scheduleBuffer(loop, at: nil, options: .loops)
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
		// A player with no file is attached but not connected, and playing it raises.
		if engineLoop != nil
		{
			enginePlayer.play()
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
		for player in [enginePlayer, ambientPlayer, beeperPlayer, oneShotPlayer]
		{
			player.stop()
		}
		engine.stop()
		isRunning = false
		isBeeping = false
	}

	func update(_ state: SoundState)
	{
		guard isRunning
		else { return }

		let speed = Float(state.speedFraction)
		let throttle = Float(abs(state.throttle))
		varispeed.rate = Constants.idleRate + Constants.rateRiseWithSpeed * speed
			+ Constants.rateRiseWithThrottle * throttle
		engineMixer.outputVolume = Constants.idleVolume + Constants.volumeRiseWithSpeed * speed
			+ Constants.volumeRiseWithThrottle * throttle

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

	func playParked()
	{
		playOneShot(Constants.hornFile)
	}

	// MARK: - Private

	/// Attached and connected once. A missing file leaves that player unconnected and
	/// silent rather than crashing: the WAVs come from a script and can be absent.
	private func buildGraph()
	{
		isGraphBuilt = true
		for player in [enginePlayer, ambientPlayer, beeperPlayer, oneShotPlayer]
		{
			engine.attach(player)
		}
		engine.attach(varispeed)
		engine.attach(engineMixer)

		engineLoop = buffer(named: Constants.engineLoopFile)
		if let loop = engineLoop
		{
			engine.connect(enginePlayer, to: varispeed, format: loop.format)
			engine.connect(varispeed, to: engineMixer, format: loop.format)
			engine.connect(engineMixer, to: engine.mainMixerNode, format: loop.format)
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
		for name in [Constants.crashFile, Constants.jamFile, Constants.hornFile]
		{
			guard let sound = buffer(named: name)
			else { continue }
			if oneShots.isEmpty
			{
				engine.connect(oneShotPlayer, to: engine.mainMixerNode, format: sound.format)
			}
			oneShots[name] = sound
		}
		oneShotPlayer.volume = Constants.oneShotVolume
	}

	private func playOneShot(_ name: String)
	{
		guard isRunning,
			  let sound = oneShots[name]
		else { return }
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
