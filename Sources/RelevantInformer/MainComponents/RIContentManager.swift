//
//  RIContentManager.swift
//  RelevantInformerExample
//
//  Created by Rufat Mirza on 4.07.2020.
//  Copyright © 2020 Rufat Mirza. All rights reserved.
//

import UIKit

protocol ContentViewDelegate: AnyObject {
  
  func changeToActive(with attributes: RIAttributes)
  func changeToInactive(with attributes: RIAttributes)
  func didCloseUserInitiated(view: RIMessageView)
}

private extension RIContentManager {
  
  struct Constants {
    static let minimumSwipeVelocity: CGFloat = 60
  }
}

final class RIContentManager {
  
  var context: RelevantInformer.Context
  
  private var attributes: RIAttributes
  private var contentView: RIMessageView
  private var container: UIView
  private weak var delegate: ContentViewDelegate?
  
  private var targetConstraint: NSLayoutConstraint!
  private var pendingWork: DispatchWorkItem!
  private var animation: Animator!
    
  private var totalTranslation: CGFloat = 0
  
  private var edgeOffset: CGFloat {
    return attributes.constraints.verticalOffset
  }
  
  private var verticalLimit: CGFloat {
    return UIScreen.main.bounds.height + edgeOffset
  }

  // MARK: Lifecycle
  
  init(with context: RelevantInformer.Context, container: UIViewController, delegate: ContentViewDelegate) {
    
    self.context = context
    
    let contentView: RIMessageView
    
    if let viewController = context.viewController {
      container.addChild(viewController)
      contentView = RIMessageView(view: viewController.view, attributes: context.attributes)
    }
    else {
      contentView = RIMessageView(view: context.view, attributes: context.attributes)
    }
    
    self.contentView = contentView
    self.container = container.view
    self.attributes = context.attributes
    self.delegate = delegate
    
    setup()
    setupPanGesture()
    setupTapGesture()

    totalTranslation = edgeOffset
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  deinit {
    print(#function + " " + String(describing: type(of: self)))
    NotificationCenter.default.removeObserver(self)
  }
  
  // MARK: Setup
  
  private func setup() {
    contentView.delegate = self
    container.addSubview(contentView)
    let animationContext = AnimationContext(view: contentView, parent: container, attributes: attributes)
    animation = attributes.presentation.animation(context: animationContext)
    targetConstraint = animation.targetConstraint
  }
  
  private func setupPanGesture() {
    guard attributes.interaction.isPanEnabled else { return }
    
    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureRecognized(gesture:)))
    contentView.addGestureRecognizer(panGesture)
  }
  
  private func setupTapGesture() {
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGestureRecognized))
    tapGesture.cancelsTouchesInView = false

    switch attributes.interaction.onContent {
    case .forwardToLowerWindow:
      return
      
    default:
      contentView.addGestureRecognizer(tapGesture)
    }
  }
  
  func display() {
    animation.show() { [weak self] in
      self?.scheduleAnimateOut()
    }
    self.delegate?.changeToActive(with: attributes)
  }
  
  func close(promptly: Bool = false, userInitiated: Bool = true, completion: VoidCallback? = nil) {
    if promptly {
      removePromptly()
    }
    else {
      animateOut(userInitiated: userInitiated, completion: completion)
    }
  }
}

// MARK: - End of Lifecycle

private extension RIContentManager {
  
  func removePromptly() {
    pendingWork?.cancel()
    delegate?.changeToInactive(with: attributes)
    removeFromSuperview()
  }
  
  func removeFromSuperview(completion: VoidCallback? = nil) {
    contentView.removeFromSuperview()
    completion?()
  }
}

// MARK: - Animations

private extension RIContentManager {
  
  func scheduleAnimateOut() {
    pendingWork?.cancel()
    
    pendingWork = DispatchWorkItem { [weak self] in
      self?.animateOut(userInitiated: true)
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + attributes.displayDuration, execute: pendingWork)
  }
  
  private func animateOut(userInitiated: Bool, completion: VoidCallback? = nil) {
    
    if attributes.constraints.keyboard.isBound {
      container.endEditing(true)
    }
    
    animation.hide() {
      self.removeFromSuperview()
      if userInitiated {
        self.delegate?.didCloseUserInitiated(view: self.contentView)
      }
      completion?()
    }
    
    pendingWork?.cancel()
    
    delegate?.changeToInactive(with: attributes)
  }
}

// MARK: - Responds to user interactions (tap / pan / swipe / touches)

private extension RIContentManager {
  
  @objc func tapGestureRecognized() {
    switch attributes.interaction.onContent {
    case .delayExit where attributes.displayDuration.isFinite:
      scheduleAnimateOut()
      
    case .dismiss:
      close()
      fallthrough
      
    default:
      // TODO: Custom actions can be added here.
      break
    }
  }
  
  @objc func panGestureRecognized(gesture: UIPanGestureRecognizer) {
    
    container.endEditing(true)
    handleExitDelayIfNeeded(byPanState: gesture.state)
    
    let translation = gesture.translation(in: container).y
    
    if shouldStretch(with: translation) {
      if attributes.interaction.isStretchEnabled {
        totalTranslation += translation
        calculateLogarithmicOffset(forOffset: totalTranslation, currentTranslation: translation)
        
        switch gesture.state {
        case .ended, .failed, .cancelled:
          animateRubberBandPullback()
        default:
          break
        }
      }
    }
    else {
      switch gesture.state {
      case .ended, .failed, .cancelled:
        let velocity = gesture.velocity(in: container).y
        swipeEnded(with: velocity)
      case .changed:
        targetConstraint.constant += translation
      default:
        break
      }
    }
    gesture.setTranslation(.zero, in: container)
  }
  
  func swipeEnded(with velocity: CGFloat) {
    let distance = Swift.abs(0 - targetConstraint.constant)
    var duration = max(0.3, TimeInterval(distance / Swift.abs(velocity)))
    duration = min(0.7, duration)
    
    if attributes.interaction.isPanEnabled && testSwipeVelocity(with: velocity) && testSwipeInConstraint() {
      stretchOut(duration: duration)
    }
    else {
      animateRubberBandPullback()
    }
  }
  
  func stretchOut(duration: TimeInterval) {
    close()
  }
  
  func calculateLogarithmicOffset(forOffset offset: CGFloat, currentTranslation: CGFloat) {
    let offset = Swift.abs(offset) + verticalLimit
    let delta = (1 + log10(offset / verticalLimit))
    
    switch attributes.presentation {
    case .slideUpToCenter:
      targetConstraint.constant -= delta

    case .slideDownToTop:
      targetConstraint.constant += delta
      
    case .slideUpToBottom:
      targetConstraint.constant -= delta
    }
  }
  
  func shouldStretch(with translation: CGFloat) -> Bool {
    switch attributes.presentation {
    case .slideUpToCenter:
      return translation < 0 && targetConstraint.constant <= edgeOffset
      
    case .slideDownToTop:
      return translation > 0 && targetConstraint.constant >= edgeOffset
      
    case .slideUpToBottom:
      return translation < 0 && targetConstraint.constant <= edgeOffset
    }
  }
  
  func animateRubberBandPullback() {
    totalTranslation = edgeOffset
    animation.animateRubberBandPullback()
  }
  
  func testSwipeInConstraint() -> Bool {
    switch attributes.presentation {
    case .slideUpToCenter:
      return targetConstraint.constant > edgeOffset
      
    case .slideDownToTop:
      return targetConstraint.constant < edgeOffset
    
    case .slideUpToBottom:
      return targetConstraint.constant > edgeOffset
    }
  }
  
  func testSwipeVelocity(with velocity: CGFloat) -> Bool {
    switch attributes.presentation {
    case .slideUpToCenter:
      return velocity > Constants.minimumSwipeVelocity

    case .slideDownToTop:
      return velocity < Constants.minimumSwipeVelocity
      
    case .slideUpToBottom:
      return velocity > Constants.minimumSwipeVelocity
    }
  }
  
  func handleExitDelayIfNeeded(byPanState state: UIGestureRecognizer.State) {
    guard attributes.interaction.onContent.isDelayExit && attributes.displayDuration.isFinite else {
      return
    }
    
    switch state {
    case .began:
      pendingWork?.cancel()
      
    case .ended, .failed, .cancelled:
      scheduleAnimateOut()
    default:
      break
    }
  }
}

// MARK: - TouchEventsDelegate

extension RIContentManager: TouchEventsDelegate {
  
  func touchesBegan(view: RIMessageView) {
    if attributes.interaction.onContent.isDelayExit && attributes.displayDuration.isFinite {
      pendingWork?.cancel()
    }
  }
  
  func touchesEnded(view: RIMessageView) {
    if attributes.interaction.onContent.isDelayExit && attributes.displayDuration.isFinite {
      scheduleAnimateOut()
    }
  }
}
