import UIKit

extension UIColor {
    static let svBackground = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
    static let svPanel = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
    static let svPanel2 = UIColor(red: 0.11, green: 0.14, blue: 0.19, alpha: 1)
    static let svBorder = UIColor(red: 0.18, green: 0.21, blue: 0.27, alpha: 1)
    static let svBlue = UIColor(red: 0.18, green: 0.51, blue: 0.97, alpha: 1)
    static let svGreen = UIColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1)
    static let svOrange = UIColor(red: 0.94, green: 0.53, blue: 0.24, alpha: 1)
    static let svRed = UIColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1)
    static let svText = UIColor(red: 0.90, green: 0.93, blue: 0.95, alpha: 1)
    static let svDim = UIColor(white: 0.60, alpha: 1)
}

extension UIView {
    func svRounded(_ r: CGFloat = 8) {
        layer.cornerRadius = r
        clipsToBounds = true
    }
}

func svHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}
