//
//  PersonalizationViewController.swift
//  prenatalPregnancy
//
//  Created by GEU on 01/04/26.
//

import UIKit
import Lottie

class PersonalizationViewController: UIViewController {
    
    @IBOutlet weak var animationView: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    var theme: AppTheme!
    
    var dataController: DataController!
    
    private var animationContainerView: LottieAnimationView!
    private var timer: Timer?
    private var stepIndex = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.theme = dataController.theme
        title = "Preparing Your Routine"
        
        navigationItem.hidesBackButton = true
        
        setupTheme()
        setupUI()
        setupLottie()
        startFilteringAnimation()
        
        // Do any additional setup after loading the view.
    }
    
    private func setupTheme() {
        applyAnimatedBackground(theme: theme)
        animationView.backgroundColor = .clear
    }
    
    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        subtitleLabel.text = "Filtering safe activities for you..."
        subtitleLabel.textColor = dataController.theme.secondaryText
    }
    
    private func setupLottie() {
        animationView.backgroundColor = .clear
        animationView.subviews.forEach { $0.removeFromSuperview() }
        
        animationContainerView = LottieAnimationView(name: "Gears")
        animationContainerView.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.contentMode = .scaleAspectFit
        animationContainerView.loopMode = .loop
        animationContainerView.backgroundColor = .clear
        
        animationView.addSubview(animationContainerView)
        
        NSLayoutConstraint.activate([
            animationContainerView.topAnchor.constraint(equalTo: animationView.topAnchor),
            animationContainerView.bottomAnchor.constraint(equalTo: animationView.bottomAnchor),
            animationContainerView.leadingAnchor.constraint(equalTo: animationView.leadingAnchor),
            animationContainerView.trailingAnchor.constraint(equalTo: animationView.trailingAnchor)
        ])
        
        animationContainerView.play()
    }
    
    private func startFilteringAnimation() {
        let steps = RoutineProcessingStep.allCases
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] timer in
            
            guard let self = self else { return }
            
            if self.stepIndex >= steps.count {
                timer.invalidate()
                self.finishAndNavigate()
                return
            }
            
            let step = steps[self.stepIndex]
            
            self.titleLabel.text = step.title
            self.subtitleLabel.text = step.subtitle
            
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.pulseAnimation()
            
            self.stepIndex += 1
        }
    }
    
    private func pulseAnimation() {
        UIView.animate(withDuration: 0.2, animations: {
            self.animationView.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.animationView.transform = .identity
            }
        }
    }
    
    private func finishAndNavigate() {
        self.dataController.saveProfileToFirestore()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let tabBarVC = storyboard.instantiateViewController(identifier: "MainTabBarController") as! MainTabBarController
            
            tabBarVC.dataController = self.dataController
            
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else { return }
            
            UIView.transition(with: window,
                              duration: 0.4,
                              options: .transitionCrossDissolve) {
                window.rootViewController = tabBarVC
            }
        }
    }
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destination.
     // Pass the selected object to the new view controller.
     }
     */
    
}
