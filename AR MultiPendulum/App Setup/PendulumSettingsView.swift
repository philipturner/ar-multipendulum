//
//  PendulumSettingsView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 10/5/21.
//

import ARHeadsetKit
import SwiftUI

struct PendulumSettingsView: CustomRenderingSettingsView {
    @ObservedObject var coordinator: Coordinator
    init(c: Coordinator) { coordinator = c }
    
    public var body: some View {
        Toggle(isOn: $coordinator.doingTwoSidedPendulums) {
            Text("Two-Sided Pendulums")
        }
    }
}
