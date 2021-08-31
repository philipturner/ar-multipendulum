//
//  SwiftUIExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/23/21.
//

import SwiftUI

extension ScrollView {
    
    func fixFlickering() -> some View {
        fixFlickering { $0 }
    }
    
    func fixFlickering<T: View>(@ViewBuilder configurator: @escaping (ScrollView<AnyView>) -> T) -> some View {
        GeometryReader { geometryWithSafeArea in
            GeometryReader { _ in
                configurator(
                ScrollView<AnyView>(axes, showsIndicators: showsIndicators) {
                    AnyView(
                        VStack {
                            content
                        }
                        .padding(.top, geometryWithSafeArea.safeAreaInsets.top)
                        .padding(.bottom, geometryWithSafeArea.safeAreaInsets.bottom)
                        .padding(.leading, geometryWithSafeArea.safeAreaInsets.leading)
                        .padding(.trailing, geometryWithSafeArea.safeAreaInsets.trailing)
                    )
                })
            }
            .edgesIgnoringSafeArea(.all)
        }
    }
    
}
