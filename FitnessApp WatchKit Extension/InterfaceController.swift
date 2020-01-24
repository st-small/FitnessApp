//
//  InterfaceController.swift
//  FitnessApp WatchKit Extension
//
//  Created by Stanly Shiyanovskiy on 23.01.2020.
//  Copyright © 2020 Stanly Shiyanovskiy. All rights reserved.
//

import HealthKit
import WatchKit
import Foundation


public class InterfaceController: WKInterfaceController {

    // MARK: - UI elements
    @IBOutlet private weak var activityType: WKInterfacePicker!
    
    // MARK: - Data
    private let activities: [(String, HKWorkoutActivityType)] = [("Cycling", .cycling), ("Running", .running), ("Wheelchair", .wheelchairRunPace)]
    private var selectedActivity = HKWorkoutActivityType.cycling
    
    public override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        var items = [WKPickerItem]()

        for activity in activities {
            let item = WKPickerItem()
            item.title = activity.0.uppercased()
            items.append(item)
        }

        activityType.setItems(items)
    }

    // MARK: - Actions
    @IBAction private func activityPickerChanged(_ value: Int) {
        selectedActivity = activities[value].1
    }
    
    @IBAction private func startWorkoutTapped() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        WKInterfaceController.reloadRootPageControllers(withNames: ["WorkoutInterfaceController"], contexts: [selectedActivity], orientation: .horizontal, pageIndex: 0)
    }

}
