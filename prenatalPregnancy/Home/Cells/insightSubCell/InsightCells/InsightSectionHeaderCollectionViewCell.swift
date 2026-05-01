import UIKit

class InsightSectionHeaderCollectionViewCell: UICollectionViewCell {

    @IBOutlet weak var container: UIView!
    @IBOutlet weak var header: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.numberOfLines = 1

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        container.backgroundColor = .clear
    }

    func configure(title: String, theme: AppTheme) {
        header.text = title.uppercased()
        header.textColor = theme.secondaryText
    }
}
