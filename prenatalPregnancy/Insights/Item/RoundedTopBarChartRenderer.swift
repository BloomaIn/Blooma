//
//  RoundedBarChartRenderer.swift
//

import UIKit
@preconcurrency import DGCharts

final class RoundedBarChartRenderer: BarChartRenderer {

    var barCornerRadius: CGFloat = 18
    var accentGlassColor: UIColor = .systemPink

    nonisolated override init(
        dataProvider: BarChartDataProvider,
        animator: Animator,
        viewPortHandler: ViewPortHandler
    ) {
        super.init(
            dataProvider: dataProvider,
            animator: animator,
            viewPortHandler: viewPortHandler
        )
    }

    nonisolated override func drawDataSet(
        context: CGContext,
        dataSet: BarChartDataSetProtocol,
        index: Int
    ) {

        guard let dataProvider = dataProvider,
              let barData = dataProvider.barData else { return }

        let transformer = dataProvider.getTransformer(
            forAxis: dataSet.axisDependency
        )

        let phaseY = CGFloat(animator.phaseY)

        for i in 0..<dataSet.entryCount {

            guard let entry = dataSet.entryForIndex(i) as? BarChartDataEntry else {
                continue
            }

            let x = CGFloat(entry.x)
            let y = CGFloat(entry.y)

            let width = CGFloat(barData.barWidth)

            var rect = CGRect(
                x: x - width/2,
                y: 0,
                width: width,
                height: y * phaseY
            )

            transformer.rectValueToPixel(&rect)

            if rect.height <= 0 { continue }

            let radius = min(
                barCornerRadius,
                rect.width/2,
                rect.height/2
            )

            let path = UIBezierPath(
                roundedRect: rect,
                cornerRadius: radius
            )

            let originalColor = dataSet.color(atIndex: i)

            // FIXED RGB + ALPHA EXTRACTION
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0

            originalColor.getRed(
                &red,
                green: &green,
                blue: &blue,
                alpha: &alpha
            )

            let isSelected = alpha > 0.5

            context.saveGState()
            path.addClip()

            let gradientColors: [CGColor]

            if isSelected {

                gradientColors = [
                    accentGlassColor
                        .lighter(by: 0.08)
                        .withAlphaComponent(0.88)
                        .cgColor,

                    accentGlassColor
                        .darker(by: 0.08)
                        .withAlphaComponent(0.82)
                        .cgColor
                ]
            } else {

                gradientColors = [
                    accentGlassColor
                        .lighter(by: 0.40)
                        .withAlphaComponent(0.22)
                        .cgColor,

                    accentGlassColor
                        .lighter(by: 0.15)
                        .withAlphaComponent(0.08)
                        .cgColor
                ]
            }

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors as CFArray,
                locations: [0,1]
            )!

            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )

            context.restoreGState()

            context.setStrokeColor(
                UIColor.white.withAlphaComponent(0.18).cgColor
            )

            context.setLineWidth(0.8)

            context.addPath(path.cgPath)
            context.strokePath()
        }
    }
}

extension UIColor {

    func lighter(by percentage: CGFloat = 0.25) -> UIColor {

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        )

        return UIColor(
            red: min(red + percentage, 1),
            green: min(green + percentage, 1),
            blue: min(blue + percentage, 1),
            alpha: alpha
        )
    }
    
    func darker(by percentage: CGFloat = 0.20) -> UIColor {

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        )

        return UIColor(
            red: max(red - percentage, 0),
            green: max(green - percentage, 0),
            blue: max(blue - percentage, 0),
            alpha: alpha
        )
    }
}
