/*
 * Copyright 2017 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import UIKit

import FirebaseDev // FirebaseAuth
import GoogleSignIn // GoogleSignIn

final class ViewController: UIViewController {
  /// The profile image for the currently signed-in user.
  @IBOutlet weak var profileImage: UIImageView!

  /// The display name for the currently signed-in user.
  @IBOutlet weak var displayNameLabel: UILabel!

  /// The email for the currently signed-in user.
  @IBOutlet weak var emailLabel: UILabel!

  /// The ID for the currently signed-in user.
  @IBOutlet weak var userIDLabel: UILabel!

  /// The list of providers for the currently signed-in user.
  @IBOutlet weak var providerListLabel: UILabel!

  /// The picker for the list of action types.
  @IBOutlet weak var actionTypePicker: UIPickerView!

  /// The picker for the list of actions.
  @IBOutlet weak var actionPicker: UIPickerView!

  /// The picker for the list of credential types.
  @IBOutlet weak var credentialTypePicker: UIPickerView!

  /// The label for the "email" text field.
  @IBOutlet weak var emailInputLabel: UILabel!

  /// The "email" text field.
  @IBOutlet weak var emailField: UITextField!

  /// The label for the "password" text field.
  @IBOutlet weak var passwordInputLabel: UILabel!

  /// The "password" text field.
  @IBOutlet weak var passwordField: UITextField!

  /// The currently selected action type.
  fileprivate var actionType = ActionType(rawValue: 0)! {
    didSet {
      if actionType != oldValue {
        actionPicker.reloadAllComponents()
        actionPicker.selectRow(actionType == .auth ? authAction.rawValue : userAction.rawValue,
                               inComponent: 0, animated: false)
      }
    }
  }

  /// The currently selected auth action.
  fileprivate var authAction = AuthAction(rawValue: 0)!

  /// The currently selected user action.
  fileprivate var userAction = UserAction(rawValue: 0)!

  /// The currently selected credential.
  fileprivate var credentialType = CredentialType(rawValue: 0)!

  /// The current Firebase user.
  fileprivate var user: User? = nil {
    didSet {
      if user?.uid != oldValue?.uid {
        actionTypePicker.reloadAllComponents()
        actionType = ActionType(rawValue: actionTypePicker.selectedRow(inComponent: 0))!
      }
    }
  }

  /// The user's photo URL used by the last network request for its contents.
  fileprivate var lastPhotoURL: URL? = nil

  override func viewDidLoad() {
    GIDSignIn.sharedInstance().uiDelegate = self
    updateUserInfo(Auth.auth())
    NotificationCenter.default.addObserver(forName: .AuthStateDidChange,
                                           object: Auth.auth(), queue: nil) { notification in
      self.updateUserInfo(notification.object as? Auth)
    }
  }

  /// Executes the action designated by the operator on the UI.
  @IBAction func execute(_ sender: UIButton) {
    switch actionType {
    case .auth:
      switch authAction {
      case .fetchProviderForEmail:
        Auth.auth().fetchProviders(forEmail: emailField.text!) { providers, error in
          self.ifNoError(error) {
            self.showAlert(title: "Providers", message: providers?.joined(separator: ", "))
          }
        }
      case .signInAnonymously:
        Auth.auth().signInAnonymously() { user, error in
          self.ifNoError(error) {
            self.showAlert(title: "Signed In Anonymously")
          }
        }
      case .signInWithCredential:
        getCredential() { credential in
          Auth.auth().signIn(with: credential) { user, error in
            self.ifNoError(error) {
              self.showAlert(title: "Signed In With Credential", message: user?.textDescription)
            }
          }
        }
      case .createUser:
        Auth.auth().createUser(withEmail: emailField.text!, password: passwordField.text!) {
            user, error in
          self.ifNoError(error) {
            self.showAlert(title: "Signed In With Credential", message: user?.textDescription)
          }
        }
      case .signOut:
        try! Auth.auth().signOut()
        GIDSignIn.sharedInstance().signOut()
      }
    case .user:
      switch userAction {
      case .updateEmail:
        user!.updateEmail(to: emailField.text!) { error in
          self.ifNoError(error) {
            self.showAlert(title: "Updated Email", message: self.user?.email)
          }
        }
      case .updatePassword:
        user!.updatePassword(to: passwordField.text!) { error in
          self.ifNoError(error) {
            self.showAlert(title: "Updated Password")
          }
        }
      case .reload:
        user!.reload() { error in
          self.ifNoError(error) {
            self.showAlert(title: "Reloaded", message: self.user?.textDescription)
          }
        }
      case .reauthenticate:
        getCredential() { credential in
          self.user!.reauthenticate(with: credential) { error in
            self.ifNoError(error) {
              self.showAlert(title: "Reauthenticated", message: self.user?.textDescription)
            }
          }
        }
      case .getToken:
        user!.getIDToken() { token, error in
          self.ifNoError(error) {
            self.showAlert(title: "Got ID Token", message: token)
          }
        }
      case .linkWithCredential:
        getCredential() { credential in
          self.user!.link(with: credential) { user, error in
            self.ifNoError(error) {
              self.showAlert(title: "Linked With Credential", message: user?.textDescription)
            }
          }
        }
      case .deleteAccount:
        user!.delete() { error in
          self.ifNoError(error) {
            self.showAlert(title: "Deleted Account")
          }
        }
      }
    }
  }

  /// Gets an AuthCredential potentially asynchronously.
  private func getCredential(completion: @escaping (AuthCredential) -> Void) {
    switch credentialType {
    case .google:
      GIDSignIn.sharedInstance().delegate = GoogleSignInDelegate(completion: { user, error in
        self.ifNoError(error) {
          completion(GoogleAuthProvider.credential(
              withIDToken: user!.authentication.idToken,
              accessToken: user!.authentication.accessToken))
        }
      })
      GIDSignIn.sharedInstance().signIn()
    case .password:
      completion(EmailAuthProvider.credential(withEmail: emailField.text!,
                                                         password: passwordField.text!))
    }
  }

  /// Updates user's profile image and info text.
  private func updateUserInfo(_ auth: Auth?) {
    user = auth?.currentUser
    displayNameLabel.text = user?.displayName
    emailLabel.text = user?.email
    userIDLabel.text = user?.uid
    let providers = user?.providerData.map { userInfo in userInfo.providerID }
    providerListLabel.text = providers?.joined(separator: ", ")
    if let photoURL = user?.photoURL {
      lastPhotoURL = photoURL
      DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async {
        if let imageData = try? Data(contentsOf: photoURL) {
          let image = UIImage(data: imageData)
          DispatchQueue.main.async {
            if self.lastPhotoURL == photoURL {
              self.profileImage.image = image
            }
          }
        }
      }
    } else {
      lastPhotoURL = nil
      self.profileImage.image = nil
    }
    updateControls()
  }

  // Updates the states of the UI controls.
  fileprivate func updateControls() {
    let action: Action
    switch actionType {
    case .auth:
      action = authAction
    case .user:
      action = userAction
    }
    let isCredentialEnabled = action.requiresCredential
    credentialTypePicker.isUserInteractionEnabled = isCredentialEnabled
    credentialTypePicker.alpha = isCredentialEnabled ? 1.0 : 0.6
    let isEmailEnabled = isCredentialEnabled && credentialType.requiresEmail || action.requiresEmail
    emailInputLabel.alpha = isEmailEnabled ? 1.0 : 0.6
    emailField.isEnabled = isEmailEnabled
    let isPasswordEnabled = isCredentialEnabled && credentialType.requiresPassword ||
        action.requiresPassword
    passwordInputLabel.alpha = isPasswordEnabled ? 1.0 : 0.6
    passwordField.isEnabled = isPasswordEnabled
  }

  fileprivate func showAlert(title: String, message: String? = "") {
    UIAlertView(title: title, message: message ?? "(NULL)", delegate: nil, cancelButtonTitle: nil,
                otherButtonTitles: "OK").show()
  }

  private func ifNoError(_ error: Error?, execute: () -> Void) {
    guard error == nil else {
      showAlert(title: "Error", message: error!.localizedDescription)
      return
    }
    execute()
  }
}

extension ViewController : GIDSignInUIDelegate {
  func sign(_ signIn: GIDSignIn!, present viewController: UIViewController!) {
    present(viewController, animated: true, completion: nil)
  }

  func sign(_ signIn: GIDSignIn!, dismiss viewController: UIViewController!) {
    dismiss(animated: true, completion: nil)
  }
}

extension ViewController : UIPickerViewDataSource {
  func numberOfComponents(in pickerView: UIPickerView) -> Int {
    return 1
  }

  func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
    switch pickerView {
    case actionTypePicker:
      if Auth.auth().currentUser != nil {
        return ActionType.countWithUser
      } else {
        return ActionType.countWithoutUser
      }
    case actionPicker:
      switch actionType {
        case .auth:
          return AuthAction.count
        case .user:
          return UserAction.count
      }
    case credentialTypePicker:
      return CredentialType.count
    default:
      return 0
    }
  }
}

extension ViewController : UIPickerViewDelegate {
  func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int)
      -> String? {
    switch pickerView {
    case actionTypePicker:
      return ActionType(rawValue: row)!.text
    case actionPicker:
      switch actionType {
      case .auth:
        return AuthAction(rawValue: row)!.text
      case .user:
        return UserAction(rawValue: row)!.text
      }
    case credentialTypePicker:
      return CredentialType(rawValue: row)!.text
    default:
      return nil
    }
  }

  func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
    switch pickerView {
    case actionTypePicker:
      actionType = ActionType(rawValue: row)!
    case actionPicker:
      switch actionType {
      case .auth:
        authAction = AuthAction(rawValue: row)!
      case .user:
        userAction = UserAction(rawValue: row)!
      }
    case credentialTypePicker:
      credentialType = CredentialType(rawValue: row)!
    default:
      break
    }
    updateControls()
  }
}

/// An adapter class to pass GoogleSignIn delegate method to a block.
fileprivate final class GoogleSignInDelegate: NSObject, GIDSignInDelegate {

  private let completion: (GIDGoogleUser?, Error?) -> Void
  private var retainedSelf: GoogleSignInDelegate?

  init(completion: @escaping (GIDGoogleUser?, Error?) -> Void) {
    self.completion = completion
    super.init()
    retainedSelf = self
  }

  func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser?, withError error: Error?) {
    completion(user, error)
    retainedSelf = nil
  }
}

/// The list of all possible action types.
fileprivate enum ActionType: Int {

  case auth, user

  // Count of action types when no user is signed in.
  static var countWithoutUser: Int {
    return ActionType.auth.rawValue + 1
  }

  // Count of action types when a user is signed in.
  static var countWithUser: Int {
    return ActionType.user.rawValue + 1
  }

  /// The text description for a particular enum value.
  var text : String {
    switch self {
    case .auth:
      return "Auth"
    case .user:
      return "User"
    }
  }
}

fileprivate protocol Action {
  /// The text description for the particular action.
  var text: String { get }

  /// Whether or not the action requires credential.
  var requiresCredential : Bool { get }

  /// Whether or not the action requires email.
  var requiresEmail: Bool { get }

  /// Whether or not the credential requires password.
  var requiresPassword: Bool { get }
}

/// The list of all possible actions the operator can take on the Auth object.
fileprivate enum AuthAction: Int, Action {

  case fetchProviderForEmail, signInAnonymously, signInWithCredential, createUser, signOut

  /// Total number of auth actions.
  static var count: Int {
    return AuthAction.signOut.rawValue + 1
  }

  var text : String {
    switch self {
    case .fetchProviderForEmail:
      return "Fetch Provider ⬇️"
    case .signInAnonymously:
      return "Sign In Anonymously"
    case .signInWithCredential:
      return "Sign In w/ Credential ↙️"
    case .createUser:
      return "Create User ⬇️"
    case .signOut:
      return "Sign Out"
    }
  }

  var requiresCredential : Bool {
    return self == .signInWithCredential
  }

  var requiresEmail : Bool {
    return self == .fetchProviderForEmail || self == .createUser
  }

  var requiresPassword : Bool {
    return self == .createUser
  }
}

/// The list of all possible actions the operator can take on the User object.
fileprivate enum UserAction: Int, Action {

  case updateEmail, updatePassword, reload, reauthenticate, getToken, linkWithCredential,
       deleteAccount

  /// Total number of user actions.
  static var count: Int {
    return UserAction.deleteAccount.rawValue + 1
  }

  var text : String {
    switch self {
    case .updateEmail:
      return "Update Email ⬇️"
    case .updatePassword:
      return "Update Password ⬇️"
    case .reload:
      return "Reload"
    case .reauthenticate:
      return "Reauthenticate ↙️"
    case .getToken:
      return "Get Token"
    case .linkWithCredential:
      return "Link With Credential ↙️"
    case .deleteAccount:
      return "Delete Account"
    }
  }

  var requiresCredential : Bool {
    return self == .reauthenticate ||  self == .linkWithCredential
  }

  var requiresEmail : Bool {
    return self == .updateEmail
  }

  var requiresPassword : Bool {
    return self == .updatePassword
  }
}

/// The list of all possible credential types the operator can use to sign in or link.
fileprivate enum CredentialType: Int {

  case google, password

  /// Total number of enum values.
  static var count: Int {
    return CredentialType.password.rawValue + 1
  }

  /// The text description for a particular enum value.
  var text : String {
    switch self {
    case .google:
      return "Google"
    case .password:
      return "Password ➡️️"
    }
  }

  /// Whether or not the credential requires email.
  var requiresEmail : Bool {
    return self == .password
  }

  /// Whether or not the credential requires password.
  var requiresPassword : Bool {
    return self == .password
  }
}

fileprivate extension User {
  var textDescription: String {
    return self.displayName ?? self.email ?? self.uid
  }
}
