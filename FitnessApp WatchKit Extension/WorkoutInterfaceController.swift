//
//  WorkoutInterfaceController.swift
//  FitnessApp WatchKit Extension
//
//  Created by Stanly Shiyanovskiy on 23.01.2020.
//  Copyright © 2020 Stanly Shiyanovskiy. All rights reserved.
//

import HealthKit
import WatchKit
import Foundation

public enum DisplayMode {
    case distance, energy, heartRate
}

public class WorkoutInterfaceController: WKInterfaceController {
    
    // MARK: - UI elements
    @IBOutlet private weak var quantityLabel: WKInterfaceLabel!
    @IBOutlet private weak var unitLabel: WKInterfaceLabel!
    @IBOutlet private weak var stopButton: WKInterfaceButton!
    @IBOutlet weak var resumeButton: WKInterfaceButton!
    @IBOutlet weak var endButton: WKInterfaceButton!
    
    // MARK: - Data
    private var healthStore: HKHealthStore?
    private var distanceType = HKQuantityTypeIdentifier.distanceCycling
    
    private var workoutStartDate = Date()
    private var workoutEndDate = Date()
    private var activeDataQueries = [HKQuery]()
    private var workoutSession: HKWorkoutSession?
    
    private var totalEnergyBurned = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: 0)
    private var totalDistance = HKQuantity(unit: HKUnit.meter(), doubleValue: 0)
    private var lastHeartRate = 0.0
    private let countPerMinuteUnit = HKUnit(from: "count/min")
    
    private var displayMode = DisplayMode.distance
    private var workoutIsActive = true
    
    public override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        guard let activity = context as? HKWorkoutActivityType else { return }
        switch activity {
        case .cycling:
            distanceType = .distanceCycling
        case .running:
            distanceType = .distanceWalkingRunning
        default:
            distanceType = .distanceWheelchair
        }
        
        // configure the values we want to write
        let sampleTypes: Set<HKSampleType> = [
            .workoutType(),
            HKSampleType.quantityType(forIdentifier: .heartRate)!,
            HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSampleType.quantityType(forIdentifier: .distanceCycling)!,
            HKSampleType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKSampleType.quantityType(forIdentifier: .distanceWheelchair)!
        ]

        // create our health store
        healthStore = HKHealthStore()
        
        // use it to request authorization for our types
        healthStore?.requestAuthorization(toShare: sampleTypes, read: sampleTypes) { success, error in
            if success {
                self.startWorkout(type: activity)
            }
        }
    }
    
    private func startWorkout(type: HKWorkoutActivityType) {
        let config = HKWorkoutConfiguration()
        config.activityType = type
        config.locationType = .outdoor

        if let session = try? HKWorkoutSession(configuration: config) {
            workoutSession = session
            healthStore?.start(session)
            workoutStartDate = Date()
            session.delegate = self
        }
    }
    
    private func startQueries() {
        startQuery(quantityTypeIdentifier: distanceType)
        startQuery(quantityTypeIdentifier: .activeEnergyBurned)
        startQuery(quantityTypeIdentifier: .heartRate)
        WKInterfaceDevice.current().play(.start)
    }
    
    private func startQuery(quantityTypeIdentifier: HKQuantityTypeIdentifier) {
        // we only want data points after our workout start date
        let datePredicate = HKQuery.predicateForSamples(withStart: workoutStartDate, end: nil, options: .strictStartDate)
        
        // we only want data points that come from our current device
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        
        // combine the two predicates into one
        let queryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, devicePredicate])

        // write code to receive results from our query
        let updateHandler = { (query: HKAnchoredObjectQuery, samples: [HKSample]?, deletedObjects: [HKDeletedObject]?, queryAnchor: HKQueryAnchor?, error: Error?) in
            // safely typecast to a quantity sample so we can read values
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            self.process(samples, type: quantityTypeIdentifier)
        }

        // create the query out of our type (e.g. heart rate), predicate, and result handling code
        let query = HKAnchoredObjectQuery(type: HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier)!, predicate: queryPredicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: updateHandler)
        
        // tell HealthKit to re-run the code every time new data is available
        query.updateHandler = updateHandler
        
        // start the query running
        healthStore?.execute(query)

        // stash it away so we can stop it later
        activeDataQueries.append(query)
    }
    
    private func process(_ samples: [HKQuantitySample], type: HKQuantityTypeIdentifier) {
        // ignore updates while we are paused
        guard workoutIsActive else { return }

        // loop over all the samples we've been sent
        for sample in samples {
            // this is a calorie count
            if type == .activeEnergyBurned {
                // find out how many calories were burned
                let newEnergy = sample.quantity.doubleValue(for: HKUnit.kilocalorie())
                // get our current total calorie burn
                let currentEnergy = totalEnergyBurned.doubleValue(for: HKUnit.kilocalorie())
                // add the two together and store it
                totalEnergyBurned = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: currentEnergy + newEnergy)
                // print out the new total for debugging purposes
                print("Total energy: \(totalEnergyBurned)")
            } else if type == .heartRate {
                // we got a heart rate – just update the property
                lastHeartRate = sample.quantity.doubleValue(for: countPerMinuteUnit)
                print("Last heart rate: \(lastHeartRate)")
            } else if type == distanceType {
                // we got a distance traveled value
                let newDistance = sample.quantity.doubleValue(for: HKUnit.meter())
                let currentDistance = totalDistance.doubleValue(for: HKUnit.meter())
                totalDistance = HKQuantity(unit: HKUnit.meter(), doubleValue: currentDistance + newDistance)
                print("Total distance: \(totalDistance)")
            }
        }

        // update our user interface
        updateLabels()
    }
    
    private func updateLabels() {
        switch displayMode {
        case .distance:
            let meters = totalDistance.doubleValue(for: HKUnit.meter())
            let kilometers = meters / 1000
            let formattedKilometers = String(format: "%.2f", kilometers)

            quantityLabel.setText(formattedKilometers)
            unitLabel.setText("KILOMETERS")

        case .energy:
            let kilocalories = totalEnergyBurned.doubleValue(for: HKUnit.kilocalorie())
            let formatterKilocalories = String(format: "%.0f", kilocalories)
            quantityLabel.setText(formatterKilocalories)
            unitLabel.setText("CALORIES")

        case .heartRate:
            let heartRate = String(Int(lastHeartRate))
            quantityLabel.setText(heartRate)
            unitLabel.setText("BEATS / MINUTE")
        }
    }
    
    private func cleanUpQueries() {
        for query in activeDataQueries {
            healthStore?.stop(query)
        }

        activeDataQueries.removeAll()
    }
    
    private func save(_ workoutSession: HKWorkoutSession) {
        let config = workoutSession.workoutConfiguration
        let workout = HKWorkout(activityType: config.activityType, start: workoutStartDate, end: workoutEndDate, workoutEvents: nil, totalEnergyBurned: totalEnergyBurned, totalDistance: totalDistance, metadata: [HKMetadataKeyIndoorWorkout: false])
        
        healthStore?.save(workout) { (success, error) in
            if success {
                DispatchQueue.main.async {
                    WKInterfaceController.reloadRootPageControllers(withNames: ["InterfaceController"], contexts: nil, orientation: .horizontal, pageIndex: 0)
                }
            }
        }
    }
    
    // MARK: - Actions
    @IBAction private func changeDisplayMode() {
        switch displayMode {
        case .distance:
            displayMode = .energy
        case .energy:
            displayMode = .heartRate
        case .heartRate:
            displayMode = .distance
        }
        
        updateLabels()
    }
    
    @IBAction private func stopWorkout() {
        guard let workoutSession = workoutSession else { return }
        
        stopButton.setHidden(true)
        resumeButton.setHidden(false)
        endButton.setHidden(false)
        
        healthStore?.pause(workoutSession)
    }
    
    @IBAction private func resumeWorkout() {
        guard let workoutSession = workoutSession else { return }
        stopButton.setHidden(false)
        resumeButton.setHidden(true)
        endButton.setHidden(true)
        
        healthStore?.resumeWorkoutSession(workoutSession)
    }
    
    @IBAction private func endWorkout() {
        guard let workoutSession = workoutSession else { return }
        workoutEndDate = Date()
        
        healthStore?.end(workoutSession)
    }
}

extension WorkoutInterfaceController: HKWorkoutSessionDelegate {
    public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        switch toState {
        case .running:
            if fromState == .notStarted {
                startQueries()
            } else {
                workoutIsActive = true
            }
            
        case .paused:
            workoutIsActive = false
            
        case .ended:
            workoutIsActive = false
            
            cleanUpQueries()
            save(workoutSession)
            
        default:
            break
        }
    }
    
    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        
    }
}
