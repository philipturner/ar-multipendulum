//
//  MainSettingsView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/23/21.
//

import SwiftUI

struct MainSettingsView: View {
    @EnvironmentObject var coordinator: Coordinator
    
    static let openAnimationDuration: Double = 0.5
    
    var body: some View {
        ZStack {
            Path { path in
                path.addRect(UIScreen.main.bounds)
            }
            .fill(Color(UIColor.systemBackground))
            .opacity(1)
            
            NavigationView {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        RenderingSettingsView()
                        
                        InteractionSettingsView()
                        
                        if coordinator.renderer.usingLiDAR {
                            LiDAREnabledSettingsView()
                        }
                        
                        if coordinator.interactionSettings.usingHandForSelection,
                           !coordinator.renderer.usingLiDAR ||
                           !coordinator.lidarEnabledSettings.allowingHandReconstruction
                        {
                            Toggle(isOn: $coordinator.interactionSettings.showingHandPosition) {
                                Text("Show Hand Position")
                            }
                        }
                        
                        Button(action: {
                            coordinator.showingAppTutorial = true
                        }) {
                            Text("App Tutorial")
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                    .padding([.leading, .trailing], 20)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .fixFlickering { $0
                    .animation(coordinator.settingsShouldBeAnimated ? .default : nil)
                    .padding(.top, 20)
                    .navigationBarTitle("Settings", displayMode: .inline)
                    .navigationBarItems(trailing: Button("Back") {
                        coordinator.settingsAreShown = false
                        
                        if coordinator.interactionSettings.canHideSettingsIcon {
                            coordinator.settingsIconIsHidden = true
                            coordinator.shouldImmediatelyHideSettingsIcon = true
                        }
                    }.font(.body))
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .offset(x: coordinator.settingsAreShown ? 0 : -UIScreen.main.bounds.width)
        .animation(coordinator.settingsAreShown ? .easeOut(duration: Self.openAnimationDuration)
                                                : .easeIn (duration: Self.openAnimationDuration))
    }
}
