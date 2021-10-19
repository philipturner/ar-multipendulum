//
//  Coordinator.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 10/5/21.
//

import ARHeadsetKit
import SwiftUI

class Coordinator: AppCoordinator {
    @Published var doingTwoSidedPendulums: Bool = false
    
    override var makeMainRenderer: MainRendererInitializer {
        AR_MultiPendulumRenderer.init
    }
    
    static func createAppDescription() -> AppDescription {
        let name = "AR MultiPendulum"
        
        let summary = """
        AR MultiPendulum allows you to interact with virtual objects directly with your hand instead of tapping their location on a touchscreen. It brings a mesmerizing multi-pendulum simulation into augmented reality. You interact with this simulation through hand movements and modify it through a holographic interface.
        
        Not only does this app bring augmented reality to a pendulum simulation, it is also the first app to simulate more than three pendulums. Additionally, by repurposing a VR headset for AR, this is the first app that gives users an affordable AR headset experience.
        """
        
        let controlInterfaceColor = "blue"
        
        let tutorialExtension = """
        To relocate the blue control interface, highlight the gray anchor (located near the top) with your on-screen hand. With the clicking hand, press and hold anywhere on your device's touchscreen while dragging the anchor with your on-screen hand.
        
        To initiate interaction with the simulated pendulums, place your on-screen hand in the area where they are swinging and press and hold anywhere on the touchscreen with your clicking hand. Wait until they swing in the direction you are pointing and the simulation pauses. Move your on-screen hand and the pendulums will rotate and follow it. When you release your clicking hand, the simulation will resume.
        
        After activating the "Move Simulation" button in the blue control interface, the simulation will move with the position of your on-screen hand. It will follow your on-screen hand even though your clicking hand is not in contact with the screen, which is different behavior from the other interactions in this app. To end the "Move Simulation" interaction, tap anywhere on the touchscreen once with your clicking hand.
        """
        
        let mainActivity = "control the simulation"
        
        return AppDescription(name:              name,
                              summary:           summary,
                              controlInterfaceColor: controlInterfaceColor,
                              tutorialExtension: tutorialExtension,
                              mainActivity:      mainActivity)
    }
    
    override func initializeCustomSettings(from storedSettings: [String : String]) {
        if storedSettings["doingTwoSidedPendulums"] == String(true) {
            doingTwoSidedPendulums = true
        }
    }
    
    override func modifyCustomSettings(customSettings: inout [String : String]) {
        customSettings["doingTwoSidedPendulums"] = String(doingTwoSidedPendulums)
    }
}
