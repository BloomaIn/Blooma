//
//  SceneDelegate.swift
//  prenatalPregnancy
//
//  Created by GEU on 30/01/26.
//

import UIKit
import FirebaseAuth

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    var dataModel: DataController!

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let firebaseUser = Auth.auth().currentUser
        let isLoggedIn = firebaseUser != nil || UserDefaults.standard.bool(forKey: "isLoggedIn")
        let loginType = UserDefaults.standard.string(forKey: "loginType")
        
        dataModel = DataController(
            userProfile: UserProfile(
                userId: UUID(),
                profileImageData: nil,
                name: "",
                email: nil,
                userName: "",
                password: "",
                age: 0,
                lmpDate: nil,
                eddDate: nil,
                gestationalWeek: 1,
                gestationalDay: 0,
                trimester: .first,
                medicalConditions: [],
                activityLevel: .low,
                hasAppleWatch: false
            )
        )
        
        if isLoggedIn {
            
            if let savedUserId = UserDefaults.standard.string(forKey: "userId") {
                
                dataModel.currentUserId = savedUserId
                
                dataModel.loadProfileFromFirestore { profile in
                    if let profile = profile {
                        self.dataModel.loadProgressFromFirestore {
                            DispatchQueue.main.async {
                                self.dataModel.userProfile = profile
                                self.showMainApp(storyboard: storyboard)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showLogin(storyboard: storyboard)
                        }
                    }
                }
                
            } else {
                showLogin(storyboard: storyboard)
            }
        }
        
        else {
            showLogin(storyboard: storyboard)
        }
        
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        dataModel?.refreshPregnancyProgressIfNeeded()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        dataModel?.refreshPregnancyProgressIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        Task { @MainActor in
            FocusWorkoutSessionManager.shared.startLiveActivityIfNeeded()
        }
    }


}

extension SceneDelegate {

    func showMainApp(storyboard: UIStoryboard) {

        let tabBarVC = storyboard.instantiateViewController(identifier: "MainTabBarController") as! MainTabBarController
        tabBarVC.dataController = dataModel
        dataModel.requestStartupTrackingPermissions()

        window?.rootViewController = tabBarVC
        window?.installGlobalParticleOverlay(theme: dataModel.theme)
        window?.makeKeyAndVisible()
    }

    func showLogin(storyboard: UIStoryboard) {

        guard let navVC = storyboard.instantiateInitialViewController() as? UINavigationController else { return }

        window?.rootViewController = navVC
        window?.installGlobalParticleOverlay(theme: dataModel.theme)
        window?.makeKeyAndVisible()

        if let loginVC = navVC.topViewController as? OnboardingLoginViewController {
            loginVC.dataController = dataModel
        }
    }
}
