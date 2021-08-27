//
//  MRViewSeparator.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/23/21.
//

import SwiftUI

struct MRViewSeparator: View {
    @EnvironmentObject var coordinator: Coordinator
    
    var body: some View {
        if coordinator.renderingSettings.doingMixedRealityRendering,
           coordinator.renderingSettings.renderingViewSeparator {
            SeparatorView()
        }
    }
    
    private struct SeparatorView: UIViewRepresentable {
        @EnvironmentObject var coordinator: Coordinator

        func makeCoordinator() -> Coordinator { coordinator }

        func makeUIView(context: Context) -> UIView { coordinator.separatorView }
        func updateUIView(_ uiView: UIView, context: Context) { }
    }
    
    static var separatorView: UIView {
        let separatorRadius: CGFloat = 1.5
        let separatorToSideDistance: CGFloat = 10
        let bounds = UIScreen.main.bounds
        
        let path = UIBezierPath()
        path.addArc(withCenter: CGPoint(x: separatorToSideDistance + separatorRadius,
                                        y: bounds.height * 0.5),
                    radius: separatorRadius,
                    startAngle: degreesToRadians(90),
                    endAngle:   degreesToRadians(270),
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width        - separatorRadius - separatorToSideDistance,
                                 y: bounds.height * 0.5 - separatorRadius))

        path.addArc(withCenter: CGPoint(x: bounds.width - separatorRadius - separatorToSideDistance,
                                        y: bounds.height * 0.5),
                    radius: separatorRadius,
                    startAngle: degreesToRadians(270),
                    endAngle:   degreesToRadians(450),
                    clockwise: true)

        path.addLine(to: CGPoint(x: separatorRadius     + separatorRadius,
                                 y: bounds.height * 0.5 + separatorRadius))
        
        path.close()
        
        
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.fillColor = UIColor.white.cgColor
        shapeLayer.lineWidth = 0
        
        let view = UIView()
        view.layer.addSublayer(shapeLayer)
        return view
    }
}
