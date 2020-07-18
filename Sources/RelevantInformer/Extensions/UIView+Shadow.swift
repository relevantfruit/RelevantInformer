
import UIKit

extension UIView {
  
  func applyDropShadow(with offset: CGSize, opacity: Float, radius: CGFloat, color: UIColor) {
    layer.applyDropShadow(with: offset, opacity: opacity, radius: radius, color: color)
  }
  
  func removeDropShadow() {
    layer.removeDropShadow()
  }
}

extension CALayer {
  
  func applyDropShadow(with offset: CGSize, opacity: Float, radius: CGFloat, color: UIColor) {
    shadowOffset = offset
    shadowOpacity = opacity
    shadowRadius = radius
    shadowColor = color.cgColor
    shouldRasterize = true
    rasterizationScale = UIScreen.main.scale
  }
  
  func removeDropShadow() {
    shadowOffset = .zero
    shadowOpacity = 0
    shadowRadius = 0
    shadowColor = UIColor.clear.cgColor
    shouldRasterize = false
  }
}
