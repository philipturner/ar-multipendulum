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
    var interfaceScale: Float
    
    init(_ storedSettings: UserSettings.StoredSettings) {
        doingMixedRealityRendering = storedSettings.doingMixedRealityRendering
        renderingViewSeparator     = storedSettings.renderingViewSeparator
        
        doingTwoSidedPendulums     = storedSettings.doingTwoSidedPendulums
        interfaceScale             = storedSettings.interfaceScale
    }
}

struct RenderingSettingsView: View {
    @EnvironmentObject var coordinator: Coordinator
    
    var body: some View {
        VStack(alignment: .center) {
            NavigationLink(destination: AppearanceSettingsView()) {
                Text("Customize Appearance")
            }
            
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
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private struct AppearanceSettingsView: View {
        @EnvironmentObject var coordinator: Coordinator
        
        var body: some View {
            VStack(alignment: .center) {
                Toggle(isOn: $coordinator.renderingSettings.doingTwoSidedPendulums) {
                    Text("Two-Sided Pendulums")
                }
                
                VStack {
                    Text("Control Interface Size")
                }
                .frame(maxWidth: UIScreen.main.bounds.width, alignment: .center)
                
                HStack {
                    Slider(value: $coordinator.renderingSettings.interfaceScale, in: 0.20...2.00)
                    
                    Text("\(Int(coordinator.renderingSettings.interfaceScale * 100))%")
                }
                
                
            }
            .padding(20)
            .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}
