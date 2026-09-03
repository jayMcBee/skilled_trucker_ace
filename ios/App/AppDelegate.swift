//	==================================================
//	'AppDelegate.swift'
//	--------------------------------------------------
//	One window, one view controller, no storyboard.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate
{
	// MARK: - Public Properties

	var window: UIWindow?

	// MARK: - Lifecycle

	func application(_ application: UIApplication,
					 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
	{
		let window = UIWindow(frame: UIScreen.main.bounds)
		window.rootViewController = ViewController()
		window.makeKeyAndVisible()
		self.window = window
		return true
	}
}
