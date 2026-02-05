//
//  ContentView.swift
//  TabBarDemo
//
//  Created by lynnswap on 2025/12/31.
//

import SwiftUI
import TabBarMenuDemoSupport

struct ContentView: View {
    @AppStorage("selectedTab") private var mode: TabBarMenuPreviewMode = .uiTab

    var body: some View {
        NavigationStack {
            TabBarMenuPreviewScreen(mode: mode)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        modePicker
                    }
                }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Text("UITab").tag(TabBarMenuPreviewMode.uiTab)
            Text("VC").tag(TabBarMenuPreviewMode.uiTabBarItem)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

#Preview {
    ContentView()
}
