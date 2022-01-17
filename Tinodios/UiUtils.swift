//
//  UiUtils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Firebase
import Foundation
import TinodiosDB
import TinodeSDK

public typealias ScalingData = (dst: CGSize, src: CGRect, altered: Bool)

class UiTinodeEventListener: TinodeEventListener {
    private var connected: Bool = false

    init(connected: Bool) {
        self.connected = connected
    }
    func onConnect(code: Int, reason: String, params: [String: JSONValue]?) {
        connected = true
    }
    func onDisconnect(byServer: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String) {
        if connected {
            // If we just got disconnected, display the connection lost message.
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("Connection to server lost.", comment: "Toast notification"))
            }
        }
        connected = false
    }
    func onLogin(code: Int, text: String) {}
    func onMessage(msg: ServerMessage?) {}
    func onRawMessage(msg: String) {}
    func onCtrlMessage(ctrl: MsgServerCtrl?) {}
    func onDataMessage(data: MsgServerData?) {}
    func onInfoMessage(info: MsgServerInfo?) {}
    func onMetaMessage(meta: MsgServerMeta?) {}
    func onPresMessage(pres: MsgServerPres?) {}
}

// Calculates attributed string size (bounding rectangle) with with specified width.
// Can't use AttributedString.boundingRect(with CGSize) per
// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Tasks/StringHeight.html
class TextSizeHelper {
    private let textStorage: NSTextStorage
    private let textContainer: NSTextContainer
    private let layoutManager: NSLayoutManager

    init() {
        textStorage = NSTextStorage()
        textContainer = NSTextContainer()
        layoutManager = NSLayoutManager()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    public func computeSize(for attributedText: NSAttributedString,
                            within maxWidth: CGFloat) -> CGSize {
        textStorage.setAttributedString(attributedText)
        textContainer.size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        return layoutManager.usedRect(for: textContainer).integral.size
    }
}

enum ToastLevel {
    case error, warning, info
}

class UiUtils {
    static let kMinTagLength: Int64 = 4
    static let kMaxTagLength: Int64 = 96

    static let kAvatarSize: CGFloat = 128
    // Maximum linear size of an image.
    static let kMaxBitmapSize: CGFloat = 1024
    // Maximum size of image preview when image is sent out-of-band.
    static let kImagePreviewDimensions: CGFloat = 64
    // Default dimensions of a bitmap when the sender provided none.
    static let kDefaultBitmapSize: CGFloat = 256
    // Maximum length of topic title or user name.
    static let kMaxTitleLength = 60

    // Color of "read" delivery marker.
    static let kDeliveryMarkerTint = UIColor(red: 19/255, green: 144/255, blue: 255/255, alpha: 0.8)
    // Color of all other markers.
    static let kDeliveryMarkerColor = UIColor.gray.withAlphaComponent(0.7)

    // Maximum length of the quoted part in a reply.
    static let kQuotedReplyLength = 30
    // Size of image thumbnails in the quoted part in a reply.
    static let kReplyThumbnailSize = 36
    // Max file name (e.g. image file names) length to display in previews and quotes.
    static let kPreviewMaxFileNameLength = 16
    // Max length of message previews.
    static let kPreviewLength = 42

    // Letter tile image colors (light).
    private static let kLetterTileLightColors: [UIColor] = [
        UIColor(fromHexCode: 0xFFEF9A9A),
        UIColor(fromHexCode: 0xFF90CAF9),
        UIColor(fromHexCode: 0xFFB0BEC5),
        UIColor(fromHexCode: 0xFFB39DDB),
        UIColor(fromHexCode: 0xFFFFAB91),
        UIColor(fromHexCode: 0xFFA5D6A7),
        UIColor(fromHexCode: 0xFFDDDDDD),
        UIColor(fromHexCode: 0xFFE6EE9C),
        UIColor(fromHexCode: 0xFFC5E1A5),
        UIColor(fromHexCode: 0xFFFFF59D),
        UIColor(fromHexCode: 0xFFF48FB1),
        UIColor(fromHexCode: 0xFF9FA8DA),
        UIColor(fromHexCode: 0xFFFFE082),
        UIColor(fromHexCode: 0xFFBCAAA4),
        UIColor(fromHexCode: 0xFF80DEEA),
        UIColor(fromHexCode: 0xFFCE93D8)
    ]

    // Letter tile image colors (dark).
    private static let kLetterTileDarkColors: [UIColor] = [
        UIColor(fromHexCode: 0xFFC62828),
        UIColor(fromHexCode: 0xFFAD1457),
        UIColor(fromHexCode: 0xFF6A1B9A),
        UIColor(fromHexCode: 0xFF4527A0),
        UIColor(fromHexCode: 0xFF283593),
        UIColor(fromHexCode: 0xFF1565C0),
        UIColor(fromHexCode: 0xFF0277BD),
        UIColor(fromHexCode: 0xFF00838F),
        UIColor(fromHexCode: 0xFF00695C),
        UIColor(fromHexCode: 0xFF2E7D32),
        UIColor(fromHexCode: 0xFF558B2F),
        UIColor(fromHexCode: 0xFF9E9D24),
        UIColor(fromHexCode: 0xFFF9A825),
        UIColor(fromHexCode: 0xFFFF8F00),
        UIColor(fromHexCode: 0xFFEF6C00),
        UIColor(fromHexCode: 0xFFD84315)
    ]

    private static let kDefaultLetterTileLightColor = UIColor(fromHexCode: 0xFF9E9E9E)
    private static let kDefaultLetterTileDarkColor = UIColor(fromHexCode: 0xFF757575)

    public static func letterTileColor(for uid: String, dark: Bool) -> UIColor {
        let colors = dark ? UiUtils.kLetterTileDarkColors : UiUtils.kLetterTileLightColors

        let hash = UInt(uid.hashCode().magnitude)
        if hash == 0 {
            return dark ? UiUtils.kDefaultLetterTileDarkColor : UiUtils.kDefaultLetterTileLightColor
        }
        return colors[Int(hash % UInt(colors.count))]
    }

    private static func setUpPushNotifications() {
        let application = UIApplication.shared
        let appDelegate = application.delegate as! AppDelegate
        guard !appDelegate.pushNotificationsConfigured else {
            Messaging.messaging().token { (token, error) in
                if let error = error {
                    Cache.log.debug("Error fetching FCM registration token: %@", error.localizedDescription)
                } else if let token = token {
                    Cache.tinode.setDeviceToken(token: token)
                }
            }
            return
        }

        // Configure FCM.
        FirebaseApp.configure()
        Messaging.messaging().delegate = appDelegate
        UNUserNotificationCenter.current().delegate = appDelegate

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: {_, _ in })

        application.registerForRemoteNotifications()
        appDelegate.pushNotificationsConfigured = true
    }

    public static func attachToMeTopic(meListener: DefaultMeTopic.Listener?) -> PromisedReply<ServerMessage>? {
        let tinode = Cache.tinode
        var me = tinode.getMeTopic()
        if me == nil {
            me = DefaultMeTopic(tinode: tinode, l: meListener)
        } else {
            me!.listener = meListener
        }
        let get = me!.metaGetBuilder().withCred().withDesc().withSub().withTags().build()
        return me!.subscribe(set: nil, get: get)
            .thenCatch({ err in
                Cache.log.error("ME topic subscription error: %@", err.localizedDescription)
                if let e = err as? TinodeError {
                    if case TinodeError.serverResponseError(let code, let text, _) = e {
                        switch code {
                        case 404:
                            UiUtils.logoutAndRouteToLoginVC()
                        case 502:
                            if text == "cluster unreachable" {
                                Cache.tinode.reconnectNow(interactively: false, reset: true)
                            }
                        default:
                            break
                        }
                    }
                }
                return nil
            })
    }
    public static func attachToFndTopic(fndListener: DefaultFndTopic.Listener?) -> PromisedReply<ServerMessage>? {
        let tinode = Cache.tinode
        let fnd = tinode.getOrCreateFndTopic()
        fnd.listener = fndListener
        return !fnd.attached ?
            fnd.subscribe(set: nil, get: nil) :
            PromisedReply<ServerMessage>(value: ServerMessage())
    }

    public static func logoutAndRouteToLoginVC() {
        Cache.log.info("UiUtils - Invalidating cache and logging out.")
        BaseDb.sharedInstance.logout()
        Cache.invalidate()
        SharedUtils.removeAuthToken()
        UiUtils.routeToLoginVC()
    }

    private static func routeToLoginVC() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let destinationVC = storyboard.instantiateViewController(withIdentifier: "StartNavigator") as! UINavigationController

            if let window = UIApplication.shared.keyWindow {
                window.rootViewController = destinationVC
            }
        }
    }

    public static func routeToCredentialsVC(in navVC: UINavigationController?, verifying meth: String?) {
        guard let navVC = navVC else { return }
        // +1 second to let the spinning wheel dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let destinationVC = storyboard.instantiateViewController(withIdentifier: "CredentialsViewController") as! CredentialsViewController
            destinationVC.meth = meth
            navVC.pushViewController(destinationVC, animated: true)
        }
    }

    public static func routeToChatListVC() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let initialViewController =
                storyboard.instantiateViewController(
                    withIdentifier: "ChatsNavigator") as! UINavigationController
            if let window = UIApplication.shared.keyWindow {
                window.rootViewController = initialViewController
            }
            UiUtils.setUpPushNotifications()
        }
    }

    private static func isShowingChatListVC() -> Bool {
        guard let rootVC = UIApplication.shared.keyWindow?.rootViewController as? UINavigationController else {
            return false
        }
        return rootVC.viewControllers.contains(where: { $0 is ChatListViewController })
    }

    public static func routeToMessageVC(forTopic topicId: String) {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)

            var shouldReplaceRootVC = true
            var rootVC: UINavigationController
            if isShowingChatListVC() {
                rootVC = UIApplication.shared.keyWindow!.rootViewController as! UINavigationController
                // The app is in the foreground.
                while !(rootVC.topViewController is ChatListViewController) {
                    rootVC.popViewController(animated: false)
                }
                shouldReplaceRootVC = false
            } else {
                rootVC = storyboard.instantiateViewController(
                    withIdentifier: "ChatsNavigator") as! UINavigationController
            }
            let messageViewController =
                storyboard.instantiateViewController(
                    withIdentifier: "MessageViewController") as! MessageViewController
            messageViewController.topicName = topicId
            rootVC.pushViewController(messageViewController, animated: false)
            if let window = UIApplication.shared.keyWindow, shouldReplaceRootVC {
                window.rootViewController = rootVC
            }
            UiUtils.setUpPushNotifications()
        }
    }

    // Get text from UITextField or mark the field red if the field is blank
    public static func ensureDataInTextField(_ field: UITextField, maxLength: Int = -1) -> String {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            markTextFieldAsError(field)
            return ""
        }
        return maxLength > 0 ? String(text.prefix(maxLength)) : text
    }

    public static func markTextFieldAsError(_ field: UITextField) {
        let imageView = UIImageView(image: UIImage(named: "important-32"))
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        imageView.tintColor = .red
        // Padding around the icon
        let padding: CGFloat = 4
        // Create the view that would act as the padding
        let rightView = UIView(frame: CGRect(x: 0, y: 0, // keep this as 0, 0
            width: imageView.frame.width + padding, height: imageView.frame.height))
        rightView.addSubview(imageView)
        field.rightViewMode = .always
        field.rightView = rightView
    }
    public static func clearTextFieldError(_ field: UITextField) {
        field.rightViewMode = .never
        field.rightView = nil
    }

    public static func bytesToHumanSize(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return "0 Bytes"
        }

        // Not that GB+ are likely to be used ever, just making sure sizes[bucket] does not crash on large values.
        let sizes = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB"]
        let bucket = (63 - bytes.leadingZeroBitCount) / 10
        let count: Double = Double(bytes) / Double(pow(1024, Double(bucket)))
        // Multiplier for rounding fractions.
        let roundTo: Int = bucket > 0 ? (count < 3 ? 2 : (count < 30 ? 1 : 0)) : 0
        let multiplier: Double = pow(10, Double(roundTo))
        let whole: Int = Int(count)
        let fraction: String = roundTo > 1 ? "." + "\(Int(round(count * multiplier)))".suffix(roundTo) : ""
        return "\(whole)\(fraction) \(sizes[bucket])"
    }

    /// Displays bottom pannel with an error message.
    /// - Parameters:
    ///  - message: message to display
    ///  - duration: duration of display in seconds.
    public static func showToast(message: String, duration: TimeInterval = 3.0, level: ToastLevel = .error) {
        // Grab the last window (instead the key window) so we can show
        // the toast over they keyboard when it's presented.
        guard let parent = UIApplication.shared.windows.last else {
            Cache.log.error("UiUtils.showToast - parent window not set")
            return
        }

        let iconSize: CGFloat = 32
        let spacing: CGFloat = 8
        let minMessageHeight = iconSize + spacing * 2
        let maxMessageHeight: CGFloat = 100

        // Prevent very short toasts
        guard duration > 0.5 else { return }

        var settings: (color: UInt, bgColor: UInt, icon: String)
        switch level {
        case .error: settings = (color: 0xFFFFFFFF, bgColor: 0xFFFF6666, icon: "important-32")
        case .warning: settings = (color: 0xFF666633, bgColor: 0xFFFFFFCC, icon: "warning-32")
        case .info: settings = (color: 0xFF333366, bgColor: 0xFFCCCCFF, icon: "info-32")
        }
        let icon = UIImageView(image: UIImage(named: settings.icon))
        icon.tintColor = UIColor(fromHexCode: settings.color)
        icon.frame = CGRect(x: spacing, y: spacing, width: iconSize, height: iconSize)

        let label = UILabel()
        label.textColor = UIColor(fromHexCode: settings.color)
        label.textAlignment = .left
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 3
        label.font = UIFont.preferredFont(forTextStyle: .callout)
        label.text = message
        label.alpha = 1.0
        let maxLabelWidth = parent.frame.width - spacing * 3 - iconSize

        let labelBounds = label.textRect(forBounds: CGRect(x: 0, y: 0, width: maxLabelWidth, height: CGFloat.greatestFiniteMagnitude), limitedToNumberOfLines: label.numberOfLines)
        label.frame = CGRect(
            x: iconSize + spacing * 2, y: spacing + (iconSize - label.font.lineHeight) * 0.5,
            width: labelBounds.width, height: labelBounds.height)

        let toastView = UIView()
        toastView.alpha = 0
        toastView.backgroundColor = UIColor(fromHexCode: settings.bgColor)
        toastView.addSubview(icon)
        toastView.addSubview(label)

        parent.addSubview(toastView)
        label.sizeToFit()

        var toastHeight = max(min(label.frame.height + spacing * 3, maxMessageHeight), minMessageHeight)
        toastHeight += parent.safeAreaInsets.bottom

        toastView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 0),
            toastView.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: 0),
            toastView.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: toastHeight),
            toastView.heightAnchor.constraint(equalToConstant: toastHeight)
            ])

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
            toastView.alpha = 1
            toastView.transform = CGAffineTransform(translationX: 0, y: -toastHeight)
        }, completion: {(isCompleted) in
            UIView.animate(withDuration: 0.2, delay: duration-0.4, options: .curveEaseIn, animations: {
                toastView.alpha = 0
            }, completion: {(_) in
                toastView.removeFromSuperview()
            })
        })
    }
    public static func setupTapRecognizer(forView view: UIView, action: Selector?, actionTarget: UIViewController) {
        let tap = UITapGestureRecognizer(target: actionTarget, action: action)
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tap)
    }
    public static func dismissKeyboardForTaps(onView view: UIView) {
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    @discardableResult
    public static func ToastFailureHandler(err: Error) -> PromisedReply<ServerMessage>? {
        DispatchQueue.main.async {
            if let e = err as? TinodeError, case .notConnected = e {
                UiUtils.showToast(message: NSLocalizedString("You are offline.", comment: "Toast notification"))
            } else {
                UiUtils.showToast(message: String(format: NSLocalizedString("Action failed: %@", comment: "Toast notification"), err.localizedDescription))
            }
        }
        return nil
    }
    @discardableResult
    public static func ToastSuccessHandler(msg: ServerMessage?) -> PromisedReply<ServerMessage>? {
        if let ctrl = msg?.ctrl, ctrl.code >= 300 {
            DispatchQueue.main.async {
                UiUtils.showToast(message: String(format: NSLocalizedString("Something went wrong: %d (%s)", comment: "Toast notification"), ctrl.code, ctrl.text), level: .warning)
            }
        }
        return nil
    }
    public static func showPermissionsEditDialog(over viewController: UIViewController?, acs: AcsHelper, callback: PermissionsEditViewController.ChangeHandler?, disabledPermissions: String?) {
        let alertVC = PermissionsEditViewController(set: acs.description, disabled: disabledPermissions, changeHandler: callback)
        alertVC.show(over: viewController)
    }

    public enum PermissionsChangeType {
        case updateSelfSub, updateSub, updateAuth, updateAnon
    }

    @discardableResult
    public static func handlePermissionsChange(onTopic topic: DefaultTopic, forUid uid: String?, changeType: PermissionsChangeType, newPermissions: String)
        -> PromisedReply<ServerMessage>? {
        var reply: PromisedReply<ServerMessage>?
        switch changeType {
        case .updateSelfSub:
            reply = topic.updateMode(uid: nil, update: newPermissions)
        case .updateSub:
            reply = topic.updateMode(uid: uid, update: newPermissions)
        case .updateAuth:
            reply = topic.updateDefacs(auth: newPermissions, anon: nil)
        case .updateAnon:
            reply = topic.updateDefacs(auth: nil, anon: newPermissions)
        }
        return reply?.then(
            onSuccess: { msg in
                if let ctrl = msg?.ctrl, ctrl.code >= 300 {
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: String(format: NSLocalizedString("Permissions not modified: %d (%s)", comment: "Toast notification"), ctrl.code, ctrl.text), level: .warning)
                    }
                }
                return nil
            },
            onFailure: { err in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: String(format: NSLocalizedString("Error changing permissions: %@", comment: "Toast notification"), err.localizedDescription))
                }
                return nil
            })
    }
    @discardableResult
    public static func updateAvatar(forTopic topic: DefaultTopic, image: UIImage) -> PromisedReply<ServerMessage>? {
        let pub = topic.pub == nil ? VCard(fn: nil, avatar: image) : topic.pub!.copy()
        pub.photo = Photo(image: image)
        return UiUtils.setTopicData(forTopic: topic, pub: pub, priv: nil)
    }
    @discardableResult
    public static func setTopicData(
        forTopic topic: DefaultTopic, pub: VCard?, priv: PrivateType?) -> PromisedReply<ServerMessage>? {
        return topic.setDescription(pub: pub, priv: priv).then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: UiUtils.ToastFailureHandler)
    }

    public static func topViewController(rootViewController: UIViewController?) -> UIViewController? {
        guard let rootViewController = rootViewController else { return nil }
        guard let presented = rootViewController.presentedViewController else {
            return rootViewController
        }
        switch presented {
        case let navigationController as UINavigationController:
            return topViewController(rootViewController: navigationController.viewControllers.last)
        case let tabBarController as UITabBarController:
            return topViewController(rootViewController: tabBarController.selectedViewController)
        default:
            return topViewController(rootViewController: presented)
        }
    }

    public static func presentFileSharingVC(for fileUrl: URL) {
        DispatchQueue.main.async {
            let filesToShare = [fileUrl]
            let activityViewController = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)
            let topVC = UiUtils.topViewController(
                rootViewController: UIApplication.shared.keyWindow?.rootViewController)
            topVC?.present(activityViewController, animated: true, completion: nil)
        }
    }

    public static func toggleProgressOverlay(in parent: UIViewController, visible: Bool, title: String? = nil) {
        DispatchQueue.main.async {
            if visible {
                let alert = UIAlertController(title: nil, message: title ?? NSLocalizedString("Please wait...", comment: "Progress overlay"), preferredStyle: .alert)

                let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
                loadingIndicator.hidesWhenStopped = true
                loadingIndicator.style = UIActivityIndicatorView.Style.medium
                loadingIndicator.startAnimating()

                alert.view.addSubview(loadingIndicator)
                parent.present(alert, animated: true, completion: nil)
            } else if let vc = parent.presentedViewController, vc is UIAlertController {
                parent.dismiss(animated: false, completion: nil)
            }
        }
    }

    public static func presentManageTagsEditDialog(over viewController: UIViewController,
                                                   forTopic topic: TopicProto?) {
        // Topic<VCard, PrivateType, VCard, PrivateType> is the least common ancestor for
        // DefaultMeTopic (AccountSettingsVC) and DefaultComTopic (TopicInfoVC).
        guard let topic = topic as? Topic<VCard, PrivateType, VCard, PrivateType> else { return }
        guard let tags = topic.tags else {
            DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Tags missing.", comment: "Toast notification"))}
            return
        }
        let alert = TagsEditDialogViewController(with: tags)
        alert.completionHandler = { newTags in
            topic.setMeta(meta: MsgSetMeta(desc: nil, sub: nil, tags: newTags, cred: nil))
                .thenCatch(UiUtils.ToastFailureHandler)
        }
        alert.show(over: viewController)
    }

    // Sets tint color on the password visibility switch buttons.
    public static func adjustPasswordVisibilitySwitchColor(for switches: [UIButton], setColor color: UIColor) {
        switches.forEach {
            $0.tintColor = color
            $0.setImage($0.imageView?.image?.withRenderingMode(.alwaysTemplate), for: .normal)
        }
    }

    /// Generate image of a given size with an icon in the ceneter.
    public static func placeholderImage(named: String, withBackground bg: UIImage?, width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        let icon = UIImage(named: named)!
        let result = UiUtils.sizeUnder(original: CGSize(width: 24 * icon.scale, height: 24 * icon.scale), fitUnder: size, scale: 1, clip: false)
        let iconSize = result.dst
        let dx = (size.width - iconSize.width) * 0.5
        let dy = (size.height - iconSize.height) * 0.5

        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            // Draw solid gray background
            UIColor.secondarySystemBackground.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))

            // Draw semi-transparent background image, if available.
            if let bg = bg {
                bg.draw(in: CGRect(x: 0, y: 0, width: width, height: height), blendMode: .normal, alpha: 0.35)
            }

            // Draw icon.
            UIColor.secondaryLabel.setFill()
            icon.draw(in: CGRect(x: dx, y: dy, width: iconSize.width, height: iconSize.height))
        }
    }

    /// Calculate physical (not logical, i.e. UIImage.scale is factored in) linear dimensions
    /// for scaling image down to fit under a certain size.
    ///
    /// - Parameters:
    ///     - width: width of the original image
    ///     - height: height of the original image
    ///     - maxWidth: maximum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - scale: image scaling factor
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    /// - Returns:
    ///     a tuple which contains destination image sizes, source sizes and offsets
    ///     into source (when 'clip' is true), an indicator that the new dimensions are different
    ///     from the original.
    public static func sizeUnder(original: CGSize, fitUnder: CGSize, scale: CGFloat, clip: Bool) -> ScalingData {
        // Sanity check
        assert(fitUnder.width > 0 && fitUnder.height > 0 && scale > 0, "Maxumum dimensions must be positive")

        let originalWidth = CGFloat(original.width * scale)
        let originalHeight = CGFloat(original.height * scale)

        // scale? is [0,1): ~0 - very large original, =1: under the limits already.
        let scaleX = min(originalWidth, fitUnder.width) / originalWidth
        let scaleY = min(originalHeight, fitUnder.height) / originalHeight
        // How much to scale the image
        let scale = clip ?
            // Scale as little as possible (large 'scale' == little change): only one dimension is below the limit, clip the other dimension; the image will have the new aspect ratio.
            max(scaleX, scaleY) :
            // Both width and height are below the limits: no clipping will occur, the image will keep the original aspect ratio.
            min(scaleX, scaleY)

        let dstSize = CGSize(width: max(1, min(fitUnder.width, originalWidth * scale)), height: max(1, min(fitUnder.height, originalHeight * scale)))

        let srcWidth = max(1, dstSize.width / scale)
        let srcHeight = max(1, dstSize.height / scale)

        return (
            dst: dstSize,
            src: CGRect(
                x: 0.5 * (originalWidth - srcWidth),
                y: 0.5 * (originalHeight - srcHeight),
                width: srcWidth,
                height: srcHeight
            ),
            altered: originalWidth != dstSize.width || originalHeight != dstSize.height
        )
    }

    public static func deliveryMarkerIcon(for message: Message, in topic: DefaultComTopic) -> (UIImage, UIColor) {
        let iconName: String
        var tint: UIColor = UiUtils.kDeliveryMarkerColor

        if message.isPending {
            iconName = "in-progress-30"
        } else {
            if topic.msgReadCount(seq: message.seqId) > 0 {
                iconName = "done-all-30"
                tint = UiUtils.kDeliveryMarkerTint
            } else if topic.msgRecvCount(seq: message.seqId) > 0 {
                iconName = "done-all-30"
            } else {
                iconName = "done-30"
            }
        }

        return (UIImage(named: iconName)!, tint)
    }

    // Returns a shortened version of the file name.
    public static func previewFileName(from original: String) -> String {
        guard original.count > UiUtils.kPreviewMaxFileNameLength else { return original }
        let len = UiUtils.kPreviewMaxFileNameLength / 2
        return original.prefix(len) + "…" + original.suffix(len)
    }
}

extension UIViewController {
    // Opens a chat with the specified topic name after popping all items from the current navigation stack.
    public func presentChatReplacingCurrentVC(with topicName: String, afterDelay delay: DispatchTimeInterval = .seconds(0), initializationCallback: ((UIViewController) -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let navController = self.navigationController {
                navController.popToRootViewController(animated: false)

                let messageVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MessageViewController") as! MessageViewController
                messageVC.topicName = topicName
                initializationCallback?(messageVC)
                navController.pushViewController(messageVC, animated: true)
            }
        }
    }
}

extension UITableViewController {
    func resolveNavbarOverlapConflict() {
        // In iOS 9, UITableViewController.tableView overlaps with the navbar
        // when the latter is declared in the tabController.
        // Resolve this issue.
        if let rect = self.tabBarController?.navigationController?.navigationBar.frame {
            let y = rect.size.height + rect.origin.y
            let shift = UIEdgeInsets(top: y, left: 0, bottom: 0, right: 0)
            self.tableView.scrollIndicatorInsets = shift
            self.tableView.contentInset = shift
        }
    }
}

extension UIImage {
    private static let kScaleFactor: CGFloat = 0.70710678118 // 1.0/SQRT(2)

    private static func resizeImage(image: UIImage, newSize size: ScalingData) -> UIImage? {
        // cropRect for cropping the original image to the required aspect ratio.
        let cropRect = size.src
        let scaleDown = CGAffineTransform(scaleX: size.dst.width / size.src.width, y: size.dst.width / size.src.width)

        // Scale image to the requested dimentions
        guard let imageOut = CIImage(image: image)?.cropped(to: cropRect).transformed(by: scaleDown) else { return nil }

        // This 'UIGraphicsBeginImageContext' is some iOS weirdness. The image cannot be converted to png without it.
        UIGraphicsBeginImageContext(imageOut.extent.size)
        defer { UIGraphicsEndImageContext() }
        UIImage(ciImage: imageOut).draw(in: CGRect(origin: .zero, size: imageOut.extent.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Resize the image to given physical (i.e. device pixels, not logical pixels) dimentions.
    /// If the image does not need to be changed, return the original.
    ///
    /// - Parameters:
    ///     - maxWidth: maxumum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    public func resize(width: CGFloat, height: CGFloat, clip: Bool) -> UIImage? {
        let size = sizeUnder(CGSize(width: width, height: height), clip: clip)

        // Don't mess with image if it does not need to be scaled.
        guard size.altered else { return self }

        return UIImage.resizeImage(image: self, newSize: size)
    }

    /// Resize the image to the given bytesize keeping the original aspect ratio and format, of possible.
    public func resize(byteSize: Int, asMimeType mime: String?) -> UIImage? {
        // Sanity check
        assert(byteSize > 100, "Maxumum byte size must be more than 100 bytes")

        var image: UIImage = self
        guard var bits = image.pixelData(forMimeType: mime) else { return nil }
        while bits.count > byteSize {
            let originalWidth = CGFloat(image.size.width * image.scale)
            let originalHeight = CGFloat(image.size.height * image.scale)

            guard let newImage = UIImage.resizeImage(image: image, newSize: image.sizeUnder(CGSize(width: originalWidth * UIImage.kScaleFactor, height: originalHeight * UIImage.kScaleFactor), clip: false)) else { return nil }
            image = newImage

            guard let newBits = image.pixelData(forMimeType: mime) else { return nil }
            bits = newBits
        }

        return image
    }

    /// Calculate physical (not logical, i.e. UIImage.scale is factored in) linear dimensions
    /// for scaling image down to fit under a certain size.
    ///
    /// - Parameters:
    ///     - maxWidth: maximum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    /// - Returns:
    ///     a tuple which contains destination image sizes, source sizes and offsets
    ///     into source (when 'clip' is true), an indicator that the new dimensions are different
    ///     from the original.
    public func sizeUnder(_ size: CGSize, clip: Bool) -> ScalingData {
        return UiUtils.sizeUnder(original: CGSize(width: self.size.width, height: self.size.height), fitUnder: size, scale: self.scale, clip: clip)
    }

    public func pixelData(forMimeType mime: String?) -> Data? {
        return mime != "image/png" ? jpegData(compressionQuality: 0.8) : pngData()
    }

    // Turns image into proper upright orientation.
    public func fixedOrientation() -> UIImage? {
        guard imageOrientation != UIImage.Orientation.up else {
            // This is default orientation, don't need to do anything.
            return self
        }

        guard let cgImage = self.cgImage else {
            // CGImage is not available
            return nil
        }

        guard let colorSpace = cgImage.colorSpace, let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil // Not able to create CGContext
        }

        // We need to calculate the proper transformation to make the image upright.
        // We do it in 2 steps:
        // * Rotate if .left/.right/.down
        // * Flip if .*mirrored.
        var transform: CGAffineTransform = CGAffineTransform.identity

        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: CGFloat.pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2.0)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: CGFloat.pi / -2.0)
        case .up, .upMirrored:
            break
        @unknown default:
            fatalError("Missing image orientation...")
            break
        }

        // Flip image if needed.
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        @unknown default:
            fatalError("Missing image orientation...")
            break
        }

        ctx.concatenate(transform)

        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            break
        }

        guard let newCGImage = ctx.makeImage() else { return nil }

        return UIImage(cgImage: newCGImage, scale: 1, orientation: .up)
    }

    /// Get default iOS icon for the given file name (the file does not need to exist).
    /// It will likely return nil when running under simulator, but will likely work on a real device.
    public class func defaultIcon(forMime mime: String, preferredWidth width: CGFloat) -> UIImage? {
        let fileName = Utils.uniqueFilename(forMime: mime)
        guard let url = URL(string: "file:///\(fileName)") else { return nil }
        let ic = UIDocumentInteractionController(url: url)
        let allIcons = ic.icons

        let nearest = allIcons.enumerated().min(by: {
            return abs($0.element.size.width - width) < abs($1.element.size.width - width)
        })
        return nearest?.element
    }
}

extension UIColor {
    convenience init(fromHexCode code: UInt) {
        let blue = code & 0xff
        let green = (code >> 8) & 0xff
        let red = (code >> 16) & 0xff
        let alpha = (code >> 24) & 0xff
        self.init(red: CGFloat(Float(red) / 255.0),
                  green: CGFloat(green) / 255.0,
                  blue: CGFloat(blue) / 255.0,
                  alpha: CGFloat(alpha) / 255.0)
    }

    func lighter(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjustBrightness(by: abs(percentage) )
    }

    func darker(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjustBrightness(by: -1 * abs(percentage) )
    }

    func adjustBrightness(by percentage: CGFloat = 30.0) -> UIColor? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let delta = percentage / 100
            return UIColor(red: min(red + delta, 1.0),
                           green: min(green + delta, 1.0),
                           blue: min(blue + delta, 1.0),
                           alpha: alpha)
        } else {
            return nil
        }
    }
}

public enum UIButtonBorderSide {
    case top, bottom, left, right
}

extension UIButton {

    public func addBorder(side: UIButtonBorderSide, color: UIColor, width: CGFloat) {
        let border = CALayer()
        border.backgroundColor = color.cgColor

        switch side {
        case .top:
            border.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: width)
        case .bottom:
            border.frame = CGRect(x: 0, y: self.frame.size.height - width, width: self.frame.size.width, height: width)
        case .left:
            border.frame = CGRect(x: 0, y: 0, width: width, height: self.frame.size.height)
        case .right:
            border.frame = CGRect(x: self.frame.size.width - width, y: 0, width: width, height: self.frame.size.height)
        }

        self.layer.addSublayer(border)
    }
}
