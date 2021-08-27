//
//  RenderingSettingsView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/23/21.
//

import SwiftUI

struct RenderingSettings {
    var doingMixedRealityRendering: Bool
    var renderingViewSeparator: Bool
    var usingModifiedPerspective: Bool = false
    var doingTwoSidedPendulums: Bool
    
    init(_ storedSettings: UserSettings.StoredSettings) {
        doingMixedRealityRendering = storedSettings.doingMixedRealityRendering
        renderingViewSeparator     = storedSettings.renderingViewSeparator
        doingTwoSidedPendulums     = storedSettings.doingTwoSidedPendulums
    }
}

struct RenderingSettingsView: View {
    @EnvironmentObject var coordinator: Coordinator
    
    var body: some View {
        VStack(alignment: .center) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle(isOn: $coordinator.renderingSettings.doingMixedRealityRendering) {
                    Text("Headset Mode")
                }
                
                if coordinator.renderingSettings.doingMixedRealityRendering {
                    Toggle(isOn: $coordinator.renderingSettings.renderingViewSeparator) {
                        Text("Show View Separator")
                    }
                    
                    NavigationLink(destination: HeadsetTutorialView()) {
                        Text("How to Use Google Cardboard")
                    }
                }
            }
            
            Toggle(isOn: $coordinator.renderingSettings.usingModifiedPerspective) {
                Text("Flying Mode")
            }
            
            if coordinator.renderingSettings.usingModifiedPerspective {
                NavigationLink(destination: FlyingTutorialView()) {
                    Text("How to Use Flying Mode")
                }
            }
            
            Toggle(isOn: $coordinator.renderingSettings.doingTwoSidedPendulums) {
                Text("Two-Sided Pendulums")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
