//	==================================================
//	'ViewController.swift'
//	--------------------------------------------------
//	Hosts the SpriteKit scene. Replaces the template's empty view controller; the
//	storyboard scene needs no outlets and no changes.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit
import SpriteKit

final class ViewController: UIViewController
{
	// MARK: - Private Properties

	private let scene = GameScene(size: CGSize(width: Canvas.width, height: Canvas.height))

	// MARK: - Lifecycle

	/// Replaces the storyboard's plain UIView with an SKView. Nothing in the storyboard
	/// scene is referenced, so there is no outlet to lose.
	override func loadView()
	{
		view = SKView()
	}

	override func viewDidLoad()
	{
		super.viewDidLoad()

		guard let spriteView = view as? SKView
		else { return }

		spriteView.ignoresSiblingOrder = true
		spriteView.presentScene(scene)
	}

	// MARK: - Presentation

	/// The lot is wider than it is tall and the scene letterboxes with .aspectFit, so
	/// portrait would waste most of the screen on empty asphalt.
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
}
