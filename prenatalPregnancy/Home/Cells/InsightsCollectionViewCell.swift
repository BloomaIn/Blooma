//
//  InsightsCollectionViewCell.swift
//  prenatalPregnancy
//

import UIKit

class InsightsCollectionViewCell: UICollectionViewCell {

    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var insightImageView: UIImageView!

    private let bottomScrimLayer = CAGradientLayer()
    private let topScrimLayer    = CAGradientLayer()
    private let categoryLabel    = UILabel()
    private let subtitleLabel    = UILabel()
    private let badgeView        = UIView()
    private let badgeLabel       = UILabel()

    override func awakeFromNib() {
        super.awakeFromNib()
        buildUI()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bottomScrimLayer.frame = contentView.bounds
        topScrimLayer.frame    = contentView.bounds

        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: contentView.layer.cornerRadius
        ).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        insightImageView.image = nil
        label.text             = nil
        subtitleLabel.text     = nil
        categoryLabel.text     = nil
        subtitleLabel.isHidden = true
    }

    func configure(with model: Insights, isHero: Bool) {
        insightImageView.image = model.image
        label.text             = model.title
        categoryLabel.text     = categoryTag(for: model.title)

        if isHero {
            contentView.layer.cornerRadius = 20
            layer.shadowOpacity = 0.15
            layer.shadowRadius             = 16

            label.font         = .systemFont(ofSize: 22, weight: .heavy)
            categoryLabel.font = .systemFont(ofSize: 11, weight: .semibold)

            subtitleLabel.text     = model.description.isEmpty ? nil : model.description
            subtitleLabel.isHidden = model.description.isEmpty

            badgeLabel.text    = "✦  Featured"
            badgeView.isHidden = false

            bottomScrimLayer.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.20).cgColor,
                UIColor.black.withAlphaComponent(0.48).cgColor
            ]
            bottomScrimLayer.locations = [0.28, 0.55, 1.0]

        } else {
            contentView.layer.cornerRadius = 16
            layer.shadowOpacity            = 0.15
            layer.shadowRadius             = 10

            label.font         = .systemFont(ofSize: 13, weight: .heavy)
            categoryLabel.font = .systemFont(ofSize: 9, weight: .semibold)

            subtitleLabel.isHidden = true

            badgeLabel.text    = "✦"
            badgeView.isHidden = false
            bottomScrimLayer.colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.30).cgColor,
                UIColor.black.withAlphaComponent(0.32).cgColor
            ]
            bottomScrimLayer.locations = [0.05, 0.42, 1.0]
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    private func buildUI() {

        layer.masksToBounds = false
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOffset  = CGSize(width: 0, height: 5)
        layer.shadowOpacity = 0
        layer.shadowRadius  = 12

        contentView.clipsToBounds      = true
        contentView.layer.cornerRadius = 20

        insightImageView.contentMode   = .scaleAspectFill
        insightImageView.clipsToBounds = false
        insightImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            insightImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            insightImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            insightImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            insightImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        
        topScrimLayer.colors     = [UIColor.black.withAlphaComponent(0.18).cgColor,
                                     UIColor.clear.cgColor]
        topScrimLayer.locations  = [0, 0.28]
        topScrimLayer.startPoint = CGPoint(x: 0.5, y: 0)
        topScrimLayer.endPoint   = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(topScrimLayer)

        bottomScrimLayer.startPoint = CGPoint(x: 0.5, y: 0)
        bottomScrimLayer.endPoint   = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(bottomScrimLayer)

        badgeView.backgroundColor    = UIColor.white.withAlphaComponent(0.22)
        badgeView.layer.cornerRadius = 12
        badgeView.layer.borderWidth  = 1
        badgeView.layer.borderColor  = UIColor.white.withAlphaComponent(0.35).cgColor
        badgeView.clipsToBounds      = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badgeView)

        badgeLabel.font      = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            badgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            badgeLabel.topAnchor.constraint(equalTo: badgeView.topAnchor, constant: 4),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: -4),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor, constant: 9),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: -9)
        ])

        subtitleLabel.textColor     = UIColor.white.withAlphaComponent(1.0)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font          = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.isHidden      = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // Category label
        categoryLabel.textColor     = UIColor.white.withAlphaComponent(1.0)
        categoryLabel.numberOfLines = 1
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(categoryLabel)

        // Title — reuse IBOutlet, bring to front so it sits above CA layers
        label.textColor      = .white
        label.numberOfLines  = 2
        label.lineBreakMode  = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.shadowColor   = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.6
        label.layer.shadowRadius  = 6
        label.layer.shadowOffset  = CGSize(width: 0, height: 1)
        label.layer.masksToBounds = false
        contentView.bringSubviewToFront(label)

        // Layout — stack bottom-up:
        // contentView bottom → subtitle (14pt inset) → title (5pt gap) → category (4pt gap)
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -5),

            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            categoryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            categoryLabel.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4)
        ])
    }

    // MARK: - Helpers
    private func categoryTag(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("bump")                         { return "Wellness · Movement" }
        if t.contains("calm") || t.contains("sleep")  { return "Rest · Mindfulness"  }
        if t.contains("strength")                     { return "Strength · Fitness"  }
        if t.contains("safe") || t.contains("moment") { return "Safety · Awareness"  }
        return "This Week"
    }
}
