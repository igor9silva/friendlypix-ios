//
//  Copyright (c) 2017 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Firebase
import FirebaseAuthUI
import FirebaseFacebookAuthUI
import FirebaseGoogleAuthUI
import GoogleSignIn
import MaterialComponents
import UserNotifications

private let kFirebaseTermsOfService = URL(string: "https://firebase.google.com/terms/")!

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  let mdcMessage = MDCSnackbarMessage()
  let mdcAction = MDCSnackbarMessageAction()
  var window: UIWindow?
  let gcmMessageIDKey = "gcm.message_id"
  var notificationGranted = false

  func application(_ application: UIApplication, didFinishLaunchingWithOptions
    launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    FirebaseApp.configure()
    Messaging.messaging().delegate = self
    if #available(iOS 10.0, *) {
      // For iOS 10 display notification (sent via APNS)
      UNUserNotificationCenter.current().delegate = self

      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { granted, _ in
          if granted {
            if let uid = Auth.auth().currentUser?.uid {
              Database.database().reference().child("people/\(uid)/notificationEnabled").setValue(true)
            } else {
              self.notificationGranted = true
            }
          }
      })
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }

    application.registerForRemoteNotifications()

    let authUI = FUIAuth.defaultAuthUI()
    authUI?.delegate = self
    authUI?.tosurl = kFirebaseTermsOfService
    authUI?.isSignInWithEmailHidden = true
    let providers: [FUIAuthProvider] = [FUIGoogleAuth(), FUIFacebookAuth()]
    authUI?.providers = providers

    return true
  }

  func showAlert(_ userInfo: [AnyHashable: Any]) {
    let apsKey = "aps"
    let gcmMessage = "alert"
    let gcmLabel = "google.c.a.c_l"
    if let aps = userInfo[apsKey] as? [String: String], !aps.isEmpty, let message = aps[gcmMessage],
      let label = userInfo[gcmLabel] as? String {
      mdcMessage.text = "\(label): \(message)"
      MDCSnackbarManager.show(mdcMessage)
    }
  }

  func showContent(_ content: UNNotificationContent) {
    mdcMessage.text = content.body
    mdcAction.title = content.title
    mdcMessage.duration = 10_000
    mdcAction.handler = {
      guard let feed = self.window?.rootViewController?.childViewControllers[0] as? FPFeedViewController else { return }
      let userId = content.categoryIdentifier.components(separatedBy: "/user/")[1]
      feed.showProfile(FPUser(dictionary: ["uid": userId]))
    }
    mdcMessage.action = mdcAction
    MDCSnackbarManager.show(mdcMessage)
  }

  @available(iOS 9.0, *)
  func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey: Any]) -> Bool {
    guard let sourceApplication = options[UIApplicationOpenURLOptionsKey.sourceApplication] as? String else {
      return false
    }
    return self.handleOpenUrl(url, sourceApplication: sourceApplication)
  }

  @available(iOS 8.0, *)
  func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
    return self.handleOpenUrl(url, sourceApplication: sourceApplication)
  }

  func handleOpenUrl(_ url: URL, sourceApplication: String?) -> Bool {
    if FUIAuth.defaultAuthUI()?.handleOpen(url, sourceApplication: sourceApplication) ?? false {
      return true
    }
    return GIDSignIn.sharedInstance().handle(url, sourceApplication: sourceApplication, annotation: nil)
  }

  func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
    // If you are receiving a notification message while your app is in the background,
    // this callback will not be fired till the user taps on the notification launching the application.
    showAlert(userInfo)
  }

  func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                   fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // If you are receiving a notification message while your app is in the background,
    // this callback will not be fired till the user taps on the notification launching the application.
    showAlert(userInfo)
    completionHandler(.newData)
  }
}

extension AppDelegate: FUIAuthDelegate {
  func authUI(_ authUI: FUIAuth, didSignInWith authDataResult: AuthDataResult?, error: Error?) {
    switch error {
    case .some(let error as NSError) where UInt(error.code) == FUIAuthErrorCode.userCancelledSignIn.rawValue:
      print("User cancelled sign-in")
    case .some(let error as NSError) where error.userInfo[NSUnderlyingErrorKey] != nil:
      print("Login error: \(error.userInfo[NSUnderlyingErrorKey]!)")
    case .some(let error):
      print("Login error: \(error.localizedDescription)")
    case .none:
      if let user = authDataResult?.user {
        signed(in: user)
      }
    }
  }

  func authPickerViewController(forAuthUI authUI: FUIAuth) -> FUIAuthPickerViewController {
    return FPAuthPickerViewController(nibName: "FPAuthPickerViewController", bundle: Bundle.main, authUI: authUI)
  }

  func signed(in user: User) {
    var values: [String: Any] = ["profile_picture": user.photoURL?.absoluteString ?? "",
                                 "full_name": user.displayName ?? "",
                                 "_search_index": ["full_name": user.displayName?.lowercased(),
                                                   "reversed_full_name": user.displayName?.components(separatedBy: " ")
                                                    .reversed().joined(separator: "")]]
    if notificationGranted {
      values["notificationEnabled"] = true
      notificationGranted = false
    }
    Database.database().reference(withPath: "people/\(user.uid)")
      .updateChildValues(values)
  }
}

@available(iOS 10, *)
extension AppDelegate: UNUserNotificationCenterDelegate {

  // Receive displayed notifications for iOS 10 devices.
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
    showContent(notification.request.content)
    completionHandler([])
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    showContent(response.notification.request.content)
    completionHandler()
  }
}

extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    Database.database().reference(withPath: "/people/\(uid)/notificationTokens/\(fcmToken)").setValue(true)
  }

  // Receive data messages on iOS 10+ directly from FCM (bypassing APNs) when the app is in the foreground.
  // To enable direct data messages, you can set Messaging.messaging().shouldEstablishDirectChannel to true.
  func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
    let data = remoteMessage.appData
    showAlert(data)
  }
}
