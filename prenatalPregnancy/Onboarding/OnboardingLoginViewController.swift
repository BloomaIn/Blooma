//
//  OnboardingLoginViewController.swift
//  prenatalPregnancy
//
//  Created by GEU on 07/02/26.
//

import UIKit
import Lottie
import AuthenticationServices

class OnboardingLoginViewController: UIViewController, ASAuthorizationControllerPresentationContextProviding, UITextFieldDelegate {
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.view.window!
    }
    
    @IBOutlet weak var animationContainerView: UIView!
    
    @IBOutlet weak var containerView: UIView!
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var googleButton: UIButton!
    @IBOutlet weak var guestButton: UIButton!
    
    var dataController: DataController!
    var appName: String = "Blooma"
    var theme: AppTheme!
    
    private var animationView: LottieAnimationView!
    private weak var activeTextField: UITextField?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupDataController()
        configureUI()
        setupTextFields()
        setupLottie()
        setupKeyboard()
        updateLoginState()
        setupKeyboardObservers()
        
        // Do any additional setup after loading the view.
    }
    
    private func setupDataController() {
        if dataController == nil {
            if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate {
                dataController = sceneDelegate.dataModel
            }
        }
    }
    
    private func configureUI() {
        
        theme = dataController.theme
        applyAnimatedBackground(theme: theme)
        
        navigationItem.title = appName
        
        titleLabel.text = "Welcome Back"
        subtitleLabel.text = "Login to continue"
        
        titleLabel.textColor = theme.primaryText
        subtitleLabel.textColor = theme.secondaryText
        
        containerView.layer.cornerRadius = 24
        containerView.backgroundColor = theme.glassMedium
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = theme.glassBorderLight.cgColor
        
        loginButton.setTitle("Login", for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        
        if let googleImage = UIImage(named: "Google") {
            let resized = googleImage.resize(to: CGSize(width: 38, height: 38))
            googleButton.setImage(resized.withRenderingMode(.alwaysOriginal), for: .normal)
        }
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let guestImage = UIImage(systemName: "person.fill", withConfiguration: config)
        guestButton.setImage(guestImage, for: .normal)
        guestButton.tintColor = theme.primaryText
        
        stylePrimaryButton(loginButton)
        styleSecondaryButton(googleButton)
        styleSecondaryButton(guestButton)
    }
    
    private func setupTextFields() {
        
        setupGlassTextField(usernameTextField)
        setupGlassTextField(passwordTextField)
        
        usernameTextField.delegate = self
        passwordTextField.delegate = self
        
        passwordTextField.isSecureTextEntry = true
        
        usernameTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        passwordTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }
    
    private func setupLottie() {
        
        animationView = LottieAnimationView(name: "Intro")
        animationView.loopMode = .loop
        animationView.backgroundBehavior = .pauseAndRestore
        
        animationView.backgroundColor = .clear
        
        animationContainerView.backgroundColor = .clear
        
        animationView.frame = animationContainerView.bounds
        animationContainerView.addSubview(animationView)
        
        animationView.play()
    }
    
    private func setupGlassTextField(_ textField: UITextField) {
        
        textField.textColor = theme.primaryText
        textField.tintColor = theme.accentSecondary
        textField.font = .systemFont(ofSize: 16, weight: .regular)
        textField.backgroundColor = theme.inputGlassBackground
        if let placeholder = textField.placeholder {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: theme.secondaryText.withAlphaComponent(0.75)]
            )
        }
        
        textField.layer.cornerRadius = 12
        textField.layer.borderWidth = 1
        textField.layer.borderColor = theme.inputGlassBorder.cgColor
        
        textField.clipsToBounds = true
        
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: textField.frame.height))
        textField.leftView = padding
        textField.leftViewMode = .always
        
        applyGlassEffect(to: textField)
    }
    
    private func stylePrimaryButton(_ button: UIButton) {
        
        button.layer.cornerRadius = 18
        button.backgroundColor = theme.buttonGlassBackground
        button.setTitleColor(theme.buttonText, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        
        button.layer.borderWidth = 1
        button.layer.borderColor = theme.buttonGlassBorder.cgColor
        button.layer.shadowOpacity = 0.08
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        
        applyGlassEffect(to: button)
    }
    
    private func styleSecondaryButton(_ button: UIButton) {
        
        button.layer.cornerRadius = 16
        button.backgroundColor = theme.glassThin
        button.setTitleColor(theme.primaryText, for: .normal)
    }
    
    private func applyGlassEffect(to view: UIView) {
        
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurView = UIVisualEffectView(effect: blur)
        
        blurView.frame = view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.layer.cornerRadius = view.layer.cornerRadius
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        
        view.insertSubview(blurView, at: 0)
    }
    
    private func setupKeyboard() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if textField == usernameTextField {
            passwordTextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            loginTapped(loginButton)
        }
        
        return true
    }
    
    @objc private func textChanged() {
        updateLoginState()
    }
    
    private func updateLoginState() {
        
        let username = usernameTextField.text ?? ""
        let password = passwordTextField.text ?? ""
        
        let isValid = !username.isEmpty && !password.isEmpty
        
        loginButton.isEnabled = isValid
        loginButton.alpha = isValid ? 1.0 : 0.5
    }
    
    private func setupKeyboardObservers() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc private func keyboardWillShow(notification: Notification) {
        
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let activeField = activeTextField else { return }
        
        let keyboardHeight = keyboardFrame.height
        
        let fieldFrame = activeField.convert(activeField.bounds, to: view)
        
        let bottomSpace = view.frame.height - fieldFrame.maxY
        
        if bottomSpace < keyboardHeight {
            
            let shift = keyboardHeight - bottomSpace + 20
            
            UIView.animate(withDuration: 0.3) {
                self.view.transform = CGAffineTransform(translationX: 0, y: -shift)
            }
        }
    }
    
    @objc private func keyboardWillHide(notification: Notification) {
        
        UIView.animate(withDuration: 0.3) {
            self.view.transform = .identity
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        activeTextField = nil
    }
    
    @IBAction func loginTapped(_ sender: UIButton) {
        
        view.endEditing(true)
        
        let username = usernameTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let password = passwordTextField.text ?? ""
        
        let isEmail = username.contains("@")

        let credentials = LoginCredentials(
            username: isEmail ? nil : username,
            email: isEmail ? username : nil,
            password: password
        )
        
        showLoader()
        
        dataController.loginWithUsername(credentials: credentials) { result, state in
            
            self.hideLoader()
            
            switch result {
                
            case .success:
                
                UserDefaults.standard.set(true, forKey: "isLoggedIn")
                UserDefaults.standard.set("username", forKey: "loginType")
                
                if state == .newUser {
                    self.performSegue(withIdentifier: "onboarding_login_to_name", sender: self)
                } else {
                    self.goToHome()
                }
                
            case .failure(let error):
                
                self.shake(view: self.passwordTextField)
                
                let message: String

                switch error {
                case .userNotFound:
                    message = "User does not exist. Please sign up."
                case .wrongPassword:
                    message = "Incorrect password."
                default:
                    message = "Something went wrong."
                }

                self.showAlert(title: "Login Failed", message: message)
            }
        }
    }
    
    @IBAction func googleTapped(_ sender: UIButton) {
        dataController.signInWithGoogle(from: self) { result, state in
            
            switch result {
                
            case .success:
                
                UserDefaults.standard.set(true, forKey: "isLoggedIn")
                UserDefaults.standard.set("google", forKey: "loginType")
                
                if state == .newUser {
                    self.performSegue(withIdentifier: "onboarding_login_to_name", sender: self)
                } else {
                    self.goToHome()
                }
                
            case .failure(let error):
                self.showAlert(title: "Login Failed", message: error.localizedDescription)
            }
        }
        
    }
    
    @IBAction func guestTapped(_ sender: UIButton) {
        
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        UserDefaults.standard.set("guest", forKey: "loginType")
        
        dataController.signInAsGuest()
        goToHome()
    }
    
    private func goToHome() {
        
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let window = scene.windows.first else { return }
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let tabBarVC = storyboard.instantiateViewController(identifier: "MainTabBarController") as! MainTabBarController
        
        tabBarVC.dataController = dataController
        
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = tabBarVC
        }
    }
    
    private func showAlert(title: String, message: String) {
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        present(alert, animated: true)
    }
    
    private func showLoader() {
        loginButton.isEnabled = false
        loginButton.setTitle("Logging in...", for: .normal)
    }
    
    private func hideLoader() {
        loginButton.isEnabled = true
        loginButton.setTitle("Login", for: .normal)
    }
    
    private func shake(view: UIView) {
        
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-8, 8, -6, 6, -3, 3, 0]
        animation.duration = 0.4
        
        view.layer.add(animation, forKey: "shake")
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "onboarding_login_to_name" {
            if let vc = segue.destination as? OnboardingUserCredentialsViewController {
                vc.dataController = dataController
                vc.appName = appName
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
