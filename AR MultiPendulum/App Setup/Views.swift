//
//  ContentView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    @EnvironmentObject var coordinator: Coordinator
    
    var body: some View {
        ZStack {
            MetalView()
                .disabled(false)
                .frame(width: UIScreen.main.bounds.height,
                       height: UIScreen.main.bounds.width)
                .rotationEffect(.degrees(90))
                .position(x: UIScreen.main.bounds.width * 0.5, y: UIScreen.main.bounds.height * 0.5)
            
            MRViewSeparator()
            
            SettingsIconView()
            
            MainSettingsView()
            
            AppTutorialView()
        }
    }
}

struct MetalView: UIViewRepresentable {
    @EnvironmentObject var coordinator: Coordinator
    
    func makeCoordinator() -> Coordinator { coordinator }
    
    func makeUIView(context: Context) -> MTKView { context.coordinator.view }
    func updateUIView(_ uiView: MTKView, context: Context) { }
}
