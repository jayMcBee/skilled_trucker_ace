//	==================================================
//	'SceneDelegate.swift'
//	--------------------------------------------------
//	One window, one view controller.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate
{
	// MARK: - Public Properties

	var window: UIWindow?

	// MARK: - Lifecycle

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
	{
		guard let windowScene = scene as? UIWindowScene
		else { return }

		let window = UIWindow(windowScene: windowScene)
		window.rootViewController = GameViewController()
		window.makeKeyAndVisible()
		self.window = window
	}
}
