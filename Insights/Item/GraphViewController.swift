//
//  WalkGraphViewController.swift
//  weekselector
//
//  Created by GEU on 11/02/26.
//

import UIKit
import PDFKit

class GraphViewController: UIViewController {
    
    @IBOutlet weak var walkinggraph: UICollectionView!
    var activities: [ActivityType] = ActivityType.allCases
    let allWeeks = Array(1...40)
    var insightsData: InsightsResponse?
    var selectedActivityIndex: Int = 0
    var selectedWeekIndex: Int = 0
    var selectedDayKey: String?
    var selectedSessionForDetail: InsightSession?
    var selectedDateForDetail: String = ""
    var selectedActivityIconForDetail: String = ""
    var selectedActivityTypeForDetail: String = ""
    var selectedActivityTitleForDetail: String = ""
    var dataController: DataController!
    var theme:AppTheme!
    private var progressObserver: NSObjectProtocol?
    
    var availableWeeks: [Int] {
        let currentWeek = max(1, min(dataController?.userProfile.gestationalWeek ?? 1, 40))
        return Array(1...currentWeek)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        theme = dataController.theme
        applyAnimatedBackground(theme: theme)
        walkinggraph.backgroundColor = .clear
        walkinggraph.allowsSelection = true
        walkinggraph.allowsMultipleSelection = false
        walkinggraph.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)
        walkinggraph.clipsToBounds = false
        walkinggraph.layer.masksToBounds = false
        walkinggraph.scrollIndicatorInsets = walkinggraph.contentInset
        navigationItem.largeTitleDisplayMode = .never
        setupCollectionView()
        observeProgressChanges()
        reloadUI()
//        dataController.loadDummyProgressDataUntilCurrentDay { [weak self] in
//            DispatchQueue.main.async {
//                self?.reloadUI()
//            }
//        }
    }
    
    deinit {
        if let progressObserver {
            NotificationCenter.default.removeObserver(progressObserver)
        }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "detail_cell" {
            if let nav = segue.destination as? UINavigationController,
               let vc = nav.topViewController as? InnerCellViewController {
                vc.selectedSession = selectedSessionForDetail
                vc.selectedDateText = selectedDateForDetail
                vc.selectedActivityTitle = selectedActivityTitleForDetail
                vc.selectedActivityIcon = selectedActivityIconForDetail
                vc.selectedActivityType = selectedActivityTypeForDetail
                vc.dataController = dataController
                
            } else if let vc = segue.destination as? InnerCellViewController {
                vc.selectedSession = selectedSessionForDetail
                vc.selectedDateText = selectedDateForDetail
                vc.selectedActivityTitle = selectedActivityTitleForDetail
                vc.selectedActivityIcon = selectedActivityIconForDetail
                vc.selectedActivityType = selectedActivityTypeForDetail
                vc.dataController = dataController
            }
        }
    }
}

extension GraphViewController {
    
    private func observeProgressChanges() {
        progressObserver = NotificationCenter.default.addObserver(
            forName: DataController.progressDidChangeNotification,
            object: dataController,
            queue: .main
        ) { [weak self] _ in
            self?.reloadUI()
        }
    }
    
    func setupCollectionView() {
        walkinggraph.delegate = self
        walkinggraph.dataSource = self

        walkinggraph.register(UINib(nibName: "WeekCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "week_cell")

        walkinggraph.register(UINib(nibName: "GraphCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "graph_cell")

        walkinggraph.register(UINib(nibName: "FooterInsights", bundle: nil), forCellWithReuseIdentifier: "footer_insights")

        walkinggraph.register(UINib(nibName: "ActivitySessionHeaderView", bundle: nil), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "ActivitySessionHeaderView")
        
        walkinggraph.setCollectionViewLayout(generateLayout(), animated: false)
    }
}

extension GraphViewController {
    
    func reloadUI() {
        guard activities.indices.contains(selectedActivityIndex) else { return }

        let activity = activities[selectedActivityIndex]
        title = activity.title

        let onboardingWeek = max(1, min(dataController?.userProfile.gestationalWeek ?? 1, 40))

        if selectedWeekIndex == 0 || !availableWeeks.contains(selectedWeekIndex) {
            selectedWeekIndex = dataController.preferredInsightWeek(for: activity, preferredWeek: onboardingWeek)
        }

        let orderedDays = selectedInsightDaysOrdered()
        if selectedDayKey == nil || !orderedDays.contains(where: { $0.dayKey == selectedDayKey }) {
            selectedDayKey = defaultDayKeyForSelectedWeek()
        }
        walkinggraph.reloadData()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let index = self.availableWeeks.firstIndex(of: self.selectedWeekIndex) {
                let indexPath = IndexPath(item: index, section: 0)
                self.walkinggraph.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
            }
        }
    }
    func themeColor() -> UIColor {
        guard activities.indices.contains(selectedActivityIndex) else {
            return .systemGreen
        }

        return activities[selectedActivityIndex].selectedColor
    }

    func selectedInsight() -> Insight? {
        guard activities.indices.contains(selectedActivityIndex) else { return nil }

        let selectedActivity = activities[selectedActivityIndex]

        return insightsData?.insights.first(where: {
            $0.title.lowercased() == selectedActivity.title.lowercased() ||
            $0.activityType.lowercased() == selectedActivity.rawValue.lowercased()
        })
    }

    func selectedInsightWeek() -> InsightWeek? {
        guard let insight = selectedInsight() else { return nil }
        let selectedWeek = "W\(selectedWeekIndex)"

        return insight.weeks.first(where: {
            $0.week.lowercased() == selectedWeek.lowercased()
        })
    }

    func selectedInsightDaysOrdered() -> [InsightDay] {
        if let liveSnapshot = dataController.activityWeekProgressSnapshot(
            for: activities[selectedActivityIndex],
            gestationalWeek: selectedWeekIndex
        ) {
            return liveSnapshot.days
        }
        return selectedInsightWeek()?.days ?? []
    }

    func selectedInsightDay() -> InsightDay? {
        let days = selectedInsightDaysOrdered()

        if let selectedDayKey,
           let selectedDay = days.first(where: { $0.dayKey == selectedDayKey }) {
            return selectedDay
        }

        return days.last
    }
    
  
    func currentGraphSummary() -> InsightGraphSummary? {
        if let liveSummary = dataController.activityWeekProgressSnapshot(
            for: activities[selectedActivityIndex],
            gestationalWeek: selectedWeekIndex
        )?.graphSummary {
            return liveSummary
        }
        
        guard let week = selectedInsightWeek(), activities.indices.contains(selectedActivityIndex) else { return nil }
        let activity = activities[selectedActivityIndex]
        let labels = week.days.map(\.dayLabel)
        var values = Array(repeating: 0.0, count: 7)
        for day in week.days {
            guard let index = week.days.firstIndex(where: { $0.dayKey == day.dayKey }) else { continue }
            values[index] = metricValue(for: day, activityType: activity.rawValue)
        }
        let total = values.reduce(0, +)
        let nonZeroDays = max(values.filter { $0 > 0 }.count, 1)
        let average = total / Double(nonZeroDays)
        let metricTitle: String
        let displayValue: String
        switch activity.rawValue.lowercased() {
        case "walking":
            metricTitle = "Average Steps"
            displayValue = "\(Int(average * 1000)) steps"
        case "exercise":
            metricTitle = "Average Reps"
            displayValue = "\(Int(average)) reps"
        case "yoga":
            metricTitle = "Average Duration"
            displayValue = "\(Int(average)) min"
        default:
            metricTitle = "Average"
            displayValue = "\(Int(average))"
        }
        return InsightGraphSummary(
            title: activity.title,metricTitle: metricTitle,displayValue: displayValue,dayLabels: labels, dayValues: values
        )
    }

    func metricValue(for day: InsightDay, activityType: String) -> Double {
        switch activityType.lowercased() {
        case "walking":
            return totalStat(named: "Steps", in: day.sessions)
        case "exercise":
            return totalStat(named: "Reps", in: day.sessions)
        case "yoga":
            return totalStat(named: "Duration", in: day.sessions)
        default:
            return 0
        }
    }

    func totalStat(named title: String, in sessions: [InsightSession]) -> Double {
        sessions.reduce(0.0) { partial, session in
            let value = session.stats.first(where: { $0.title.lowercased() == title.lowercased() })?.value ?? "0"
            return partial + (Double(value) ?? 0)
        }
    }

    func chartIndex(for dayKey: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return nil }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 2: return 0
        case 3: return 1
        case 4: return 2
        case 5: return 3
        case 6: return 4
        case 7: return 5
        case 1: return 6
        default: return nil
        }
    }
    
    func selectedSessions() -> [InsightSession] {
        selectedInsightDay()?.sessions ?? []
    }

    func defaultDayKeyForSelectedWeek() -> String? {
        let orderedDays = selectedInsightDaysOrdered()
        guard !orderedDays.isEmpty else { return nil }

        let currentWeek = max(1, min(dataController?.userProfile.gestationalWeek ?? 1, 40))
        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "yyyy-MM-dd"
        todayFormatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        let todayKey = todayFormatter.string(from: Date())

        if selectedWeekIndex == currentWeek,
           let today = orderedDays.first(where: { $0.dayKey == todayKey }) {
            return today.dayKey
        }

        if let latestSessionDay = orderedDays.last(where: { !$0.sessions.isEmpty }) {
            return latestSessionDay.dayKey
        }

        return orderedDays.first?.dayKey
    }

    func selectedChartIndex() -> Int? {
        guard let selectedDayKey else { return nil }
        return selectedInsightDaysOrdered().firstIndex { $0.dayKey == selectedDayKey }
    }

    func updateSelectedActivity(index: Int) {
        guard activities.indices.contains(index) else { return }
        selectedActivityIndex = index
        selectedDayKey = nil
        reloadUI()
        walkinggraph.reloadData()
    }

    func updateSelectedDayFromChart(barIndex: Int) {
        let orderedDays = selectedInsightDaysOrdered()
        guard orderedDays.indices.contains(barIndex) else { return }
        selectedDayKey = orderedDays[barIndex].dayKey
        walkinggraph.reloadSections(IndexSet(integer: 2))
    }
 }

extension GraphViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 3
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard !activities.isEmpty else { return 0 }
        switch section {
        case 0:
            return availableWeeks.count
        case 1:
            return 1
        case 2:
            return max(selectedSessions().count, 1)
        default:
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let activity = activities[selectedActivityIndex]
        switch indexPath.section {
        case 0:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "week_cell",for: indexPath) as! WeekCollectionViewCell
          let weekNumber = availableWeeks[indexPath.item]
            cell.configure(title: "W\(weekNumber)",isSelected: weekNumber == selectedWeekIndex,themeColor:themeColor(),theme:theme)
            return cell
            
        case 1:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "graph_cell",for: indexPath) as! GraphCollectionViewCell
            cell.layer.cornerRadius = 24
            cell.layer.masksToBounds = true
            cell.backgroundColor = .secondarySystemBackground
            cell.onBarSelected = { [weak self] barIndex in self?.updateSelectedDayFromChart(barIndex: barIndex)
            }
            if let summary = currentGraphSummary() {
                cell.configure(with: summary,activity: activity,color: themeColor(),theme: theme,selectedBarIndex: selectedChartIndex()
                )
            } else {
                cell.showNoData(activity: activity)
            }
            return cell
        case 2:
            let cell = collectionView.dequeueReusableCell( withReuseIdentifier: "footer_insights", for: indexPath)as! FooterInsights
            let sessions = selectedSessions()
            if sessions.isEmpty {
                cell.theme = theme
                cell.configurePlaceholder(activityName: activity.title,activityIcon:activity.icon,activityColor:activity.rawValue)
            }else if sessions.indices.contains(indexPath.item),
                      let day = selectedInsightDay() {
                let session = sessions[indexPath.item]
                
                cell.configure(session:session,activityIcon:activity.icon,activityColor:activity.rawValue,dateDisplay:day.dayKey,theme: theme)
            }
            return cell
            
        default:
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView,viewForSupplementaryElementOfKind kind: String,at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,withReuseIdentifier: "ActivitySessionHeaderView",for: indexPath) as! ActivitySessionHeaderView
        if indexPath.section == 2 { header.configure(title: "Your Activity Sessions")
        }
        return header
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
        cell.alpha = 0
        cell.transform = CGAffineTransform(translationX: 0, y: 15)
        
        UIView.animate(
            withDuration: 0.1,delay: Double(indexPath.item) * 0.01,usingSpringWithDamping: 0.9,initialSpringVelocity:0.5,options: [.curveEaseOut],animations: {
               cell.alpha = 1
               cell.transform = .identity
            }
        )
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        if indexPath.section == 0 {
            selectedWeekIndex = availableWeeks[indexPath.item]
            selectedDayKey = defaultDayKeyForSelectedWeek()
            collectionView.reloadData()
            collectionView.scrollToItem(at: indexPath,at: .centeredHorizontally,animated: true)
            return
        }
        if indexPath.section == 2 {
            let sessions = selectedSessions()
            guard sessions.indices.contains(indexPath.item),
            let day = selectedInsightDay() else { return }
            let activity = activities[selectedActivityIndex]
            selectedSessionForDetail = sessions[indexPath.item]
            selectedDateForDetail = day.dayKey
            selectedActivityTitleForDetail = selectedSessionForDetail?.sessionTitle ?? activity.title
            selectedActivityIconForDetail = activity.icon
            selectedActivityTypeForDetail = activity.rawValue
            performSegue(withIdentifier: "detail_cell", sender: self)
        }
    }
}

extension GraphViewController {
        func generateLayout() -> UICollectionViewLayout {
            UICollectionViewCompositionalLayout { sectionIndex, _ in
            switch sectionIndex {
            case 0:
                let itemSize = NSCollectionLayoutSize( widthDimension: .absolute(52),heightDimension: .absolute(52))
                
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension:.estimated(52),heightDimension:.absolute(52))
                
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = 14
                section.contentInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 16)
                return section
                
            case 1:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),heightDimension: .fractionalHeight(1.0))
                
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),heightDimension: .absolute(340))
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize,subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 16,leading: 16,bottom: 12,trailing: 16
                )
                return section
                
            default:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),heightDimension: .estimated(220))
                
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),heightDimension: .estimated(250))
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize,subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 16
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16)
                
                let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),heightDimension: .absolute(36))
                
                let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize:headerSize,elementKind:UICollectionView.elementKindSectionHeader,alignment: .top )
                header.pinToVisibleBounds = false
                section.boundarySupplementaryItems = [header]
                return section
            }
        }
    }
}
