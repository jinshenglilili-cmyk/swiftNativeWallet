//
//  MainTabView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var profileVM = ProfileViewModel()

    var body: some View {
        TabView {
            homeTab
            browserTab
            profileTab
        }
        .environmentObject(profileVM)
    }
}

extension MainTabView {

    private var homeTab: some View {
        NavigationView {
            HomeView()
                .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tabItem {
            Image(systemName: "house.fill")
            Text("首页")
        }
        .tag(0)
    }

    private var browserTab: some View {
        BrowserTabView()
            .tabItem {
                Image(systemName: "safari.fill")
                Text("浏览")
            }
            .tag(1)
    }

    private var profileTab: some View {
        Group {
            if #available(iOS 16.0, *) {
                // NavigationStack 修复了老 NavigationView 的 pop 过渡 bug：
                // 父页面隐藏导航栏 + 子页面显示导航栏时，返回会导致列表条目闪动
                NavigationStack {
                    ProfileView()
                        .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                NavigationView {
                    ProfileView()
                        .navigationBarHidden(true)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .tabItem {
            Image(systemName: "person.fill")
            Text("我的")
        }
        .tag(2)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(DeveloperPreview.instance.homeVM)
    }
}
