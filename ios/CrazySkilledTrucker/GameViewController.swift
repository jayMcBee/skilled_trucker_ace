//	==================================================
//	'GameViewController.swift'
//	--------------------------------------------------
//	Hosts the SpriteKit scene and presents the options sheet over it.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit
import SpriteKit

final class GameViewController: UIViewController
{
	// MARK: - Private Properties

	private let scene = GameScene(size: CGSize(width: Canvas.width, height: Canvas.height))

	private enum Constants
	{
		static let framesPerSecond = 60
	}

	// MARK: - Presentation

	/// The lot is wider than it is tall and letterboxes to fit, so portrait would
	/// waste most of the screen on empty asphalt.
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask
	{
		return .landscape
	}

	override var prefersStatusBarHidden: Bool
	{
		return true
	}

	override var prefersHomeIndicatorAutoHidden: Bool
	{
		return true
	}

	/// The drive pad's reverse end is near the bottom edge. A thumb sliding down for
	/// full reverse must not trip the home-indicator gesture.
	override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge
	{
		return .bottom
	}

	// MARK: - Lifecycle

	override func loadView()
	{
		view = SKView()
	}

	override func viewDidLoad()
	{
		super.viewDidLoad()

		guard let spriteView = view as? SKView
		else { return }

		// Two thumbs at once is the whole control scheme. UIView defaults to one touch.
		spriteView.isMultipleTouchEnabled = true
		// Tree order breaks z ties. With sibling order ignored, a truck body can be drawn
		// over its own detail and the asphalt over the parked trucks.
		spriteView.ignoresSiblingOrder = false
		spriteView.preferredFramesPerSecond = Constants.framesPerSecond
		scene.onOptionsRequested = { [weak self] in self?.presentOptions() }
		spriteView.presentScene(scene)
	}

	// MARK: - Private

	/// The scene pauses under the sheet, so the truck is where it was left when the
	/// sheet closes and the options are applied.
	private func presentOptions()
	{
		guard let spriteView = view as? SKView,
			  presentedViewController == nil
		else { return }

		scene.quietSound()
		spriteView.isPaused = true
		let options = OptionsViewController()
		options.onDismiss =
		{ [weak self, weak spriteView] in
			spriteView?.isPaused = false
			self?.scene.applyOptions()
		}
		let navigation = UINavigationController(rootViewController: options)
		navigation.modalPresentationStyle = .formSheet
		present(navigation, animated: true)
	}
}
