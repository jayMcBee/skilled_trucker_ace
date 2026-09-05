//	==================================================
//	'OptionsViewController.swift'
//	--------------------------------------------------
//	The options sheet. Every dial from the web build, plus the pad swap, the
//	particle toggle and the sound engine switch. The consequence of each speed dial
//	is printed under it, live, so the number can be found by feel.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit

final class OptionsViewController: UIViewController
{
	// MARK: - Callbacks

	var onDismiss: (() -> Void)?

	// MARK: - Private Properties

	private let presetControl = UISegmentedControl(items: Preset.all.map { $0.name })
	private let forwardSlider = UISlider()
	private let reverseSlider = UISlider()
	private let forwardCaption = UILabel()
	private let reverseCaption = UILabel()
	private let jackknifeSwitch = UISwitch()
	private let swapSwitch = UISwitch()
	private let particlesSwitch = UISwitch()
	private let soundControl = UISegmentedControl(items: Constants.soundNames)
	private let lotEdgeControl = UISegmentedControl(items: Constants.lotEdgeNames)
	private let lotAcrossSwitch = UISwitch()
	private let wheelSlider = UISlider()
	private let wheelCaption = UILabel()
	private let pitchSlider = UISlider()
	private let pitchCaption = UILabel()

	private enum Constants
	{
		static let soundNames = ["Off", "Synth", "Samples"]
		static let lotEdgeNames = ["Open", "Kerb"]
		static let sheetSize = CGSize(width: 540, height: 620)
		static let margin: CGFloat = 24
		static let rowSpacing: CGFloat = 22
		static let captionSpacing: CGFloat = 8
		static let captionFontSize: CGFloat = 13
		static let sliderStep: Float = 0.1
		static let fineSliderStep: Float = 0.05
	}

	// MARK: - Lifecycle

	override func viewDidLoad()
	{
		super.viewDidLoad()
		title = "Options"
		view.backgroundColor = .systemGroupedBackground
		preferredContentSize = Constants.sheetSize
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self,
															action: #selector(finish))

		presetControl.selectedSegmentIndex = GameOptions.presetIndex
		forwardSlider.minimumValue = Float(Tuning.lowestFactor)
		forwardSlider.maximumValue = Float(Tuning.highestForwardFactor)
		forwardSlider.value = Float(GameOptions.forwardFactor)
		reverseSlider.minimumValue = Float(Tuning.lowestFactor)
		reverseSlider.maximumValue = Float(Tuning.highestReverseFactor)
		reverseSlider.value = Float(GameOptions.reverseFactor)
		jackknifeSwitch.isOn = GameOptions.jackknifeEndsRun
		swapSwitch.isOn = GameOptions.swapPads
		particlesSwitch.isOn = GameOptions.particlesEnabled
		soundControl.selectedSegmentIndex = GameOptions.soundChoice.rawValue
		lotEdgeControl.selectedSegmentIndex = GameOptions.lotEdge.rawValue
		lotAcrossSwitch.isOn = GameOptions.lotAcrossScreen
		wheelSlider.minimumValue = Float(GameOptions.lowestSteeredWheelScale)
		wheelSlider.maximumValue = Float(GameOptions.highestSteeredWheelScale)
		wheelSlider.value = Float(GameOptions.steeredWheelScale)
		pitchSlider.minimumValue = Float(GameOptions.lowestEnginePitch)
		pitchSlider.maximumValue = Float(GameOptions.highestEnginePitch)
		pitchSlider.value = Float(GameOptions.enginePitch)

		for caption in [forwardCaption, reverseCaption, wheelCaption, pitchCaption]
		{
			caption.font = .monospacedDigitSystemFont(ofSize: Constants.captionFontSize, weight: .regular)
			caption.textColor = .secondaryLabel
			caption.numberOfLines = 0
		}

		presetControl.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		forwardSlider.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		reverseSlider.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		jackknifeSwitch.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		swapSwitch.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		particlesSwitch.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		soundControl.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		lotEdgeControl.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		lotAcrossSwitch.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		wheelSlider.addTarget(self, action: #selector(controlChanged), for: .valueChanged)
		pitchSlider.addTarget(self, action: #selector(controlChanged), for: .valueChanged)

		let stack = UIStackView(arrangedSubviews: [
			titled("Handling preset", presetControl),
			titled("Forward speed", forwardSlider, caption: forwardCaption),
			titled("Reverse speed", reverseSlider, caption: reverseCaption),
			row("Jackknife ends the run", jackknifeSwitch),
			titled("Lot edge (open: drive anywhere, kerb: a scrape on the edge ends the run)", lotEdgeControl),
			row("Swap the pads (drive on the right)", swapSwitch),
			row("Lot across the screen (lane left to right)", lotAcrossSwitch),
			titled("Steered wheel size", wheelSlider, caption: wheelCaption),
			row("Particle effects", particlesSwitch),
			titled("Sound engine", soundControl),
			titled("Engine pitch", pitchSlider, caption: pitchCaption)
		])
		stack.axis = .vertical
		stack.spacing = Constants.rowSpacing
		stack.translatesAutoresizingMaskIntoConstraints = false

		let scroll = UIScrollView()
		scroll.translatesAutoresizingMaskIntoConstraints = false
		scroll.addSubview(stack)
		view.addSubview(scroll)
		NSLayoutConstraint.activate([
			scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: Constants.margin),
			stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -Constants.margin),
			stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Constants.margin),
			stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Constants.margin),
			stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -Constants.margin * 2)
		])

		refreshCaptions()
	}

	override func viewDidDisappear(_ animated: Bool)
	{
		super.viewDidDisappear(animated)
		onDismiss?()
	}

	// MARK: - Private

	@objc private func finish()
	{
		dismiss(animated: true)
	}

	/// Sliders snap to tenths, as the web build's keys stepped, so a value can be
	/// named and typed back in.
	@objc private func controlChanged()
	{
		forwardSlider.value = (forwardSlider.value / Constants.sliderStep).rounded() * Constants.sliderStep
		reverseSlider.value = (reverseSlider.value / Constants.sliderStep).rounded() * Constants.sliderStep
		wheelSlider.value = (wheelSlider.value / Constants.sliderStep).rounded() * Constants.sliderStep
		pitchSlider.value = (pitchSlider.value / Constants.fineSliderStep).rounded() * Constants.fineSliderStep
		GameOptions.presetIndex = presetControl.selectedSegmentIndex
		GameOptions.forwardFactor = Double(forwardSlider.value)
		GameOptions.reverseFactor = Double(reverseSlider.value)
		GameOptions.jackknifeEndsRun = jackknifeSwitch.isOn
		GameOptions.swapPads = swapSwitch.isOn
		GameOptions.particlesEnabled = particlesSwitch.isOn
		GameOptions.soundChoice = SoundChoice(rawValue: soundControl.selectedSegmentIndex) ?? .off
		GameOptions.lotEdge = LotEdge(rawValue: lotEdgeControl.selectedSegmentIndex) ?? .open
		GameOptions.lotAcrossScreen = lotAcrossSwitch.isOn
		GameOptions.steeredWheelScale = Double(wheelSlider.value)
		GameOptions.enginePitch = Double(pitchSlider.value)
		refreshCaptions()
	}

	/// The fold clock is the only thing reverse speed trades against, so it sits
	/// next to the dial that spends it.
	private func refreshCaptions()
	{
		let world = World(preset: GameOptions.preset, tuning: GameOptions.tuning)
		forwardCaption.text = String(format: "%.0f km/h  (%.1f×). Forward costs nothing: the fold converges going forward.",
									 world.forwardKilometresPerHour, world.tuning.forwardFactor)
		let foldClock = world.secondsOfFullLockReverseBeforeJam()
		let foldText = foldClock.map { String(format: "%.1f s", $0) } ?? "never"
		reverseCaption.text = String(format: "%.1f km/h  (%.1f×). Fold clock %@: seconds of full-lock reversing before it jams.",
									 world.reverseKilometresPerHour, world.tuning.reverseFactor, foldText)
		wheelCaption.text = String(format: "%.1f× the baked tyre. The pair stays inside the cab's box at any size.",
								   GameOptions.steeredWheelScale)
		pitchCaption.text = String(format: "%.2f× the rendered engine. Lower is a bigger, slower diesel. Applies live, to both engines.",
								   GameOptions.enginePitch)
	}

	private func titled(_ title: String, _ control: UIView, caption: UILabel? = nil) -> UIStackView
	{
		let label = UILabel()
		label.text = title
		label.font = .preferredFont(forTextStyle: .headline)
		var views: [UIView] = [label, control]
		if let caption = caption
		{
			views.append(caption)
		}
		let stack = UIStackView(arrangedSubviews: views)
		stack.axis = .vertical
		stack.spacing = Constants.captionSpacing
		return stack
	}

	private func row(_ title: String, _ control: UIView) -> UIStackView
	{
		let label = UILabel()
		label.text = title
		label.font = .preferredFont(forTextStyle: .headline)
		let stack = UIStackView(arrangedSubviews: [label, control])
		stack.axis = .horizontal
		stack.alignment = .center
		stack.distribution = .equalSpacing
		return stack
	}
}
