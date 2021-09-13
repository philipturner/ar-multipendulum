//
//  AppTutorialView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/24/21.
//

import SwiftUI

struct AppTutorialView: View {
    @EnvironmentObject var coordinator: Coordinator
    
    struct Check: Equatable {
        var check1 = false
        var check2 = false
        var check3 = false
    }
    
    var body: some View {
        VStack {
            
        }
        .fullScreenCover(isPresented: $coordinator.showingAppTutorial) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack {
                    
                }
                .frame(height: 50)
                
                VStack {
                    VStack {
                        Text("AR MultiPendulum")
                            .font(.title)
                    }
                    
                    VStack {
                        Text("""
                        
                        AR MultiPendulum allows you to interact with virtual objects directly with your hand instead of tapping their location on a touchscreen. It brings a mesmerizing multi-pendulum simulation into augmented reality. You interact with this simulation through hand movements and modify it through a holographic interface.
                        
                        Not only does this app bring augmented reality to a pendulum simulation, it is also the first app to simulate more than three pendulums. Additionally, by repurposing a VR headset for AR, this is the first app that gives users an affordable AR headset experience.
                        
                        The interactive controls used in this app differ greatly from most other interactions on iOS. PLEASE THOROUGHLY READ THE FOLLOWING TUTORIAL BEFORE USING THIS APP.
                        
                        """)
                    }
                    
                    VStack {
                        Text("Using AR MultiPendulum")
                            .font(.title2)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("""
                        
                        To access the in-app settings panel, tap the settings icon in the top left corner of your device's screen. Since the settings icon may interfere with your AR experience, you can opt to hide it. It will automatically hide but reappear whenever you tap in the top left corner of your device's screen.
                        
                        If you have Google Cardboard, you can turn your iPhone into an AR headset that renders your surroundings in VR, based on images acquired using your device's camera. In this app, Google Cardboard is used differently than with most VR experiences. After activating "Headset Mode" in the settings panel, you will be able to read a tutorial on how to properly use Google Cardboard with this app.
                        """)
                        
                        Text("""
                        
                        In this guide, the hand that touches your device's screen will be referred to as the "clicking hand." The hand seen in your display will be referred to as the "on-screen hand."
                        
                        When touching the screen with your clicking hand, all touches will be treated the same, regardless of their location (except when touching the settings icon). Essentially, you're using a touch on the screen like clicking a mouse button. This may not feel intuitive since most other experiences on iOS use the location of your touch.
                        
                        You can highlight elements in the blue control interface by moving your on-screen hand over them. After a control is highlighted, use it by tapping anywhere on your phone's screen with your clicking hand.
                        
                        For the best experience, keep your on-screen hand so that your device's back-facing camera can see it. Keep your hand oriented so that all of your fingers are visible.
                        
                        Virtual objects are selected using the center of your palm on your on-screen hand.
                        
                        To relocate the blue control interface, highlight the gray anchor (located near the top) with your on-screen hand. With the clicking hand, press and hold anywhere on your device's touchscreen while dragging the anchor with your on-screen hand.
                        
                        To initiate interaction with the simulated pendulums, place your on-screen hand in the area where they are swinging and press and hold anywhere on the touchscreen with your clicking hand. Wait until they swing in the direction you are pointing and the simulation pauses. Move your on-screen hand and the pendulums will rotate and follow it. When you release your clicking hand, the simulation will resume.
                        
                        After activating the "Move Simulation" button in the blue control interface, the simulation will move with the position of your on-screen hand. It will follow your on-screen hand even though your clicking hand is not in contact with the screen, which is different behavior from the other interactions in this app. To end the "Move Simulation" interaction, tap anywhere on the touchscreen once with your clicking hand.
                        """)
                            .padding([.leading, .trailing], 20)
                        
                        Text("""
                        
                        Some of the latest iPhones and iPads have a built-in LiDAR scanner, which allows a device to understand the 3D shape of its surroundings. On these devices, this app uses the scanner to more realistically render your surroundings and reconstruct the 3D position of your on-screen hand. If your device has a LiDAR scanner, you will see "Scene Reconstruction" and "Hand Reconstruction" as options in the settings panel.
                        
                        """)
                        
                        if !coordinator.canCloseTutorial {
                            VStack(alignment: .leading) {
                                VStack {
                                    Toggle(isOn: $coordinator.appTutorialCheck.check1) {
                                        Text("I read the above tutorial")
                                    }
                                    
                                    Toggle(isOn: $coordinator.appTutorialCheck.check2) {
                                        Text("I know how to access the settings panel")
                                    }
                                    .disabled(!coordinator.appTutorialCheck.check1)
                                    
                                    Toggle(isOn: $coordinator.appTutorialCheck.check3) {
                                        Text("I know how to control the simulation with my on-screen hand")
                                    }
                                    .disabled(!coordinator.appTutorialCheck.check1)
                                }
                                .frame(maxWidth: UIScreen.main.bounds.width, alignment: .center)
                                
                                Text("You can access this tutorial at any time through the settings panel.")
                                    .frame(alignment: .leading)
                            }
                            .padding(.bottom, 20)
                        }
                        
                        VStack {
                            Button("Close Tutorial") {
                                coordinator.showingAppTutorial = false
                                
                                if !coordinator.canCloseTutorial {
                                    coordinator.canCloseTutorial = true
                                }
                            }
                            .disabled({
                                if coordinator.canCloseTutorial {
                                    return false
                                }
                                
                                let check = coordinator.appTutorialCheck
                                
                                return !check.check1 || !check.check2 || !check.check3
                            }())
                        }
                        .frame(maxWidth: UIScreen.main.bounds.width, alignment: .center)
                    }
                    .frame(alignment: .leading)
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

