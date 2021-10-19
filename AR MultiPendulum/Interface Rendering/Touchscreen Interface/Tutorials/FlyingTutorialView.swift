//
//  FlyingTutorialView.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/23/21.
//

import SwiftUI

struct FlyingTutorialView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack {
                VStack {
                    Text("How to Use Flying Mode")
                        .font(.headline)
                }
                
                VStack {
                    Text("""
                    
                    Flying mode allows you to move around your surroundings and see them from a different position than where you are currently standing. You cannot interact with virtual objects when in this mode, but you can still see them along with your surroundings.
                    
                    When in flying mode, point your device's camera in the direction you intend to travel, and press and hold with your clicking hand. To switch between flying forward and backward, double-tap with your clicking hand.
                    """)
                }
            }
            .padding([.leading, .trailing, .bottom], 20)
            .fixedSize(horizontal: false, vertical: true)
        }
        .fixFlickering { $0
            .padding(.top, 20)
        }
    }
}
