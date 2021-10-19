//
//  ContentView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 10/7/21.
//

import SwiftUI
import ARHeadsetKit

struct ContentView: View {
    var body: some View {
        let description = Coordinator.createAppDescription()
        
        ARContentView<PendulumSettingsView>()
            .environmentObject(Coordinator(appDescription: description))
    }
}
