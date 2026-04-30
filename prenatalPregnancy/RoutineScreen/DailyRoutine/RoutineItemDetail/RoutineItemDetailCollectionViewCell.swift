//
//  RoutineItemDetailCollectionViewCell.swift
//  prenatalPregnancy
//
//  Created by GEU on 04/02/26.
//

import UIKit

class RoutineItemDetailCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var contentLabel: UILabel!
    @IBOutlet weak var cardView: UIView!
    
    private var theme: AppTheme?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        contentView.backgroundColor = .clear
        contentLabel.numberOfLines = 5
        contentLabel.lineBreakMode = .byTruncatingTail
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        contentLabel.text = nil
    }
    
    func configureDescription(_ text: String, theme: AppTheme) {
        applyTheme(theme)
        contentLabel.text = text
    }
    
    func configurePoint(_ text: String, theme: AppTheme) {
        applyTheme(theme)
        contentLabel.text = text
    }
    
    private func applyTheme(_ theme: AppTheme) {
        self.theme = theme
        cardView.layer.cornerRadius = 22
        cardView.clipsToBounds = true
        cardView.backgroundColor = theme.glassMedium
        contentLabel.textColor = theme.primaryText
        contentLabel.font = .systemFont(ofSize: 13, weight: .medium)
    }
}
