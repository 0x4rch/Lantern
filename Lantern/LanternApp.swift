//
//  LanternApp.swift
//  Lantern
//
//  Created by Nathan on 9/13/26.
//

import SwiftUI

@main
struct LanternApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(iOS 27.1, *) {
                DuoProbeView()
            } else {
                TunerView()
            }
        }
    }
}
