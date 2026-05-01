// RingProgressView.swift

import UIKit

class RingProgressView: UIView {

    @IBInspectable var lineWidth: CGFloat = 5
    @IBInspectable var trackColor: UIColor = UIColor.white.withAlphaComponent(0.12)
    @IBInspectable var progressColor: UIColor = UIColor(red: 0.67, green: 0.33, blue: 1.0, alpha: 1)

    let trackLayer    = CAShapeLayer()
    let progressLayer = CAShapeLayer()

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    func setupLayers() {
        backgroundColor = .clear

        trackLayer.fillColor   = UIColor.clear.cgColor
        trackLayer.lineCap     = .round

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineCap   = .round
        progressLayer.strokeEnd = 0

        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size       = bounds.width
        guard size > 0 else { return }

        let radius     = (size - lineWidth) / 2
        let center     = CGPoint(x: size / 2, y: size / 2)
        let startAngle = -CGFloat.pi / 2
        let endAngle   = startAngle + 2 * .pi

        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        ).cgPath

        trackLayer.path        = path
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.lineWidth   = lineWidth
        trackLayer.frame       = bounds

        progressLayer.path        = path
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.lineWidth   = lineWidth
        progressLayer.frame       = bounds
    }

    func animateTo(progress: CGFloat) {
        progressLayer.strokeEnd = progress

        let animation            = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue      = 0
        animation.toValue        = progress
        animation.duration       = 1.0
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode       = .forwards
        animation.isRemovedOnCompletion = false

        progressLayer.add(animation, forKey: "ringFill")
    }

    func reset() {
        progressLayer.removeAllAnimations()
        progressLayer.strokeEnd = 0
    }
}
