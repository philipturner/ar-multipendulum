//
//  AR_MultiPendulumApp.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import SwiftUI

@main
struct AR_MultiPendulumApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.all)
                .environmentObject(Coordinator())
        }
    }
}
