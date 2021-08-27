//
//  AppTutorialView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/24/21.
//

import SwiftUI

struct AppTutorialView: View {
    @EnvironmentObject var coordinator: Coordinator
    
    var body: some View {
        VStack {
            
        }
        .sheet(isPresented: $coordinator.showingAppTutorial) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack {
                    
                }
                .frame(height: 100)
                
                VStack {
                    VStack(alignment: .center) {
                        Text("AR MultiPendulum")
                            .font(.title)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("""
                        
                        AR MultiPendulum allows you to interact with virtual objects directly with your hand instead of tapping their location on a touchscreen. It brings a mesmerizing multi-pendulum simulation into augmented reality. You interact with this simulation through hand movements and modify it through a holographic interface.
                        
                        Not only does this app bring augmented reality to a pendulum simulation, it is also the first app to simulate more than two pendulums. Additionally, by repurposing a VR headset for AR, this is the first app that gives users an affordable AR headset experience.
                        
                        """)
                    }
                    .frame(maxWidth: UIScreen.main.bounds.width, alignment: .leading)
                    
                    VStack(alignment: .center) {
                        Text("Using AR MultiPendulum")
                            .font(.title2)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("""
                        
                        To access the in-app settings panel, tap the settings icon in the top left. Since it may interfere with your AR experience, you can opt to hide the settings icon. In this case, it will automatically hide, but reappear whenever you tap in the top left.
                        
                        If you have Google Cardboard, you can turn your iPhone into an AR headset that renders your surroundings in VR, based on images acquired using your device's camera.
                        """)
                        
                        Text("""
                        
                        When interacting with the simulated interface, you will sometimes need to touch your device's screen to confirm an action, much like you use a button on a mouse.
                        
                        The hand that touches your device's screen will be referred to as the "clicking hand." The one seen in your display will be referred to as the "on-screen hand."
                        
                        You can highlight elements in the blue control interface by moving your on-screen hand over them. After a control is highlighted, use it by tapping your phone's screen with your clicking hand.
                        
                        For the best experience, keep your on-screen hand so that your device's back camera can see it. Keep it oriented so that all of your fingers are visible. Virtual objects will be selected with the center of your on-screen hand's palm.
                        
                        To relocate the blue control interface, highlight the gray anchor (located near the top) with your on-screen hand. With the clicking hand, press and hold your device's touchscreen while dragging the anchor with your on-screen hand.
                        
                        To initiate interaction with the simulated pendulums, place your on-screen hand in the area where they are swinging and press and hold on the touchscreen with your clicking hand. Wait until they swing in the direction you are pointing and the simulation pauses. Move your on-screen hand and the pendulums will rotate and follow it. When you release your clicking hand, the simulation will resume.
                        
                        After activating the "Move Simulation" button in the blue control interface, the simulation will move with the position of your on-screen hand. To end the interaction, tap the touchscreen once with your clicking hand.
                        """)
                            .padding([.leading, .trailing], 20)
                        
                        Text("""
                        
                        Some of the latest iOS devices have a built-in LiDAR scanner, which allows the device to understand the 3D shape of its surroundings. On these devices, this app uses the scanner to more realistically render your surroundings and reconstruct the 3D position of your on-screen hand. If your device has a LiDAR scanner, you will see “Scene Reconstruction" and “Hand Reconstruction" as options in the settings panel.
                        """)
                    }
                    .frame(maxWidth: UIScreen.main.bounds.width, alignment: .leading)
                }
                .padding([.leading, .trailing, .bottom], 20)
                .fixedSize(horizontal: false, vertical: true)
            }
            .fixFlickering { $0
                .frame(maxWidth: UIScreen.main.bounds.width, alignment: .center)
            }
        }
    }
}

