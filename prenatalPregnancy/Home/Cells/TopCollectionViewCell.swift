import UIKit

class TopCollectionViewCell: UICollectionViewCell {

    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var trimesterBadgeView: UIView!
    @IBOutlet weak var badgeDotView: UIView!
    @IBOutlet weak var trimesterBadge: UILabel!
    @IBOutlet weak var greetingLabel: UILabel!
    @IBOutlet weak var dueInTitleLabel: UILabel!
    @IBOutlet weak var dueValue: UILabel!
    @IBOutlet weak var dueSubLabel: UILabel!
    @IBOutlet weak var trimEndTitleLabel: UILabel!
    @IBOutlet weak var trimEndValueLabel: UILabel!
    @IBOutlet weak var trimEndSubLabel: UILabel!
    @IBOutlet weak var pregnancyRingView: RingProgressView!
    @IBOutlet weak var pregRingContainer: UIView!
    @IBOutlet weak var ringPercentLabel: UILabel!
    @IBOutlet weak var ringDoneLabel: UILabel!
    @IBOutlet weak var pregnancyJourney: UILabel!
    @IBOutlet weak var dueInContainer: UIView!
    @IBOutlet weak var trimesterInfoContainer: UIView!

    // MARK: - Theme

    private var theme: AppTheme?

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pregnancyRingView.reset()
    }

    // MARK: - Setup

    private func setupUI(theme: AppTheme) {
        layer.shadowOpacity = 0
        layer.masksToBounds = false

        // MARK: Glass card
        cardView.backgroundColor     = theme.glassMedium
        cardView.layer.cornerRadius  = 24
        cardView.layer.cornerCurve   = .continuous
        cardView.layer.masksToBounds = false
        cardView.layer.borderWidth   = 1
        cardView.layer.borderColor   = theme.glassBorderLight.cgColor
        cardView.layer.shadowColor   = theme.shadowSoft.cgColor
        cardView.layer.shadowOpacity = 1
        cardView.layer.shadowRadius  = 16
        cardView.layer.shadowOffset  = CGSize(width: 0, height: 4)

        // MARK: Trimester badge
        trimesterBadgeView.backgroundColor     = theme.accentPrimary.withAlphaComponent(0.12)
        trimesterBadgeView.layer.cornerRadius  = 12
        trimesterBadgeView.layer.cornerCurve   = .continuous
        trimesterBadgeView.layer.masksToBounds = true
        trimesterBadgeView.layer.borderWidth   = 1
        trimesterBadgeView.layer.borderColor   = theme.accentPrimary.withAlphaComponent(0.25).cgColor

        badgeDotView.backgroundColor     = theme.accentPrimary
        badgeDotView.layer.cornerRadius  = 3
        badgeDotView.layer.shadowOpacity = 0

        trimesterBadge.textColor = theme.accentSecondary
        trimesterBadge.font      = .systemFont(ofSize: 11, weight: .semibold)

        // MARK: Greeting
        greetingLabel.textColor = theme.primaryText
        greetingLabel.font      = .systemFont(ofSize: 17, weight: .semibold)

        // MARK: Due In container — glass pill
//        styleStatContainer(dueInContainer, theme: theme)
        // MARK: Due In container — clear
        dueInContainer.backgroundColor = .clear
        dueInContainer.layer.borderWidth = 0
        dueInContainer.layer.shadowOpacity = 0

        // MARK: Trimester End container — clear
        trimesterInfoContainer.backgroundColor = .clear
        trimesterInfoContainer.layer.borderWidth = 0
        trimesterInfoContainer.layer.shadowOpacity = 0

        dueInTitleLabel.textColor = theme.secondaryText
        dueInTitleLabel.font      = .systemFont(ofSize: 11, weight: .medium)

        dueValue.textColor = theme.primaryText
        dueValue.font      = .systemFont(ofSize: 20, weight: .bold)

        dueSubLabel.textColor = theme.tertiaryText
        dueSubLabel.font      = .systemFont(ofSize: 11, weight: .regular)

        // MARK: Trimester End container — glass pill
//        styleStatContainer(trimesterInfoContainer, theme: theme)

        trimEndTitleLabel.textColor = theme.secondaryText
        trimEndTitleLabel.font      = .systemFont(ofSize: 11, weight: .medium)

        trimEndValueLabel.textColor = theme.primaryText
        trimEndValueLabel.font      = .systemFont(ofSize: 20, weight: .bold)

        trimEndSubLabel.textColor = theme.tertiaryText
        trimEndSubLabel.font      = .systemFont(ofSize: 11, weight: .regular)

        // MARK: Ring container
//        pregRingContainer.backgroundColor    = theme.glassThin
//        pregRingContainer.layer.cornerRadius = 16
//        pregRingContainer.layer.cornerCurve  = .continuous
//        pregRingContainer.layer.masksToBounds = true
//        pregRingContainer.layer.borderWidth  = 1
//        pregRingContainer.layer.borderColor  = theme.glassBorderLight.cgColor
        pregRingContainer.backgroundColor = .clear

        ringPercentLabel.textColor = theme.primaryText
        ringPercentLabel.font      = .systemFont(ofSize: 15, weight: .bold)

        ringDoneLabel.text      = "done"
        ringDoneLabel.textColor = theme.tertiaryText
        ringDoneLabel.font      = .systemFont(ofSize: 10, weight: .medium)

        // MARK: Journey label
        pregnancyJourney.textColor     = theme.tertiaryText
        pregnancyJourney.font          = .systemFont(ofSize: 10, weight: .medium)
        pregnancyJourney.numberOfLines = 2
        pregnancyJourney.lineBreakMode = .byWordWrapping
        pregnancyJourney.textAlignment = .center

        // MARK: Ring
        pregnancyRingView.trackColor      = theme.accentSecondary.withAlphaComponent(0.18)
        pregnancyRingView.progressColor   = theme.accentSecondary
        pregnancyRingView.lineWidth       = 5
        pregnancyRingView.backgroundColor = .clear
    }

    private func styleStatContainer(_ view: UIView, theme: AppTheme) {
        view.backgroundColor     = theme.glassThin
        view.layer.cornerRadius  = 14
        view.layer.cornerCurve   = .continuous
        view.layer.masksToBounds = true
        view.layer.borderWidth   = 1
        view.layer.borderColor   = theme.glassBorderLight.cgColor
    }

    // MARK: - Configure

    func configure(week: Int, trimester: Int, dueDate: Date, profile: UserProfile, theme: AppTheme) {
        self.theme = theme
        setupUI(theme: theme)

        let firstName = profile.name
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .first
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Mother"

        trimesterBadge.text  = "Trimester \(trimester) · Week \(week)"
        greetingLabel.text   = "\(greetingForTime()), \(firstName)!"

        let daysLeft         = daysUntilDue(dueDate)
        dueInTitleLabel.text = "Due in"
        dueValue.text        = "\(daysLeft) days"
        dueSubLabel.text     = "~\(daysLeft / 7) weeks left"

        let trimesterEndWeek   = trimester == 1 ? 13 : trimester == 2 ? 26 : 40
        let daysToTrimEnd      = max(0, (trimesterEndWeek - week) * 7)
        trimEndTitleLabel.text = "Trimester ends"
        trimEndValueLabel.text = "\(daysToTrimEnd) days"
        trimEndSubLabel.text   = "Baby's Size: \(babySize(for: week))"

        let progress          = CGFloat(min(week * 7, 280)) / 280.0
        ringPercentLabel.text = "\(Int(progress * 100))%"
        pregnancyJourney.text = "Your journey"
        pregnancyRingView.animateTo(progress: progress)
    }

    // MARK: - Helpers

    private func daysUntilDue(_ dueDate: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0)
    }

    private func greetingForTime() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private func babySize(for week: Int) -> String {
        switch week {
        case 1...4:   return "poppy seed"
        case 5...8:   return "raspberry"
        case 9...12:  return "lime"
        case 13...16: return "avocado"
        case 17...20: return "banana"
        case 21...24: return "corn"
        case 25...28: return "eggplant"
        case 29...32: return "squash"
        case 33...36: return "honeydew"
        case 37...40: return "watermelon"
        default:      return "Baby is growing"
        }
    }
}
