//	==================================================
//	'AppDelegate.swift'
//	--------------------------------------------------
//	Hands every window to SceneDelegate. No storyboard.
//
//	--------------------------------------------------
//							 Copyright (c) 2026 Jan Barnholt
//	==================================================

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate
{
	private enum Constants
	{
		/// Must match the name in Info.plist's scene manifest.
		static let sceneConfigurationName = "Default Configuration"
	}

	// MARK: - Lifecycle

	func application(_ application: UIApplication,
					 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
	{
		return true
	}

	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
					 options: UIScene.ConnectionOptions) -> UISceneConfiguration
	{
		return UISceneConfiguration(name: Constants.sceneConfigurationName, sessionRole: connectingSceneSession.role)
	}
}
