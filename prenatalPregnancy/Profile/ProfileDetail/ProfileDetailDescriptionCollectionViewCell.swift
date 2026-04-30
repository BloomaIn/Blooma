//
//  ProfileDetailDescriptionCollectionViewCell.swift
//  prenatalPregnancy
//
//  Created by GEU on 25/03/26.
//

import UIKit

class ProfileDetailDescriptionCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    private var theme: AppTheme!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
    }
    
    private func setupUI() {
        
        contentView.backgroundColor = .clear
        iconImageView.tintColor = theme.primaryText
        
        // Title
        titleLabel.textColor = theme.primaryText
        
        // Subtitle
        subtitleLabel.textColor = theme.secondaryText
    }
    
    func configure(title: String, subtitle: String, icon: String, theme: AppTheme) {
        
        self.theme = theme
        setupUI()
        
        titleLabel.text = title
        subtitleLabel.text = subtitle
        
        iconImageView.image = UIImage(systemName: icon)
    }
    
}
